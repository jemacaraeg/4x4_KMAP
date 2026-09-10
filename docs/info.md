<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The project implements a 4×4 Karnaugh Map (K-map) in Verilog, mapped to a VGA display.

Input variables are fed into the logic system, and the corresponding cells in the K-map are highlighted on screen.

The VGA controller generates pixel coordinates and sync signals, while the K-map module determines which cells to light up.

Simplified Boolean expressions can be visualized by grouping adjacent cells, making minimization more intuitive.

## How to test

1. Simulation

-Run the Verilog modules in a simulator (e.g., ModelSim, Icarus Verilog, or Vivado) to verify logic correctness.
-Check that input combinations map correctly to the expected K-map cells.

2. VGA Playground Deployment

-Upload the design files to the VGA Playground platform.
-Use the provided switches/buttons in the playground to toggle input variables.
-Observe the VGA output: cells should update dynamically based on inputs.

3. Validation

-Compare the displayed K-map with manual truth table/K-map derivations.
-Confirm that grouping and minimization match expected Boolean simplifications.

## External hardware

VGA monitor & FPGA board
