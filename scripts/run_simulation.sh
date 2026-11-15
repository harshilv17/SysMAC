#!/usr/bin/env bash
# Run every testbench in tb/ and print one line per result.
#
#   scripts/run_simulation.sh            regenerate vectors, run everything
#   scripts/run_simulation.sh top        only testbenches whose name contains "top"
#   scripts/run_simulation.sh --waves    also keep the VCD waveform files
#   scripts/run_simulation.sh --list     show the testbenches it would run
#
# Each testbench is compiled with every file in rtl/. A testbench that needs
# a module from docs/port_spec.md that is not written yet is reported as
# WAITING, not as a failure. A missing module that is NOT in the spec is
# reported as FAIL, because it is almost certainly a typo in an instance.
#
# Extra runs, beyond the files in tb/:
#   tb_matmul_vectors_seq             the vector test on seq_matmul
#   tb_matmul_vectors_systolic_top    the same vectors on systolic_accelerator_top
#
# A testbench PASSES only if: vvp exits normally within TIMEOUT seconds
# (default 120), the log contains the word "pass" in any case, and the log
# contains no whole word fail / failed / fatal / error (in any case).
# Exit code: 0 if nothing failed, 1 if something failed, 2 for a bad setup.
#
# Needs python3 (or python), iverilog, vvp.
# Windows: run from Git Bash with the OSS CAD Suite on PATH.

set -u
cd "$(dirname "$0")/.."

TIMEOUT=${TIMEOUT:-120}

# Build products and logs stay out of git: sim/build ignores itself.
BUILD=sim/build
LOGS=$BUILD/logs
mkdir -p "$LOGS"
printf '*\n' > "$BUILD/.gitignore"

# Modules named in docs/port_spec.md, plus the baseline.
SPEC_MODULES=" processing_element mac_unit systolic_array_3x3 input_buffer input_scheduler
               output_registers systolic_controller systolic_accelerator_top seq_matmul "

FILTER=""
WAVES=0
LIST=0
for arg in "$@"; do
    case "$arg" in
        --waves) WAVES=1 ;;
        --list)  LIST=1 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        -*) echo "unknown option: $arg"; exit 2 ;;
        *) FILTER=$arg ;;
    esac
done

# On Windows "python3" is often a store stub that does nothing, so test it.
PY=""
for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import sys; sys.exit(sys.version_info < (3, 6))" 2>/dev/null; then
        PY=$cand; break
    fi
done
[ -n "$PY" ] || { echo "missing tool: python 3"; exit 2; }
for tool in iverilog vvp; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool"; exit 2; }
done

RTL=$(ls rtl/*.v 2>/dev/null)
PASSED=0; FAILED=0; WAITING=0; RAN=0

# run <label> <tb file> [iverilog flags...]
run() {
    local label=$1 tb=$2; shift 2
    local top exe log plus="" status
    top=$(basename "$tb" .v)
    exe="$BUILD/$label.vvp"
    log="$LOGS/$label.log"
    RAN=$((RAN + 1))
    if [ $LIST -eq 1 ]; then echo "  $label  ($tb $*)"; return; fi

    # shellcheck disable=SC2086
    if ! iverilog -g2005 -Wall -Wno-timescale -Wno-implicit-dimensions "$@" -s "$top" \
            -o "$exe" $RTL "$tb" >"$log" 2>&1; then
        local missing m unknown=""
        missing=$(grep -o "Unknown module type: [A-Za-z0-9_]*" "$log" | sort -u \
                  | sed 's/Unknown module type: //' | tr '\n' ' ')
        for m in $missing; do
            case "$SPEC_MODULES" in *" $m "*) ;; *) unknown="$unknown $m" ;; esac
        done
        if [ -n "$missing" ] && [ -z "$unknown" ]; then
            printf "  %-8s %-34s needs: %s\n" WAITING "$label" "$missing"
            WAITING=$((WAITING + 1))
        elif [ -n "$unknown" ]; then
            printf "  %-8s %-34s unknown module:%s (not in port_spec.md, typo?)\n" FAIL "$label" "$unknown"
            FAILED=$((FAILED + 1))
        else
            printf "  %-8s %-34s compile error, see %s\n" FAIL "$label" "$log"
            grep -m 3 -i "error" "$log" | sed 's/^/           /'
            FAILED=$((FAILED + 1))
        fi
        return
    fi

    [ $WAVES -eq 1 ] && plus="+vcd=sim/$label.vcd"
    # Run with a watchdog: a testbench that never calls $finish is killed.
    vvp -n "$exe" $plus >>"$log" 2>&1 &
    local pid=$! waited=0
    status=""
    while kill -0 "$pid" 2>/dev/null; do
        if [ $waited -ge $((TIMEOUT * 10)) ]; then
            kill "$pid" 2>/dev/null
            echo "TIMEOUT after ${TIMEOUT}s" >>"$log"
            wait "$pid" 2>/dev/null
            status=timeout
            break
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    if [ -z "$status" ]; then
        wait "$pid" 2>/dev/null
        status=$?
    fi

    if [ $status -eq 0 ] && grep -qi "pass" "$log" \
            && ! grep -Eqiw "fail|failed|fatal|error|timeout" "$log"; then
        printf "  %-8s %-34s %s\n" PASS "$label" \
            "$(grep -Eo "(jobs|latency|errors)=[0-9]+( cycles)?" "$log" | tr '\n' ' ')"
        PASSED=$((PASSED + 1))
    else
        printf "  %-8s %-34s exit %s, see %s\n" FAIL "$label" "$status" "$log"
        grep -m 3 -Eiw "fail|failed|fatal|error|timeout" "$log" | sed 's/^/           /'
        FAILED=$((FAILED + 1))
    fi
}

if [ $LIST -eq 0 ]; then
    "$PY" scripts/reference_model.py selfcheck || exit 1
    echo "vectors: $("$PY" scripts/reference_model.py vectors) jobs in sim/vectors"
fi
echo "testbenches (rtl: $(echo $RTL | wc -w | tr -d ' ') files)"

for tb in tb/tb_*.v; do
    name=$(basename "$tb" .v)
    [ "$name" = tb_matmul_vectors ] && continue
    case "$name" in *"$FILTER"*) run "$name" "$tb" ;; esac
done
if [ -f tb/tb_matmul_vectors.v ]; then
    case "tb_matmul_vectors_seq" in *"$FILTER"*)
        run tb_matmul_vectors_seq tb/tb_matmul_vectors.v ;; esac
    case "tb_matmul_vectors_systolic_top" in *"$FILTER"*)
        run tb_matmul_vectors_systolic_top tb/tb_matmul_vectors.v -DSYSTOLIC ;; esac
fi

if [ $RAN -eq 0 ]; then
    echo "no testbench matches \"$FILTER\""
    exit 2
fi
[ $LIST -eq 1 ] && exit 0
[ $WAVES -eq 0 ] && rm -f sim/*.vcd
echo "summary: $PASSED passed, $FAILED failed, $WAITING waiting for modules"
[ $FAILED -eq 0 ]
