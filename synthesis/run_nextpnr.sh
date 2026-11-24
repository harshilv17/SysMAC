#!/usr/bin/env bash
# Place and route on a Lattice iCE40 HX8K with open-source tools, for a
# maximum clock frequency that does not need Vivado.
#
#   synthesis/run_nextpnr.sh               # needs yosys and nextpnr-ice40; about a minute
#
# For the systolic top and the baseline:
#   resources  Yosys synth_ice40 on the bare design (LUT4, flip-flops, carry cells)
#   Fmax       nextpnr-ice40, HX8K CT256, 50 MHz clock constraint, placement
#              seeds 1-5; the median is reported because Fmax depends on the seed
# and writes synthesis/nextpnr/summary.txt (committed) and full logs (not committed).
#
# The design has 436 I/O bits, more than any iCE40 package has pins, and
# nextpnr has no out-of-context mode, so for place and route it is wrapped in
# synthesis/fmax_harness.v: inputs fill from a shift register, outputs shift
# out, and every port of the design is registered.
#
# The iCE40 has no multiplier blocks, so every multiplier is built from LUTs.
# Artix-7 counts are in synthesis/yosys/ and synthesis/vivado/.

set -eu
cd "$(dirname "$0")/.."
for tool in yosys nextpnr-ice40; do
    command -v "$tool" >/dev/null || { echo "missing tool: $tool"; exit 2; }
done

OUT=synthesis/nextpnr
mkdir -p "$OUT"
FREQ=50
SEEDS="1 2 3 4 5"
CYCLES_systolic_accelerator_top=10   # start to done, measured by tb_matmul_vectors.v
CYCLES_seq_matmul=29

# count <log> <regex>: cells whose type matches, in the log's last stat block
count() { awk -v re="^($2)\$" '/Printing statistics/ { n = 0 } $2 ~ re { n += $1 } END { print n + 0 }' "$1"; }

rows=""
for top in systolic_accelerator_top seq_matmul; do
    yosys -q -l "$OUT/${top}_synth.log" -p "read_verilog rtl/*.v; synth_ice40 -top $top; stat" >/dev/null
    yosys -q -p "read_verilog -DCORE=$top rtl/*.v synthesis/fmax_harness.v; synth_ice40 -top fmax_harness -json $OUT/$top.json"
    mhz=""
    for seed in $SEEDS; do
        log="$OUT/${top}_pnr_seed$seed.log"
        nextpnr-ice40 --hx8k --package ct256 --json "$OUT/$top.json" --pcf-allow-unconstrained \
            --freq $FREQ --seed "$seed" --timing-allow-fail >"$log" 2>&1
        mhz="$mhz $(grep "Max frequency for clock" "$log" | tail -1 | grep -oE '[0-9.]+ MHz' | head -1 | cut -d' ' -f1)"
    done
    rm -f "$OUT/$top.json"
    sorted=$(echo $mhz | tr ' ' '\n' | sort -n)
    med=$(echo "$sorted" | sed -n 3p)
    eval cycles=\$CYCLES_$top
    stat="$OUT/${top}_synth.log"
    lut=$(count "$stat" SB_LUT4)
    rows="$rows$(printf "%-26s %6s %5s %6s %8s %13s %7s %7.1f %10.0f" "$top" "$lut" \
        "$(count "$stat" 'SB_DFF[A-Z]*')" "$(count "$stat" SB_CARRY)" "$med" \
        "$(echo "$sorted" | head -1)-$(echo "$sorted" | tail -1)" "$cycles" \
        "$(echo "$cycles * 1000 / $med" | bc -l)" "$(echo "$lut * $cycles / $med" | bc -l)")
"
done

{
    echo "Yosys $(yosys -V | awk '{print $2}') synth_ice40 + nextpnr-ice40, iCE40 HX8K CT256, ${FREQ} MHz constraint"
    echo "Fmax: median (and range) over placement seeds$(echo " $SEEDS" | tr ' ' ',' | sed 's/^,/ /'). Area x time in LUT4 x us."
    echo
    printf "%-26s %6s %5s %6s %8s %13s %7s %7s %10s\n" design LUT4 FF carry Fmax_MHz range_MHz cycles ns area_x_t
    printf "%s" "$rows"
} | tee "$OUT/summary.txt"
