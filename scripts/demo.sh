#!/usr/bin/env bash
# Live demo in one command: run every testbench, print the demo result matrix,
# then the systolic vs sequential comparison from the last place and route.
#
#   scripts/demo.sh
#
# Waveform: open sim/waveforms/demo.vcd in GTKWave or Surfer, or show
# docs/figures/waveform.png. Place and route is not rerun (about a minute):
# synthesis/run_nextpnr.sh does that.

set -u
cd "$(dirname "$0")/.."

scripts/run_simulation.sh || exit 1

echo
echo "Demo: A = [[1,2,3],[4,5,6],[7,8,9]], B = [[9,8,7],[6,5,4],[3,2,1]]"
grep -E "^C\[|start->done" sim/build/logs/tb_demo.log

echo
cat synthesis/nextpnr/summary.txt
