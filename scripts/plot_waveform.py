#!/usr/bin/env python3
"""Draw the demo job of sim/waveforms/demo.vcd as an annotated SVG waveform.

    python3 scripts/plot_waveform.py                  # writes docs/figures/waveform.svg
    rsvg-convert -f png -z 2 -o docs/figures/waveform.png docs/figures/waveform.svg
    rsvg-convert -f pdf -o docs/figures/waveform.pdf docs/figures/waveform.svg

The plot is made from the simulator's own VCD, not drawn by hand: controller
state bands, numbered clock edges, the skewed operands one row and column at a
time (blank while the valid flag is 0), the number of cells doing a MAC in each
cycle, three accumulators and the result. Standard library only: GTKWave and
matplotlib are not needed.
"""
import sys

VCD = "sim/waveforms/demo.vcd"
OUT = "docs/figures/waveform.svg"
TOP = "tb_demo.uut"
ARRAY = TOP + ".u_array.u_systolic_array"
PE = ARRAY + ".GEN_ROW[%d].GEN_COL[%d]"
STATES = {0: "IDLE", 1: "LOAD", 2: "COMPUTE", 3: "CAPTURE", 4: "DONE"}
BAND = {"IDLE": "#f1f3f5", "LOAD": "#ffe8cc", "COMPUTE": "#d3f9d8", "CAPTURE": "#d0ebff", "DONE": "#e5dbff"}
BAND_TEXT = {"IDLE": "#868e96", "LOAD": "#d9480f", "COMPUTE": "#2b8a3e", "CAPTURE": "#1971c2", "DONE": "#6741d9"}
LINE, FILL = "#1a5fb4", "#eef3fb"


def s8(v, i):
    b = (v >> (8 * i)) & 0xFF
    return b - 256 if b > 127 else b


def s32(v, i):
    w = (v >> (32 * i)) & 0xFFFFFFFF
    return w - (1 << 32) if w >> 31 else w


def bit(v, i):
    return (v >> i) & 1


def operand(n):
    """Operand n of a skewed edge bus, or blank while its valid flag is 0."""
    return lambda v: str(s8(v[0], n)) if bit(v[1], n) else ""


def busy(v):
    """Cells whose two valid flags are both 1: they add a product at the next edge."""
    return str(sum(v[2 * c] & v[2 * c + 1] for c in range(9)))


PE_VALIDS = [PE % (r, c) + ".u_pe." + f for r in range(3) for c in range(3) for f in ("valid_a_in", "valid_b_in")]

# label, kind, VCD paths, formatter (kind "bit" = 1-bit signal drawn as a line)
SIGNALS = [
    ("clk", "bit", ["tb_demo.clk"], None),
    ("start", "bit", ["tb_demo.start"], None),
    ("t", "bus", [TOP + ".t"], lambda v: str(v[0])),
    ("load, clear", "bit", [TOP + ".load"], None),
    ("run", "bit", [TOP + ".run"], None),
] + [
    ("row %d in (A)" % n, "stair", [TOP + ".a_in_flat", TOP + ".valid_a_in"], operand(n)) for n in range(3)
] + [
    ("col %d in (B)" % n, "stair", [TOP + ".b_in_flat", TOP + ".valid_b_in"], operand(n)) for n in range(3)
] + [
    ("busy cells", "busy", PE_VALIDS, busy),
    ("acc PE(0,0)", "bus", [PE % (0, 0) + ".pe_acc"], lambda v: str(s32(v[0], 0))),
    ("acc PE(1,1)", "bus", [PE % (1, 1) + ".pe_acc"], lambda v: str(s32(v[0], 0))),
    ("acc PE(2,2)", "bus", [PE % (2, 2) + ".pe_acc"], lambda v: str(s32(v[0], 0))),
    ("capture", "bit", [TOP + ".capture"], None),
    ("done", "bit", ["tb_demo.done"], None),
    ("C[0][0], C[2][2]", "bus", ["tb_demo.c_flat"], lambda v: "%d, %d" % (s32(v[0], 0), s32(v[0], 8))),
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


def value_at(chg, t):
    cur = None
    for tt, v in chg:
        if tt > t:
            break
        cur = v
    return cur


def segments(ch, names, fmt, t0, t1):
    """[(start, end, shown value)] inside [t0, t1], merging changes of every name."""
    for name in names:
        if name not in ch:
            sys.exit("signal not in VCD: " + name)
    times = sorted({t for n in names for t, _ in ch[n] if t0 < t < t1})
    show = lambda t: fmt([value_at(ch[n], t) for n in names]) if all(
        value_at(ch[n], t) is not None for n in names) else "x"
    segs = [[t0, t1, show(t0)]]
    for t in times:
        v = show(t)
        if v != segs[-1][2]:
            segs[-1][1] = t
            segs.append([t, t1, v])
    return segs


def main():
    ch = read_vcd(VCD)
    clk_rises = [t for t, v in ch["tb_demo.clk"] if v == 1]
    period = clk_rises[1] - clk_rises[0]
    state = ch[TOP + ".u_ctrl.state"]
    # edge 1 is the rising edge on which the controller leaves IDLE for LOAD
    edge1 = next(t for t in clk_rises if value_at(state, t - 1) == 0 and value_at(state, t + 1) == 1)
    edges = [t for t in clk_rises if t >= edge1][:11]
    t0, t1 = edge1 - int(1.5 * period), edges[-1] + int(0.8 * period)

    LABEL_W, ROW_H, H, X_PER_PS, HEAD = 120, 19, 14, 0.0062, 42
    width = LABEL_W + (t1 - t0) * X_PER_PS + 8
    height = HEAD + ROW_H * len(SIGNALS) + 6
    x = lambda t: LABEL_W + (min(max(t, t0), t1) - t0) * X_PER_PS
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
           'font-family="Helvetica, Arial, sans-serif" font-size="11">' % (width, height),
           '<rect width="100%" height="100%" fill="white"/>']

    # controller states: a labelled band on top and a light tint behind every row
    for a, b, name in segments(ch, [TOP + ".u_ctrl.state"], lambda v: STATES.get(v[0], "?"), t0, t1):
        out.append('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="%s" opacity="0.45"/>'
                   % (x(a), HEAD, x(b) - x(a), height - HEAD - 4, BAND[name]))
        out.append('<rect x="%.1f" y="20" width="%.1f" height="18" fill="%s"/>' % (x(a), x(b) - x(a), BAND[name]))
        out.append('<text x="%.1f" y="33" text-anchor="middle" font-weight="bold" font-size="10" fill="%s">%s</text>'
                   % ((x(a) + x(b)) / 2, BAND_TEXT[name], name))
    # numbered rising edges, edge 1 samples start
    out.append('<text x="%d" y="13" text-anchor="end" font-style="italic" fill="#5c6370">edge</text>' % (LABEL_W - 6))
    for k, t in enumerate(edges):
        out.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#adb5bd" stroke-dasharray="2,2"/>'
                   % (x(t), HEAD, x(t), height - 4))
        out.append('<text x="%.1f" y="13" text-anchor="middle" fill="#5c6370">%d</text>' % (x(t), k + 1))

    for row, (label, kind, names, fmt) in enumerate(SIGNALS):
        top = HEAD + 4 + row * ROW_H
        lo, hi, mid = top + H, top, top + H / 2
        out.append('<text x="4" y="%d">%s</text>' % (top + 11, label))
        if kind == "bit":
            segs = segments(ch, names, lambda v: v[0], t0, t1)
            for a, b, v in segs:
                y = hi if v == 1 else lo
                out.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="%s" stroke-width="1.5"/>' % (x(a), y, x(b), y, LINE))
                out.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="%s" stroke-width="1.5"/>' % (x(a), hi, x(a), lo, LINE))
            continue
        for a, b, text in segments(ch, names, fmt, t0, t1):
            xa, xb = x(a), x(b)
            if kind in ("stair", "busy") and text in ("", "0"):
                out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#ced4da"/>' % (xa, mid, xb, mid))
                continue
            d = min(3, (xb - xa) / 2)
            out.append('<polygon points="%.1f,%.1f %.1f,%d %.1f,%d %.1f,%.1f %.1f,%d %.1f,%d" fill="%s" stroke="%s"/>'
                       % (xa, mid, xa + d, hi, xb - d, hi, xb, mid, xb - d, lo, xa + d, lo,
                          "#ebfbee" if kind == "busy" else FILL, LINE))
            if (xb - xa) > 6 * len(text):
                out.append('<text x="%.1f" y="%d" text-anchor="middle"%s>%s</text>'
                           % ((xa + xb) / 2, top + 12, ' font-weight="bold"' if kind == "busy" else "", text))
    out.append("</svg>")
    with open(OUT, "w") as f:
        f.write("\n".join(out) + "\n")
    print("wrote " + OUT)


if __name__ == "__main__":
    main()
