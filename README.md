# Systolic Array Matrix Multiplication Accelerator

3x3 output-stationary systolic array. Signed 8-bit inputs, signed 32-bit accumulators. Verilog.

## Layout
- `rtl/` synthesizable Verilog
- `tb/` testbenches
- `sim/` waveforms and logs
- `scripts/` run and reference scripts
- `synthesis/` FPGA reports
- `docs/` diagrams, `port_spec.md`

## Rules
- Module ports must match `docs/port_spec.md`.
- Commit your own files, small commits.
