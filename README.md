# Asylum Utils Generators

A collection of useful generators and tools for the Asylum project. This repository provides tools for embedded firmware compilation and hardware register generation, enabling seamless integration between software and hardware components.

## Table of Contents

- [Introduction](#introduction)
- [Tools](#tools)
- [Generators](#generators)
- [HDL Modules](#hdl-modules)
- [Register Map](#register-map)
- [Component Verification](#component-verification)

---

## Introduction

The Asylum Utils Generators project is a comprehensive toolkit designed to streamline the development of embedded systems. It provides two main generators:

1. **PBCC Generator**: Automates the compilation of C code and assembler files for the Xilinx PicoBlaze-3 soft-core processor, generating ROM content in multiple formats.

2. **Regtool Generator**: Generates hardware configuration and status registers (CSR) from HJSON specifications, producing RTL modules, header files, and documentation.

This project integrates mature tools like SDCC (Small Device C Compiler) and custom utilities to provide a complete build flow from high-level specifications to synthesizable RTL.

---

## Tools

### SDCC (Small Device C Compiler)

A complete C compiler toolchain targeting the Xilinx PicoBlaze architecture.

- **Version**: 3.1.0
- **Purpose**: Compiles C code into optimized assembly for PicoBlaze microcontrollers
- **Reference**: [SDCC Official Project](https://sdcc.sourceforge.net/)
- **Original Integration**: [PBCC Portage](https://www.fit.vutbr.cz/~meduna/work/doku.php?id=projects:vlam:pbcc:pbcc)

### PicoASM

An assembler for the Xilinx PicoBlaze-3 soft-core processor with extensive output format support.

- **Purpose**: Assembles KCPSM3 and PBlaze-IDE compatible assembly files
- **Outputs**: VHDL, Verilog, and other formats
- **Reference**: [PicoASM Original Project](https://marksix.home.xs4all.nl/picoasm.html)

### RegTool

Register generation and documentation tool for hardware/software interfaces.

- **Purpose**: Creates register definitions from HJSON specifications
- **Outputs**: VHDL/Verilog modules, C header files, documentation
- **Foundation**: Based on concepts from [OpenTitan's RegGen](https://opentitan.org/book/util/reggen/index.html)

---

## Generators

### PBCC Generator

**Command**: `generators/pbcc/pbcc.py`

Invokes SDCC and PicoASM to compile C files and generate ROM content for PicoBlaze processors.

**Parameters**:

| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `file` | Yes | string | Source file path (C or assembly) |
| `type` | Yes | enum | File type: `c`, `kcpsm3`, or `pblazeide` |
| `entity` | No | string | Entity name (default: `OpenBlaze8_ROM`) |
| `model` | No | enum | ROM model: `generic` or `xilinx` (default: `generic`) |
| `cflags` | No | string | C compilation flags |
| `logical_name` | No | string | VHDL logical name (default: `work`) |

### RegTool Generator

**Command**: `generators/regtool/regtool.py`

Generates CSR (Configuration and Status Registers) modules, C header files, and markdown documentation from HJSON register specifications.

**Parameters**:

| Parameter | Required | Type | Description |
|-----------|----------|------|-------------|
| `file` | Yes | string | HJSON register specification file |
| `name` | Yes | string | Name prefix for generated components |
| `interface` | No | enum | Register interface: `reg` or `pbi` |
| `range` | No | string | Register address range selector |

---

## HDL Modules

The RegTool generator produces four core VHDL modules in `tools/regtool/hdl/`:

### 1. csr_reg - Configuration and Status Register

**File**: `tools/regtool/hdl/csr_reg.vhd`

Standard register module with dual-side (software/hardware) read/write access control.

**Generics**:

| Generic | Type | Description |
|---------|------|-------------|
| `WIDTH` | positive | Register width in bits (default: 1) |
| `INIT` | std_logic_vector | Reset value |
| `MODEL` | string | Register type: `ro`, `rw`, `rw1c`, `rw0c`, `rw1s`, `rw0s` |

**Input Ports**:

| Port | Width | Description |
|------|-------|-------------|
| `clk_i` | 1 | System clock |
| `arst_b_i` | 1 | Asynchronous reset (active low) |
| `sw_wd_i` | WIDTH | Software side write data |
| `sw_we_i` | 1 | Software side write enable |
| `sw_re_i` | 1 | Software side read enable |
| `hw_wd_i` | WIDTH | Hardware side write data |
| `hw_we_i` | 1 | Hardware side write enable |

**Output Ports**:

| Port | Width | Description |
|------|-------|-------------|
| `sw_rd_o` | WIDTH | Software side read data |
| `sw_rbusy_o` | 1 | Software side read busy |
| `sw_wbusy_o` | 1 | Software side write busy |
| `hw_rd_o` | WIDTH | Hardware side read data |
| `hw_sw_re_o` | 1 | Hardware detected software read |
| `hw_sw_we_o` | 1 | Hardware detected software write |

**Operation**:

The `csr_reg` module implements a dual-sided register supporting various access models:

- **ro** (Read-Only): Only hardware can write, software reads register value
- **rw** (Read-Write): Both sides can read/write, with software write taking priority
- **rw1c** (Read-Write-1-to-Clear): Writing '1' to software clears corresponding bits
- **rw0c** (Read-Write-0-to-Clear): Writing '0' to software clears corresponding bits
- **rw1s** (Read-Write-1-to-Set): Writing '1' to software sets corresponding bits
- **rw0s** (Read-Write-0-to-Set): Writing '0' to software sets corresponding bits

### 2. csr_ext - External Interface Register

**File**: `tools/regtool/hdl/csr_ext.vhd`

External interface register providing pass-through connectivity for hardware-controlled registers without memory elements.

**Generics**:

| Generic | Type | Description |
|---------|------|-------------|
| `WIDTH` | positive | Register width in bits (default: 1) |

**Input Ports**:

| Port | Width | Description |
|------|-------|-------------|
| `clk_i` | 1 | System clock |
| `arst_b_i` | 1 | Asynchronous reset (active low) |
| `sw_wd_i` | WIDTH | Software side write data |
| `sw_we_i` | 1 | Software side write enable |
| `sw_re_i` | 1 | Software side read enable |
| `hw_wd_i` | WIDTH | Hardware side write data |
| `hw_we_i` | 1 | Hardware side write enable |

**Output Ports**:

| Port | Width | Description |
|------|-------|-------------|
| `sw_rd_o` | WIDTH | Software side read data |
| `sw_rbusy_o` | 1 | Software side read busy |
| `sw_wbusy_o` | 1 | Software side write busy |
| `hw_rd_o` | WIDTH | Hardware side read data |
| `hw_sw_re_o` | 1 | Hardware detected software read |
| `hw_sw_we_o` | 1 | Hardware detected software write |

**Operation**:

The `csr_ext` module provides direct pass-through connectivity without memory:

- Software writes on `sw_wd_i` are routed to hardware side as `hw_rd_o`
- Hardware writes on `hw_wd_i` are routed to software side as `sw_rd_o`
- Read/write strobes are cross-connected for event detection

### 3. csr_fifo - FIFO Interface for CSR

**File**: `tools/regtool/hdl/csr_fifo.vhd`

FIFO interface module enabling buffered communication between software and hardware through CSR registers.

**Generics**:

| Generic | Type | Default | Description |
|---------|------|---------|-------------|
| `WIDTH` | positive | 1 | Data width in bits |
| `BLOCKING_READ` | boolean | false | Block software reads when empty |
| `BLOCKING_WRITE` | boolean | true | Block software writes when full |
| `DEPTH_SW2HW` | natural | 0 | SW→HW FIFO depth (0=bypass) |
| `DEPTH_HW2SW` | natural | 0 | HW→SW FIFO depth (0=bypass) |

**Input Ports**:

| Port | Width | Description |
|------|-------|-------------|
| `clk_i` | 1 | System clock |
| `arst_b_i` | 1 | Asynchronous reset (active low) |
| `sw_wd_i` | WIDTH | Software write data (SW→HW path) |
| `sw_we_i` | 1 | Software write enable |
| `sw_re_i` | 1 | Software read enable |
| `hw_tx_valid_i` | 1 | Hardware TX valid (HW→SW path) |
| `hw_tx_data_i` | WIDTH | Hardware TX data |
| `hw_rx_ready_i` | 1 | Hardware RX ready |

**Output Ports**:

| Port | Width | Description |
|------|-------|-------------|
| `sw_rd_o` | WIDTH | Software read data (HW→SW path) |
| `sw_rbusy_o` | 1 | Software read busy |
| `sw_wbusy_o` | 1 | Software write busy |
| `hw_tx_ready_o` | 1 | Hardware TX ready |
| `hw_tx_empty_o` | 1 | Hardware TX empty flag |
| `hw_tx_full_o` | 1 | Hardware TX full flag |
| `hw_rx_valid_o` | 1 | Hardware RX valid (SW→HW path) |
| `hw_rx_data_o` | WIDTH | Hardware RX data |
| `hw_rx_empty_o` | 1 | Hardware RX empty flag |
| `hw_rx_full_o` | 1 | Hardware RX full flag |

**Operation**:

The `csr_fifo` module provides two independent FIFO paths:

1. **Software to Hardware Path** (SW→HW):
   - Optionally buffered with `DEPTH_SW2HW` FIFO
   - Software writes data via CSR interface
   - Hardware receives via handshake signals (`hw_rx_valid_o`, `hw_rx_ready_i`)

2. **Hardware to Software Path** (HW→SW):
   - Optionally buffered with `DEPTH_HW2SW` FIFO
   - Hardware transmits via handshake signals (`hw_tx_valid_i`, `hw_tx_ready_o`)
   - Software reads data via CSR interface

When depth is 0, FIFO acts as a direct bypass with handshake control.

### 4. csr_pkg - Package Definition

**File**: `tools/regtool/hdl/csr_pkg.vhd`

VHDL package containing component declarations for all CSR modules, enabling their instantiation in register maps.

---

## Register Map

The RegTool generator creates register maps from HJSON specifications. These specifications define:

- **Registers**: Named registers at specific addresses with read/write access policies
- **Bit Fields**: Individual bit ranges within registers with specific access models
- **Parameters**: Configuration options that affect RTL generation

### Example Register Specification

**File**: `tools/regtool/examples/example1.hjson`

```hjson
{
    name   : "example1",
    desc   : "The example 1",
    width  : 32,
    
    registers : [
        {
            name      : "reg1",
            address   : "x0",
            desc      : "Register 1",
            hwaccess  : "rw",
            swaccess  : "rw1c",
            fields: [
                {
                    name  : "field1",
                    bits  : "0",
                    init  : "d0",
                    desc  : "Field 1"
                },
                {
                    name  : "field2",
                    bits  : "2",
                    init  : "b00",
                    desc  : "Field 2"
                }
            ]
        }
    ]
}
```

### Register Access Models

| Model | SW Access | HW Access | Behavior |
|-------|-----------|-----------|----------|
| `rw` | Read-Write | Read-Write | Both sides can read/write |
| `ro` | Read-Only | Read-Write | Software reads hardware values |
| `wo` | Write-Only | Read-Only | Software writes, hardware reads |
| `rw1c` | Read-Write | Read-Only | Write 1 to software clears bits |
| `rw0c` | Read-Write | Read-Only | Write 0 to software clears bits |
| `rw1s` | Read-Write | Read-Only | Write 1 to software sets bits |
| `rw0s` | Read-Write | Read-Only | Write 0 to software sets bits |

### Register FIFO Type

FIFO registers support efficient buffered communication:

```hjson
{
    name      : "fifo_sw2hw",
    address   : "x10",
    desc      : "Write FIFO (Software to Hardware)",
    hwaccess  : "wo",
    swaccess  : "ro",
    hwtype    : "fifo",
    fields: [...]
}
```

FIFO type registers automatically use the `csr_fifo` module with configurable depths.

### Generated Register Documentation

The generator produces markdown documentation with register details:

**Example Output**: [`tools/regtool/examples/example1_csr.md`](tools/regtool/examples/example1_csr.md)

This file contains:
- Register address mapping table
- Per-register documentation
- Bit field descriptions and access policies
- Enumeration values (when defined)
