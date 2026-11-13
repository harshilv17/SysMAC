# Port Spec (frozen interface)

All modules: Verilog-2001, one clock `clk`, posedge, synchronous active-high `reset`.
Signed data uses `signed` declarations. Flat buses so no SystemVerilog arrays.

## Packing (row-major)
- A[i][k] = `a_flat[(i*3+k)*8 +: 8]`
- B[k][j] = `b_flat[(k*3+j)*8 +: 8]`
- C[i][j] = `c_flat[(i*3+j)*32 +: 32]`

## Owners
| Module | Owner |
|---|---|
| `processing_element`, `mac_unit` | Abhishek |
| `systolic_array_3x3` | Sushant |
| `input_buffer`, `input_scheduler`, `output_registers` | Piyush |
| `systolic_controller`, `systolic_accelerator_top` | Harshil |

## processing_element (Abhishek)
Code in `project.md` section 9.2. Params `DATA_WIDTH=8`, `ACC_WIDTH=32`.
```
in  clk, reset, clear
in  signed [7:0] a_in, b_in
in  valid_a_in, valid_b_in
out signed [7:0] a_out, b_out      // registered
out valid_a_out, valid_b_out       // registered
out signed [31:0] acc
```

## mac_unit (Abhishek)
```
in  clk, reset
in  signed [7:0] a, b
out signed [31:0] acc
```

## systolic_array_3x3 (Sushant)
A flows right, B flows down. Row i edge input = `a_in_flat[i*8 +: 8]`, col j edge input = `b_in_flat[j*8 +: 8]`.
```
in  clk, reset, clear
in  [23:0] a_in_flat               // 3 x 8, index = row
in  [23:0] b_in_flat               // 3 x 8, index = col
in  [2:0]  valid_a_in              // bit = row
in  [2:0]  valid_b_in              // bit = col
out [287:0] c_flat                 // 9 x 32, PE(i,j) acc, C packing above
```

## input_buffer (Piyush)
Latches both matrices when `load=1`. Outputs held until next load.
```
in  clk, reset, load
in  [71:0] a_flat, b_flat
out [71:0] a_mat, b_mat
```

## input_scheduler (Piyush)
Purely combinational. `t` = zero-based compute cycle 0..6. Zero data and valid=0 when `run=0` or out of range.
- Row i: `k = t-i`, valid if `run && 0<=k<=2`, data `A[i][k]`.
- Col j: `k = t-j`, valid if `run && 0<=k<=2`, data `B[k][j]`.
```
in  run
in  [2:0] t
in  [71:0] a_mat, b_mat
out [23:0] a_in_flat, b_in_flat
out [2:0]  valid_a_in, valid_b_in
```
Check: t=0 -> row0=1, col0=9 (demo matrices). t=2 -> rows 3,5,7, cols 3,5,7.

## output_registers (Piyush)
```
in  clk, reset, capture
in  [287:0] c_in
out [287:0] c_flat
```
`c_flat <= c_in` when `capture=1`. Holds otherwise.

## systolic_controller (Harshil)
FSM: IDLE -> LOAD -> COMPUTE -> CAPTURE -> DONE -> IDLE.
CAPTURE added: last MAC lands on the edge ending COMPUTE t=6, so acc is readable one cycle later.
```
in  clk, reset, start
out load, clear, run, capture, done
out [2:0] t
```
- IDLE: all low. `start` -> LOAD.
- LOAD (1 cycle): `load=1`, `clear=1`.
- COMPUTE (7 cycles): `run=1`, `t` = 0..6.
- CAPTURE (1 cycle): `capture=1`.
- DONE (1 cycle): `done=1`, then IDLE.

## systolic_accelerator_top (Harshil)
`a_flat`/`b_flat` must be stable while `start` is sampled and through the LOAD cycle.
```
in  clk, reset, start
in  [71:0] a_flat, b_flat
out done
out [287:0] c_flat                 // valid while done=1
```
Wiring: controller -> buffer(load) -> scheduler(run,t) -> array(clear) -> output_registers(capture).

## Measured cycles (expected)
Compute window 7. Start sampled -> done: LOAD 1 + COMPUTE 7 + CAPTURE 1 = 9 edges, done visible in cycle 10. Testbench must measure the real value.
