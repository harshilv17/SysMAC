#!/usr/bin/env python3
"""Reference model for SysMAC, the 3x3 systolic matrix multiplier.

It follows docs/port_spec.md exactly: signed 8-bit operands, signed 32-bit
accumulators, row-major packing, the controller FSM

    IDLE -> LOAD -> COMPUTE (t = 0..6) -> CAPTURE -> DONE -> IDLE

and the skew rule of input_scheduler: row i carries A[i][t-i] and column j
carries B[t-j][j] when the index is in 0..2.

It contains three independent descriptions of the same computation:

  matmul        the textbook triple loop, the definition of "correct"
  ArrayModel    a register-level model of systolic_array_3x3, advanced one
                clock edge at a time, with both valid flags
  seq_order     the one-MAC-per-cycle order used by rtl/seq_matmul.v

They are checked against each other (and against NumPy if installed) before
any file is written. The vector files are what the Verilog testbenches load.

Standard library only.

Usage (run from the repo root):
  python3 scripts/reference_model.py selfcheck
  python3 scripts/reference_model.py vectors            # writes sim/vectors/
  python3 scripts/reference_model.py wavefront          # what each PE does per cycle
  python3 scripts/reference_model.py schedule           # scheduler outputs for the demo matrices
  python3 scripts/reference_model.py cycles             # cycle counts and widths for several N
"""

import argparse
import os
import random

N = 3
DATA_W = 8
ACC_W = 32
LO, HI = -128, 127

# Cycle counts in the convention of tb/tb_accelerator_top.v: posedges from
# the edge that samples start up to and including the edge after which done
# is visible.
SYS_LATENCY = 1 + 1 + (3 * N - 2) + 1   # sample start, LOAD, COMPUTE, CAPTURE = 10
SEQ_LATENCY = 1 + 1 + N ** 3            # sample start, LOAD, COMPUTE = 29


# --------------------------------------------------------------------------
# The definition
# --------------------------------------------------------------------------

def matmul(a, b):
    n = len(a)
    return [[sum(a[i][k] * b[k][j] for k in range(n)) for j in range(n)]
            for i in range(n)]


# --------------------------------------------------------------------------
# input_scheduler
# --------------------------------------------------------------------------

def schedule(a, b, t, run=True):
    """Edge inputs at compute cycle t: (a_in, b_in, valid_a, valid_b), lists of N."""
    n = len(a)
    a_in, b_in, va, vb = [], [], [], []
    for r in range(n):
        k = t - r
        ok = run and 0 <= k < n
        a_in.append(a[r][k] if ok else 0)
        va.append(1 if ok else 0)
        b_in.append(b[k][r] if ok else 0)
        vb.append(1 if ok else 0)
    return a_in, b_in, va, vb


# --------------------------------------------------------------------------
# systolic_array_3x3, register by register
# --------------------------------------------------------------------------

class ArrayModel:
    """Every register of the array. step() is one rising clock edge."""

    def __init__(self, n=N):
        self.n = n
        self.clear()

    def clear(self):
        n = self.n
        z = lambda: [[0] * n for _ in range(n)]
        self.a_out, self.b_out, self.va_out, self.vb_out, self.acc = z(), z(), z(), z(), z()

    def step(self, a_in, b_in, va, vb):
        """Returns the map of PEs that did a MAC on this edge, and the terms."""
        n = self.n
        z = lambda: [[0] * n for _ in range(n)]
        na, nb, nva, nvb = z(), z(), z(), z()
        active, terms = z(), [[None] * n for _ in range(n)]
        for i in range(n):
            for j in range(n):
                ai = a_in[i] if j == 0 else self.a_out[i][j - 1]
                vai = va[i] if j == 0 else self.va_out[i][j - 1]
                bi = b_in[j] if i == 0 else self.b_out[i - 1][j]
                vbi = vb[j] if i == 0 else self.vb_out[i - 1][j]
                na[i][j], nb[i][j], nva[i][j], nvb[i][j] = ai, bi, vai, vbi
                if vai and vbi:
                    self.acc[i][j] += ai * bi
                    active[i][j] = 1
                    terms[i][j] = (ai, bi)
                # The two flags always agree in this dataflow. If they ever
                # disagree the skew is wrong, so the model refuses to go on.
                assert vai == vbi, "valid_a and valid_b disagree at PE(%d,%d)" % (i, j)
        self.a_out, self.b_out, self.va_out, self.vb_out = na, nb, nva, nvb
        return active, terms


def systolic_run(a, b):
    """One job. Returns (C, trace); trace[t] is the state after compute edge t."""
    n = len(a)
    arr = ArrayModel(n)
    trace = []
    for t in range(3 * n - 2):
        a_in, b_in, va, vb = schedule(a, b, t)
        active, terms = arr.step(a_in, b_in, va, vb)
        trace.append({"t": t, "a_in": a_in, "b_in": b_in, "va": va, "vb": vb,
                      "active": active, "terms": terms,
                      "acc": [row[:] for row in arr.acc]})
    return arr.acc, trace


# --------------------------------------------------------------------------
# seq_matmul
# --------------------------------------------------------------------------

def seq_order(a, b):
    n = len(a)
    c = [[0] * n for _ in range(n)]
    macs = 0
    for i in range(n):
        for j in range(n):
            acc = 0
            for k in range(n):
                acc += a[i][k] * b[k][j]
                macs += 1
            c[i][j] = acc
    return c, macs


# --------------------------------------------------------------------------
# Test cases
# --------------------------------------------------------------------------

def directed_cases(n=N):
    """Each case is here to catch a particular kind of mistake."""
    const = lambda v: [[v] * n for _ in range(n)]
    ident = [[int(i == j) for j in range(n)] for i in range(n)]
    ramp = [[i * n + j + 1 for j in range(n)] for i in range(n)]
    rev = [[n * n - (i * n + j) for j in range(n)] for i in range(n)]
    neg = [[-(i * n + j + 1) for j in range(n)] for i in range(n)]
    check = [[HI if (i + j) % 2 == 0 else LO for j in range(n)] for i in range(n)]

    def one(i, j, v):
        m = const(0)
        m[i][j] = v
        return m

    return [
        ("demo, expect [[30,24,18],[84,69,54],[138,114,90]]", ramp, rev),
        ("zeros", const(0), const(0)),
        ("A times identity gives A", ramp, ident),
        ("identity times B gives B", ident, neg),
        ("all -128: largest positive sum, 49152", const(LO), const(LO)),
        ("all 127", const(HI), const(HI)),
        ("-128 times 127: most negative sum", const(LO), const(HI)),
        ("alternating -128 and 127", check, check),
        ("mixed sign ramps", ramp, neg),
        ("single element in the first corner", one(0, 0, 7), one(0, 0, -9)),
        ("single element in the far corner", one(n - 1, n - 1, -5), one(n - 1, n - 1, 11)),
        ("B transposed by mistake gives a different answer", ramp,
         [list(r) for r in zip(*neg)]),
    ]


def random_cases(count, seed, n=N):
    rng = random.Random(seed)
    out = []
    for c in range(count):
        a = [[rng.randint(LO, HI) for _ in range(n)] for _ in range(n)]
        b = [[rng.randint(LO, HI) for _ in range(n)] for _ in range(n)]
        out.append(("random %d" % c, a, b))
    return out


# --------------------------------------------------------------------------
# Packing, exactly as docs/port_spec.md
# --------------------------------------------------------------------------

def pack(values, width):
    """values[0] goes in the lowest bits."""
    word = 0
    for e, v in enumerate(values):
        word |= (v & ((1 << width) - 1)) << (e * width)
    return word


def flat(m):
    return [v for row in m for v in row]


def hexw(word, bits):
    return "%0*x" % ((bits + 3) // 4, word)


def write_vectors(out_dir, n_random, seed):
    """Write the files the testbenches load with $readmemh.

    jobs_a.hex      one job per line: a_flat, 72 bits
    jobs_b.hex      one job per line: b_flat, 72 bits
    jobs_c.hex      one job per line: expected c_flat, 288 bits
    jobs.txt        line number and name of each job
    trace_in.hex    one compute cycle per line, 7 lines per job:
                    {valid_b_in[2:0], valid_a_in[2:0], b_in_flat[23:0], a_in_flat[23:0]}
                    = what input_scheduler must output, and what the array
                    must be fed, at t = 0..6
    trace_c.hex     one compute cycle per line: every accumulator (c_flat of
                    systolic_array_3x3, 288 bits) just after that cycle's edge
    """
    os.makedirs(out_dir, exist_ok=True)
    cases = directed_cases() + random_cases(n_random, seed)
    files = {k: open(os.path.join(out_dir, k), "w") for k in
             ("jobs_a.hex", "jobs_b.hex", "jobs_c.hex", "jobs.txt",
              "trace_in.hex", "trace_c.hex")}
    for idx, (name, a, b) in enumerate(cases):
        want = matmul(a, b)
        got, trace = systolic_run(a, b)
        seq, _ = seq_order(a, b)
        if got != want or seq != want:
            raise AssertionError("models disagree on job %d (%s)" % (idx, name))
        files["jobs_a.hex"].write(hexw(pack(flat(a), DATA_W), N * N * DATA_W) + "\n")
        files["jobs_b.hex"].write(hexw(pack(flat(b), DATA_W), N * N * DATA_W) + "\n")
        files["jobs_c.hex"].write(hexw(pack(flat(want), ACC_W), N * N * ACC_W) + "\n")
        files["jobs.txt"].write("%3d  %s\n" % (idx, name))
        for s in trace:
            word = (pack(s["a_in"], DATA_W)
                    | pack(s["b_in"], DATA_W) << (N * DATA_W)
                    | pack(s["va"], 1) << (2 * N * DATA_W)
                    | pack(s["vb"], 1) << (2 * N * DATA_W + N))
            files["trace_in.hex"].write(hexw(word, 2 * N * DATA_W + 2 * N) + "\n")
            files["trace_c.hex"].write(hexw(pack(flat(s["acc"]), ACC_W), N * N * ACC_W) + "\n")
    for f in files.values():
        f.close()
    return len(cases)


# --------------------------------------------------------------------------
# Printouts
# --------------------------------------------------------------------------

def print_wavefront(n=N):
    class Sym(int):
        def __new__(cls, tag):
            obj = int.__new__(cls, 1)
            obj.tag = tag
            return obj

    a = [[Sym("a%d%d" % (i, k)) for k in range(n)] for i in range(n)]
    b = [[Sym("b%d%d" % (k, j)) for j in range(n)] for k in range(n)]
    arr = ArrayModel(n)
    head = "  t | busy | " + " | ".join("PE(%d,%d)" % (i, j) for i in range(n) for j in range(n))
    print(head)
    print("-" * len(head))
    busy_total = 0
    for t in range(3 * n - 2):
        active, terms = arr.step(*schedule(a, b, t))
        cells, busy = [], 0
        for i in range(n):
            for j in range(n):
                if active[i][j]:
                    x, y = terms[i][j]
                    cells.append("%s*%s" % (x.tag, y.tag))
                    busy += 1
                else:
                    cells.append("   .   ")
        busy_total += busy
        print("%3d | %4d | %s" % (t, busy, " | ".join(cells)))
    slots = n * n * (3 * n - 2)
    print("\n%d useful MACs in %d PE-cycles: utilisation %.1f%%"
          % (busy_total, slots, 100.0 * busy_total / slots))


def print_schedule():
    """The check table for input_scheduler with the demo matrices."""
    _, a, b = directed_cases()[0]
    print("demo A = %s\ndemo B = %s\n" % (a, b))
    print("  t | row0 row1 row2 | valid_a | col0 col1 col2 | valid_b")
    for t in range(-1, 3 * N - 2):
        a_in, b_in, va, vb = schedule(a, b, t, run=t >= 0)
        print("%3s | %4d %4d %4d |   %s   | %4d %4d %4d |   %s"
              % (t if t >= 0 else "off", *a_in, "".join(map(str, va[::-1])),
                 *b_in, "".join(map(str, vb[::-1]))))
    print("\nvalid bits printed MSB first ([2:0]). 'off' means run = 0.")


def width_exact(n, w=DATA_W):
    """Smallest signed width that holds N * (-2^(W-1))^2, the largest sum."""
    worst = n * (1 << (2 * w - 2))
    bits = 1
    while (1 << (bits - 1)) - 1 < worst:
        bits += 1
    return bits


def print_cycles():
    print("  N | MACs | seq compute | sys compute | seq start->done | sys start->done |"
          " ratio | utilisation | min acc bits")
    for n in (2, 3, 4, 8, 16):
        seq_lat, sys_lat = 2 + n ** 3, 3 + (3 * n - 2)
        print("%3d | %4d | %11d | %11d | %15d | %15d | %5.2f | %10.1f%% | %12d"
              % (n, n ** 3, n ** 3, 3 * n - 2, seq_lat, sys_lat, seq_lat / sys_lat,
                 100.0 * n ** 3 / (n * n * (3 * n - 2)), width_exact(n)))
    print("\nstart->done counts as tb/tb_accelerator_top.v does (N=3: %d and %d)."
          % (SYS_LATENCY, SEQ_LATENCY))
    print("Ratios are in cycles only: the array has N*N multipliers, the baseline one.")


def selfcheck():
    try:
        import numpy as np
    except ImportError:
        np = None
    total = 0
    for n in (2, 3, 4, 5, 8):
        for name, a, b in directed_cases(n) + random_cases(300, 7 + n, n):
            want = matmul(a, b)
            got, trace = systolic_run(a, b)
            seq, macs = seq_order(a, b)
            assert got == want and seq == want, (n, name)
            assert macs == n ** 3 and len(trace) == 3 * n - 2
            for i in range(n):
                for j in range(n):
                    when = [s["t"] for s in trace if s["active"][i][j]]
                    assert when == list(range(i + j, i + j + n)), (n, i, j, when)
            if np is not None:
                assert (np.array(a, dtype=np.int64) @ np.array(b, dtype=np.int64)).tolist() == want
            total += 1
    assert matmul(*directed_cases()[0][1:]) == [[30, 24, 18], [84, 69, 54], [138, 114, 90]]
    print("selfcheck passed: %d jobs, N = 2 3 4 5 8, numpy %s"
          % (total, "agrees" if np is not None else "not installed"))


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("selfcheck")
    v = sub.add_parser("vectors")
    v.add_argument("--random", type=int, default=100)
    v.add_argument("--seed", type=int, default=2026)
    v.add_argument("--out", default="sim/vectors")
    sub.add_parser("wavefront")
    sub.add_parser("schedule")
    sub.add_parser("cycles")
    args = p.parse_args()
    if args.cmd == "selfcheck":
        selfcheck()
    elif args.cmd == "vectors":
        print(write_vectors(args.out, args.random, args.seed))
    elif args.cmd == "wavefront":
        print_wavefront()
    elif args.cmd == "schedule":
        print_schedule()
    else:
        print_cycles()


if __name__ == "__main__":
    main()
