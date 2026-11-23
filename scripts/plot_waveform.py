#!/usr/bin/env python3
"""Draw selected signals of sim/waveforms/demo.vcd as an SVG waveform.

    python3 scripts/plot_waveform.py                  # writes docs/figures/waveform.svg
    rsvg-convert -f png -z 2 -o docs/figures/waveform.png docs/figures/waveform.svg
    rsvg-convert -f pdf -o docs/figures/waveform.pdf docs/figures/waveform.svg

The plot is made from the simulator's own VCD, not drawn by hand. Standard
library only: GTKWave and matplotlib are not needed.
"""
import sys

VCD = "sim/waveforms/demo.vcd"
OUT = "docs/figures/waveform.svg"
ARRAY = "tb_demo.uut.u_array.u_systolic_array"


def s8(v, i):
    b = (v >> (8 * i)) & 0xFF
    return b - 256 if b > 127 else b


def s32(v, i):
    w = (v >> (32 * i)) & 0xFFFFFFFF
    return w - (1 << 32) if w >> 31 else w


def bits3(v):
    return format(v, "03b")


# label, VCD path, formatter (None = 1-bit signal)
SIGNALS = [
    ("clk", "tb_demo.clk", None),
    ("start", "tb_demo.start", None),
    ("load", "tb_demo.uut.load", None),
    ("run", "tb_demo.uut.run", None),
    ("t", "tb_demo.uut.t", str),
    ("valid_a_in", "tb_demo.uut.valid_a_in", bits3),
    ("a_in rows 0,1,2", "tb_demo.uut.a_in_flat", lambda v: ",".join(str(s8(v, i)) for i in range(3))),
    ("b_in cols 0,1,2", "tb_demo.uut.b_in_flat", lambda v: ",".join(str(s8(v, i)) for i in range(3))),
    ("acc PE(0,0)", ARRAY + ".GEN_ROW[0].GEN_COL[0].pe_acc", lambda v: str(s32(v, 0))),
    ("acc PE(1,1)", ARRAY + ".GEN_ROW[1].GEN_COL[1].pe_acc", lambda v: str(s32(v, 0))),
    ("acc PE(2,2)", ARRAY + ".GEN_ROW[2].GEN_COL[2].pe_acc", lambda v: str(s32(v, 0))),
    ("capture", "tb_demo.uut.capture", None),
    ("done", "tb_demo.done", None),
    ("C[0][0], C[2][2]", "tb_demo.c_flat", lambda v: "%d, %d" % (s32(v, 0), s32(v, 8))),
]


def read_vcd(path):
    """Return {hierarchical name: [(time, int value or None for x/z)]}."""
    ids, scope, changes, now = {}, [], {}, 0
    with open(path) as f:
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == "$scope":
                scope.append(tok[2])
            elif tok[0] == "$upscope":
                scope.pop()
            elif tok[0] == "$var":
                ids.setdefault(tok[3], []).append(".".join(scope + [tok[4]]))
            elif tok[0].startswith("#"):
                now = int(tok[0][1:])
            elif tok[0][0] in "bB":
                val, code = tok[0][1:], tok[1]
                for name in ids.get(code, []):
                    changes.setdefault(name, []).append((now, None if set(val) & set("xXzZ") else int(val, 2)))
            elif tok[0][0] in "01xXzZ" and not tok[0].startswith("$"):
                val, code = tok[0][0], tok[0][1:]
                for name in ids.get(code, []):
                    changes.setdefault(name, []).append((now, int(val) if val in "01" else None))
    return changes


def window(changes):
    """From one cycle before start rises to two cycles after done rises."""
    rise = lambda name: next(t for t, v in changes[name] if v == 1)
    return rise("tb_demo.start") - 10000, rise("tb_demo.done") + 20000


def main():
    ch = read_vcd(VCD)
    t0, t1 = window(ch)
    LABEL_W, ROW_H, H, X_PER_PS = 130, 26, 16, 0.006  # 60 px per 10 ns cycle
    width = LABEL_W + (t1 - t0) * X_PER_PS + 10
    height = ROW_H * len(SIGNALS) + 10
    x = lambda t: LABEL_W + (min(max(t, t0), t1) - t0) * X_PER_PS
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
           'font-family="Helvetica, Arial, sans-serif" font-size="11">' % (width, height),
           '<rect width="100%" height="100%" fill="white"/>']
    # rising clock edges as faint grid lines
    for t, v in ch["tb_demo.clk"]:
        if v == 1 and t0 <= t <= t1:
            out.append('<line x1="%.1f" y1="0" x2="%.1f" y2="%d" stroke="#ddd"/>' % (x(t), x(t), height))
    for row, (label, name, fmt) in enumerate(SIGNALS):
        if name not in ch:
            sys.exit("signal not in VCD: " + name)
        top = 6 + row * ROW_H
        lo, hi = top + H, top
        out.append('<text x="4" y="%d">%s</text>' % (top + 12, label))
        # value at t0, then every change inside the window
        segs, cur = [], None
        for t, v in ch[name]:
            if t <= t0:
                cur = v
            elif t < t1:
                segs.append((t0 if not segs else segs[-1][1], t, cur))
                cur = v
        segs.append((t0 if not segs else segs[-1][1], t1, cur))
        for a, b, v in segs:
            xa, xb = x(a), x(b)
            if fmt is None:
                y = hi if v == 1 else lo
                out.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#1a5fb4" stroke-width="1.5"/>' % (xa, y, xb, y))
                out.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#1a5fb4" stroke-width="1.5"/>' % (xa, hi, xa, lo))
            else:
                d = min(3, (xb - xa) / 2)
                mid = (hi + lo) / 2
                out.append('<polygon points="%.1f,%.1f %.1f,%d %.1f,%d %.1f,%.1f %.1f,%d %.1f,%d" '
                           'fill="#eef3fb" stroke="#1a5fb4"/>' % (xa, mid, xa + d, hi, xb - d, hi, xb, mid, xb - d, lo, xa + d, lo))
                text = "x" if v is None else fmt(v)
                if (xb - xa) > 6 * len(text):
                    out.append('<text x="%.1f" y="%d" text-anchor="middle">%s</text>' % ((xa + xb) / 2, top + 12, text))
    out.append("</svg>")
    with open(OUT, "w") as f:
        f.write("\n".join(out) + "\n")
    print("wrote " + OUT)


if __name__ == "__main__":
    main()
