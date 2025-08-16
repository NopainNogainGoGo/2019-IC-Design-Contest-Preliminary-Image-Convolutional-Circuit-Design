# CONV Module

## 📖 Overview

The **`CONV`** module is a Verilog hardware design that performs **convolution + ReLU + max pooling** operations on grayscale image data.

This module simulates the first two layers of a **Convolutional Neural Network (CNN)**:

1. **Convolution + Bias + ReLU** → writes results into **Layer 0 (SRAM)**
2. **MaxPooling (stride=2)** → writes results into **Layer 1 (SRAM)**

It uses a **finite state machine (FSM)** to control the flow of convolution, ReLU activation, pooling, and memory operations.

---

## ⚙️ Features

* **Convolution with 3×3 Kernel** (with predefined weights `K0_0` to `K0_8`)
* **Bias addition**
* **Zero padding** at image boundaries
* **ReLU activation** (negative values → 0)
* **2×2 MaxPooling (stride=2)**
* **SRAM interface** for storing intermediate results
* **FSM-based control** for modular computation

---

## 🔧 I/O Ports

| Signal     | Dir | Width | Description             |
| ---------- | --- | ----- | ----------------------- |
| `clk`      | in  | 1     | System clock            |
| `reset`    | in  | 1     | Reset signal            |
| `busy`     | out | 1     | Module busy flag        |
| `ready`    | in  | 1     | Start signal            |
| `iaddr`    | out | 12    | Input image address     |
| `idata`    | in  | 20    | Input image data        |
| `cwr`      | out | 1     | Write enable for SRAM   |
| `caddr_wr` | out | 12    | Write address for SRAM  |
| `cdata_wr` | out | 20    | Data to write into SRAM |
| `crd`      | out | 1     | Read enable for SRAM    |
| `caddr_rd` | out | 12    | Read address for SRAM   |
| `cdata_rd` | in  | 20    | Data read from SRAM     |
| `csel`     | out | 3     | SRAM bank select        |

---

## 🏗️ FSM States

| State       | Code | Description                                  |
| ----------- | ---- | -------------------------------------------- |
| `IDLE`      | 000  | Wait for `ready` signal                      |
| `READ_CONV` | 001  | Read pixels & compute convolution            |
| `WRITE_L0`  | 010  | Write convolution + ReLU result into Layer 0 |
| `DELAY1`    | 011  | Transition delay                             |
| `READ_L0`   | 100  | Read data from Layer 0 for pooling           |
| `WRITE_L1`  | 101  | Write pooled results into Layer 1            |
| `DELAY2`    | 110  | Transition delay                             |
| `FINISH`    | 111  | Processing complete                          |

---

## 🧮 Internal Logic

* **Convolution Accumulator (`conv_sum`)**

  * 9 MAC operations for kernel \* pixel values
  * Bias is added on the 10th cycle
  * Final result rounded and passed through **ReLU**

* **Pooling (`current_max`)**

  * Reads 2×2 block from Layer 0
  * Selects maximum value and writes to Layer 1

* **Coordinate counters**

  * `(x, y)` for convolution pixel scanning (64×64 image)
  * `(L1_x, L1_y)` for pooling (stride=2 → 32×32 output)

---

## 📐 Memory Mapping

* **Input image**: 64×64 pixels
* **Layer 0 (Convolution output)**: 64×64 pixels stored in `SRAM[0]`
* **Layer 1 (Pooling output)**: 32×32 pixels stored in `SRAM[1]`

---

## 🚀 Usage

1. Set `reset = 1` → Initialize
2. Set `ready = 1` → Start computation
3. Wait until `busy = 0` → Computation finished
4. Read results from SRAM:

   * **Layer 0** (convolution + ReLU results)
   * **Layer 1** (pooled results)

---

## 🗂️ File Structure

```
.
├── CONV.v        # Verilog module (this file)
├── README.md     # Documentation
└── testbench/    # (Optional) testbenches for simulation
```
