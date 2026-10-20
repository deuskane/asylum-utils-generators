<!--
  README GENERATION INSTRUCTIONS (for the next regeneration run)
  ----------------------------------------------------------------
  This README follows the common Asylum IP model. Regenerate it from the
  sources, never from the previous README text alone.

  Sources of truth (in priority order):
    1. hdl/*.vhd            : entities, generics, ports, packages
    2. hdl/csr/*.hjson      : register map (regtool); *_csr.md/.h are generated
    3. <IP>.core            : VLNV (name), filesets, targets, depends, revisions
    4. mk/targets.txt       : target list shown by `make help`; mk/defs.mk
    5. sim/, syn/, esw/, boards/ : testbenches, constraints, software
  Section order (keep it, same headings in every IP):
    CI badge / Title + one-line description + VLNV / Table of Contents /
    Introduction (Key Features) / Block Diagram / Top-Level (Parameters,
    Ports, Instantiation Example) / HDL Modules / Register Map /
    Verification / Synthesis / Design Notes (optional) /
    Directory Structure / Dependencies
  Rules:
    - Language: English. Tables: Parameters = Name|Type|Default|Description,
      Ports = Name|Direction|Type|Description (grouped by interface).
    - Register Map: link to the generated hdl/csr/<X>_csr.md (plus the
      .hjson source and _csr.h header); never copy register tables here.
    - Top-Level = sbi_* wrapper if present, else the entity used by the
      `default` target, else the main entity (libraries: list packages).
    - Write "This IP has no software-visible registers." / "No dedicated
      synthesis target ..." instead of removing a section.
    - Keep still-accurate hand-written content (ISA tables, results,
      images) in "Design Notes"; drop anything not backed by the sources.
    - Block diagram: doc/<NAME>.drawio (NAME = 4th field of the VLNV),
      top entity box with generics on top, inputs left, outputs right,
      bus interfaces as bold arrows, internal blocks colour-coded
      (CSR yellow, FIFO/memory green, core logic blue, external grey).
      Update it whenever ports/generics/sub-blocks change.
    - Do not edit generated files (hdl/csr/*_csr.*) or the CI badge URL.
-->
[![no CI](https://img.shields.io/badge/CI-no%20workflow-lightgrey)](https://github.com/deuskane/asylum-project)

# asylum-utils-generators

**FuseSoC generators of the Asylum project: regtool (CSR banks from hjson), pbcc_gen (PicoBlaze C / assembler to ROM) and rvcc_gen (RISC-V C / assembler to ROM), with their tools and the CSR HDL building blocks.**

VLNV: `asylum:utils:generators:2.7.1`

## Table of Contents

1. [Introduction](#introduction)
2. [Block Diagram](#block-diagram)
3. [Top-Level](#top-level)
4. [HDL Modules](#hdl-modules)
5. [Register Map](#register-map)
6. [Verification](#verification)
7. [Synthesis](#synthesis)
8. [Design Notes](#design-notes)
9. [Directory Structure](#directory-structure)
10. [Dependencies](#dependencies)

## Introduction

This repository provides the code generators used by the other Asylum cores through the FuseSoC `generate:` mechanism. It declares three generators in [generators.core](generators.core):

- **`regtool`**: reads a register description (`hdl/csr/<X>.hjson`) and produces a VHDL CSR bank (`<X>_registers`), its package, a C header and a Markdown documentation. Used by every IP with registers (`gen_csr` in their core).
- **`pbcc_gen`**: compiles a C file with the PicoBlaze port of SDCC (pbcc) or takes a KCPSM3 / PBlazeIDE assembler file, assembles it with picoasm and produces a ROM entity plus its component package (OpenBlaze8 / PicoBlaze-3 processors).
- **`rvcc_gen`**: compiles C / assembler with a RISC-V GCC toolchain (`rv32i`) and produces a ROM entity plus its component package (WardRV processor).

Every generator renders a `Makefile` from a Jinja2 template, runs `make` in the FuseSoC generator work directory under an exclusive file lock, and registers the produced files in the calling core. The core itself has no HDL fileset in its `default` target (the `regtool_hdl` fileset is only used by the lint targets): `default` only pulls `asylum:component:fifo`, required by the `csr_fifo` building block that regtool adds to the calling core.

### Key Features

- regtool: hjson schema validation, `reg` / `pbi` / `sbi` bus interface, 10 software access models, `reg` / `ext` / `fifo` hardware types, hjson parameters mapped to VHDL generics, conditional registers (`enable`), write aliases, enumerated field values
- regtool outputs: `<X>_csr.vhd`, `<X>_csr_pkg.vhd`, `<X>_csr.h`, `<X>_csr.md`, optionally copied back into the source tree (`copy`)
- CSR building blocks in VHDL: `csr_reg`, `csr_ext`, `csr_fifo` (with optional `fifo_sync` FIFOs and blocking access), `csr_pkg`
- pbcc_gen: C (`c`) or assembler (`kcpsm3`, `pblazeide`) input, `generic` or `xilinx` ROM model, user `cflags` (relative `-I` paths resolved from the calling core)
- rvcc_gen: C / assembler input, `start.S` and `link.ld` templates, stack size check, listing / map / size reports, `rv32i_zicsr` used when the compiler supports it
- Generated `*-gen_csr_*` directories automatically added to the include path of pbcc / rvcc (C code can include `<X>_csr.h`)
- Bundled tool sources: picoasm, PicoBlaze SDCC ports and SDCC 3.1.0, plus [doc/pbccv2_user_manual.pdf](doc/pbccv2_user_manual.pdf)
- Helper scripts: toolchain build, component package generation, pbcc target generation

## Block Diagram

- `regtool` (FuseSoC wrapper, [generators/regtool/regtool.py](generators/regtool/regtool.py)) calls the standalone tool [tools/regtool/regtool.py](tools/regtool/regtool.py) once per output file, then adds `csr_pkg` / `csr_reg` / `csr_ext` / `csr_fifo` and the generated VHDL to the calling core.
- `csr_fifo` instantiates `fifo_sync` from `asylum:component:fifo` (grey, external core).
- `pbcc_gen`: `.c` -> sdcc (`$PBCC_HOME/bin/sdcc`) -> `.psm` -> picoasm (`$PICOASM_HOME/bin/picoasm`) -> ROM `.vhd`; `gen_rom.py` writes the `_pkg.vhd`.
- `rvcc_gen`: source -> RISC-V GCC (`$RISCV_PREFIX`) -> `.elf` -> `.bin` -> `.hex` -> `gen_rom.py` -> ROM `.vhd` and `_pkg.vhd`.
- The scripts of `scripts/` are run by hand (not by FuseSoC).

## Top-Level

Library IP: there is no HDL top-level. Content of the repository:

| Unit | Kind | File | Description |
|------|------|------|-------------|
| `regtool` | FuseSoC generator | [generators/regtool/regtool.py](generators/regtool/regtool.py) + [templates/Makefile.j2](generators/regtool/templates/Makefile.j2) | CSR generator wrapper |
| `pbcc_gen` | FuseSoC generator | [generators/pbcc/pbcc.py](generators/pbcc/pbcc.py) + [templates/Makefile.j2](generators/pbcc/templates/Makefile.j2) | PicoBlaze ROM generator |
| `rvcc_gen` | FuseSoC generator | [generators/rvcc/rvcc.py](generators/rvcc/rvcc.py) + [templates/](generators/rvcc/templates/) | RISC-V ROM generator (`Makefile.j2`, `start.S`, `link.ld`) |
| regtool | Python tool | [tools/regtool/regtool.py](tools/regtool/regtool.py), [addrmap.py](tools/regtool/addrmap.py), [regtool_schema.hjson](tools/regtool/regtool_schema.hjson) | hjson parser / checker and VHDL, C, Markdown writers |
| `csr_pkg`, `csr_reg`, `csr_ext`, `csr_fifo` | VHDL | [tools/regtool/hdl/](tools/regtool/hdl/) | CSR building blocks instantiated by generated banks |
| gen_rom | Python tool | [generators/gen_rom/gen_rom.py](generators/gen_rom/gen_rom.py) + [ROM/](generators/gen_rom/ROM/) | Fills ROM / ROM package templates from a hex file |
| picoasm | C++ tool | [tools/picoasm/](tools/picoasm/) | PicoBlaze assembler with ROM templates |
| sdcc | C tool sources | `tools/pbccv2-src-20110901/`, `tools/pbccv2-src-20111024/`, `tools/sdcc-3.1.0/` | SDCC trees for the PicoBlaze C compiler |
| `component.py` | script | [scripts/component.py](scripts/component.py) | Builds / updates component packages |
| `build_toolchain.sh` | script | [scripts/build_toolchain.sh](scripts/build_toolchain.sh) | Builds and installs sdcc and picoasm |
| `gen_target.sh` | script | [scripts/gen_target.sh](scripts/gen_target.sh) | Generates pbcc_gen `generate:` / target entries and a Makefile for a set of sources |

### Parameters

Generator parameters (`parameters:` of a `generate:` entry in the calling core).

#### regtool

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `file` | string | *(mandatory)* | hjson description, relative to the calling core |
| `name` | string | *(mandatory)* | Prefix of the output files (`<name>_csr.vhd`, ...) |
| `copy` | string | *(none)* | Directory of the calling core where the 4 outputs are copied (must exist), e.g. `hdl/csr` |
| `logical_name` | string | `work` | VHDL library of the generated and building-block files |

#### pbcc_gen

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `file` | string | *(mandatory)* | Source file |
| `type` | string | *(mandatory)* | `c`, `kcpsm3` or `pblazeide` |
| `entity` | string | `OpenBlaze8_ROM` | ROM entity name |
| `model` | string | `generic` | ROM template: `generic` or `xilinx` |
| `cflags` | string | `""` | Extra sdcc options; relative `-I` paths are prefixed with the calling core root |
| `logical_name` | string | *(none: FuseSoC default)* | VHDL library of the outputs |

#### rvcc_gen

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `file` | string | *(mandatory)* | Source file (must exist) |
| `type` | string | *(mandatory)* | Accepted values: `c`, `s`, `elf`, `hex` (the Makefile compiles the file with GCC in every case) |
| `entity` | string | `WardRV_ROM` | ROM entity name |
| `model` | string | `generic` | ROM template: `generic` or `xilinx` |
| `cflags` | string | `""` | Extra GCC options; relative `-I` paths are prefixed with the calling core root |
| `stack_size` | integer | `128` | Stack size in bytes (`-Wstack-usage`, `-z stack-size`); not listed in the core usage text |
| `logical_name` | string | *(none: FuseSoC default)* | VHDL library of the outputs |

Environment: `pbcc_gen` needs `PICOASM_HOME` (and `PBCC_HOME` for C input); `rvcc_gen` uses `RISCV_PREFIX` (default `riscv64-unknown-elf-`) and optionally `HEX2VHD_HOME` (default `generators/gen_rom`).

### Ports

The main reusable unit is the CSR bank generated by regtool, `<X>_registers` (`<X>_csr.vhd`):

#### Generics

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `MODULE_NAME` | string | `""` | Name reported in `sbi_tgt_o.info.name` (`sbi` interface; hjson `name` when empty) |
| one per hjson `parameters` entry | hjson `type` | *(none)* | Used in `params` (FIFO depths, ...), `enable` or field `expr` |

#### Clock & Reset

| Name | Direction | Type | Description |
|------|-----------|------|-------------|
| `clk_i` | in | std_logic | Clock |
| `arst_b_i` | in | std_logic | Asynchronous reset, active low |

#### Bus (one of three, hjson `interface`)

| Name | Direction | Type | Description |
|------|-----------|------|-------------|
| `cs_i`, `re_i`, `we_i` | in | std_logic | `reg`: chip select, read, write |
| `addr_i` | in | std_logic_vector(`<X>`_ADDR_WIDTH-1 downto 0) | `reg`: address |
| `wdata_i` / `rdata_o` | in / out | std_logic_vector(width-1 downto 0) | `reg`: write / read data |
| `busy_o` | out | std_logic | `reg`: access not completed |
| `pbi_ini_i` / `pbi_tgt_o` | in / out | pbi_ini_t / pbi_tgt_t | `pbi` (`busy`) |
| `sbi_ini_i` / `sbi_tgt_o` | in / out | sbi_ini_t / sbi_tgt_t | `sbi` (`ready = not busy`, `info.name`) |

#### CSR (hardware side)

| Name | Direction | Type | Description |
|------|-----------|------|-------------|
| `sw2hw_o` | out | `<X>`_sw2hw_t | Only if a register has a software-to-hardware item: field values, `re` / `we` strobes (`ready` / `valid` and empty / full flags for FIFOs) |
| `hw2sw_i` | in | `<X>`_hw2sw_t | Only if a register has a hardware-to-software item: field values, `we` (`valid` / `ready` for FIFOs) |

### Instantiation Example

Generation in the calling core, as in `asylum-communication-spi/SPI.core`:

```yaml
generate:
  gen_csr:
    generator : regtool
    parameters:
      file         : hdl/csr/SPI.hjson
      name         : SPI
      copy         : hdl/csr
      logical_name : asylum

filesets:
  hdl:
    files        : [hdl/spi_pkg.vhd, hdl/spi_master.vhd, hdl/sbi_SPI.vhd]
    file_type    : vhdlSource
    logical_name : asylum
    depend       :
      - asylum:utils:generators
      - asylum:utils:pkg

targets:
  default:
    filesets : [hdl]
    generate : [gen_csr]
```

ROM generation, as in `asylum-soc-picosoc/PicoSoC.core`:

```yaml
generate:
  gen_picoblaze3_user_c:
    generator : pbcc_gen
    parameters:
      file         : esw/user.c
      type         : c
      entity       : ROM_user
      cflags       : -Dpicoblaze -Iesw/include --verbose --all-callee-saves
      logical_name : asylum

  gen_rv32i_user_c_identity:
    generator : rvcc_gen
    parameters:
      file         : esw/user_identity.c
      type         : c
      entity       : ROM_user
      cflags       : -Iesw/include --verbose
      logical_name : asylum
```

Use of the generated bank in VHDL (as in `asylum-system-spinlock`):

```vhdl
library asylum;
use     asylum.sbi_pkg.all;
use     asylum.spinlock_csr_pkg.all;   -- generated by regtool (name: spinlock)

  ins_csr : spinlock_registers
    generic map
    ( MODULE_NAME => NAME
    )
    port map
    ( clk_i     => clk_i
     ,arst_b_i  => arst_b_i
     ,sbi_ini_i => sbi_ini_i
     ,sbi_tgt_o => sbi_tgt_o
     ,sw2hw_o   => sw2hw
    );
```

## HDL Modules

| File | Unit | Kind | Role |
|------|------|------|------|
| [tools/regtool/hdl/csr_pkg.vhd](tools/regtool/hdl/csr_pkg.vhd) | `csr_pkg` | package | Component declarations of `csr_ext`, `csr_fifo`, `csr_reg` |
| [tools/regtool/hdl/csr_reg.vhd](tools/regtool/hdl/csr_reg.vhd) | `csr_reg` | entity | Storage register with software access model (`hwtype: reg`) |
| [tools/regtool/hdl/csr_ext.vhd](tools/regtool/hdl/csr_ext.vhd) | `csr_ext` | entity | Pass-through, storage outside the bank (`hwtype: ext`) |
| [tools/regtool/hdl/csr_fifo.vhd](tools/regtool/hdl/csr_fifo.vhd) | `csr_fifo` | entity | SW2HW / HW2SW FIFO register (`hwtype: fifo`) |
| [generators/gen_rom/ROM/generic/ROM_form.vhd](generators/gen_rom/ROM/generic/ROM_form.vhd) | `{name}` | template | rvcc ROM, architectures `rtl` (case) and `rom` (constant array) |
| [generators/gen_rom/ROM/xilinx/ROM_form.vhd](generators/gen_rom/ROM/xilinx/ROM_form.vhd), [ROM_form.v](generators/gen_rom/ROM/xilinx/ROM_form.v) | `{name}` | template | rvcc ROM, Xilinx model |
| [generators/gen_rom/ROM/pkg/ROM_pkg.vhd](generators/gen_rom/ROM/pkg/ROM_pkg.vhd) | `{name}_pkg` | template | ROM package: `{name}_ADDR_WIDTH`, `{name}_DATA_WIDTH`, component (`clk_i`, `cke_i`, `address_i`, `instruction_o`) |
| [tools/picoasm/ROM/](tools/picoasm/ROM/) | `{name}` | template | picoasm ROM templates (`generic`, `xilinx`), installed in `$PICOASM_HOME/share/picoasm` |
| [tools/regtool/examples/example1_csr.vhd](tools/regtool/examples/example1_csr.vhd), [example1_csr_pkg.vhd](tools/regtool/examples/example1_csr_pkg.vhd) | `example1_registers`, `example1_csr_pkg` | entity, package | regtool output for [example1.hjson](tools/regtool/examples/example1.hjson) (`reg` interface) |

### csr_reg

#### Parameters

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `WIDTH` | positive | `1` | Register width |
| `INIT` | std_logic_vector | *(none)* | Reset value |
| `MODEL` | string | *(none)* | Software access model (`ro`, `rw`, `wo`, `rw1c`, `rw0c`, `rw1s`, `rw0s`, `rsw1c`, `rcw1s`, `rsw0c`) |

#### Ports

| Name | Direction | Type | Description |
|------|-----------|------|-------------|
| `clk_i` | in | std_logic | Clock |
| `arst_b_i` | in | std_logic | Asynchronous reset, active low (register = `INIT`) |
| `sw_wd_i` | in | std_logic_vector(WIDTH-1 downto 0) | Software write data |
| `sw_rd_o` | out | std_logic_vector(WIDTH-1 downto 0) | Software read data (register value) |
| `sw_we_i` | in | std_logic | Software write enable |
| `sw_re_i` | in | std_logic | Software read enable |
| `sw_rbusy_o` | out | std_logic | Always `'0'` |
| `sw_wbusy_o` | out | std_logic | Always `'0'` |
| `hw_wd_i` | in | std_logic_vector(WIDTH-1 downto 0) | Hardware write data |
| `hw_rd_o` | out | std_logic_vector(WIDTH-1 downto 0) | Register value to the hardware |
| `hw_we_i` | in | std_logic | Hardware write enable |
| `hw_sw_re_o` | out | std_logic | Software read strobe, delayed by one cycle |
| `hw_sw_we_o` | out | std_logic | Software write strobe, delayed by one cycle |

### csr_ext

Same generics `WIDTH` (positive, default `1`) and same ports as `csr_reg`, without storage: `sw_rd_o <= hw_wd_i`, `hw_rd_o <= sw_wd_i`, `hw_sw_re_o <= sw_re_i`, `hw_sw_we_o <= sw_we_i` (not delayed), busy outputs at `'0'`.

### csr_fifo

#### Parameters

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `WIDTH` | positive | `1` | Data width |
| `BLOCKING_READ` | boolean | `false` | `true`: `sw_rbusy_o` while the HW2SW side is empty |
| `BLOCKING_WRITE` | boolean | `true` | `true`: `sw_wbusy_o` while the SW2HW side is full |
| `DEPTH_SW2HW` | natural | `0` | Depth of the software-to-hardware `fifo_sync` (0 = direct connection) |
| `DEPTH_HW2SW` | natural | `0` | Depth of the hardware-to-software `fifo_sync` (0 = direct connection) |

#### Ports

| Name | Direction | Type | Description |
|------|-----------|------|-------------|
| `clk_i` | in | std_logic | Clock |
| `arst_b_i` | in | std_logic | Asynchronous reset, active low |
| `sw_wd_i` / `sw_we_i` | in | std_logic_vector(WIDTH-1 downto 0) / std_logic | Software push (SW2HW) |
| `sw_rd_o` / `sw_re_i` | out / in | std_logic_vector(WIDTH-1 downto 0) / std_logic | Software pop (HW2SW) |
| `sw_rbusy_o`, `sw_wbusy_o` | out | std_logic | Blocking read / write (see generics) |
| `hw_tx_valid_i`, `hw_tx_ready_o`, `hw_tx_data_i` | in, out, in | std_logic, std_logic, std_logic_vector(WIDTH-1 downto 0) | Hardware push into the HW2SW path |
| `hw_tx_empty_o`, `hw_tx_full_o` | out | std_logic | HW2SW FIFO flags |
| `hw_rx_valid_o`, `hw_rx_ready_i`, `hw_rx_data_o` | out, in, out | std_logic, std_logic, std_logic_vector(WIDTH-1 downto 0) | Hardware pop from the SW2HW path |
| `hw_rx_empty_o`, `hw_rx_full_o` | out | std_logic | SW2HW FIFO flags |

With a depth of 0 the corresponding path is combinational: `hw_rx_valid_o = sw_we_i` / `hw_tx_ready_o = sw_re_i`, and the "full" (write) or "empty" (read) condition is the absence of `hw_rx_ready_i` / `hw_tx_valid_i`.

## Register Map

This repository provides regtool; the register map of each IP is documented in its own generated `hdl/csr/<X>_csr.md` (e.g. [asylum-communication-spi](https://github.com/deuskane/asylum-communication-spi) `hdl/csr/SPI_csr.md`). The hjson format accepted by regtool ([tools/regtool/regtool_schema.hjson](tools/regtool/regtool_schema.hjson), checks in [tools/regtool/regtool.py](tools/regtool/regtool.py)):

- **Top level**: `name` (mandatory), `desc`, `width` (data width, default 32, power of 2 and >= 8), `interface` (`reg` default, `pbi`, `sbi`), `parameters` (list of `name` / `type` / `desc`, become generics), `registers` (mandatory).
- **Register**: `name`, `fields` (mandatory), `desc`, `address` (default: previous address + width/8; must be unique and aligned on width/8), `enable` (`True`, `False` or the name of a boolean parameter: register inside an `if generate`), `alias_write` (this register's address becomes an extra write address of the named register; its own write path is removed), `hwtype`, `hwaccess`, `swaccess`, `params` (free key / value pairs passed as generics to `csr_fifo`: `BLOCKING_READ`, `BLOCKING_WRITE`, `DEPTH_SW2HW`, `DEPTH_HW2SW`).
- **Field**: `name`, `bits` (`"n"` or `"msb:lsb"`, mandatory, no overlap), `desc`, `init` (reset value, prefix `b`, `o`, `x`, `d` or none), `expr` (VHDL expression replacing `init`, e.g. a generic), `enum` (list of `name` / `value` / `desc`).
- **`hwtype`**: `reg` (default, `csr_reg`), `ext` (`csr_ext`), `fifo` (`csr_fifo`).
- **`hwaccess`**: `rw` (default), `ro` (hardware reads), `wo` (hardware writes), `none`.
- **`swaccess`**: `rw` (default), `ro`, `wo`, `rw1c`, `rw0c`, `rw1s`, `rw0s`, `rsw1c`, `rcw1s`, `rsw0c` (passed as `MODEL` to `csr_reg`, see Design Notes).

Generated files, all named after the generator `name`:

- `<X>_csr_pkg.vhd`: `<X>_ADDR_WIDTH` (ceil(log2(highest address + 1))), `<X>_DATA_WIDTH`, one address constant per register, `sw2hw` / `hw2sw` records, enum constants (`<X>_<REG>_<FIELD>_<ENUM>` and `..._RAW` shifted to the field position), component `<X>_registers`.
- `<X>_csr.vhd`: entity `<X>_registers` (address decode, read multiplexer returning 0 on unmapped addresses, busy handling, one building block per register).
- `<X>_csr.h`: register addresses, field position / mask, enum values, a `<X>_t` struct with padding.
- `<X>_csr.md`: address table and per-register / per-field descriptions.

## Verification

### Testbenches

There is no testbench and no CI workflow in this repository (the `Makefile` / `mk/` only run the lint targets below). The generators are exercised by the cores that use them:

| File | DUT | Description |
|------|-----|-------------|
| *(none in this repository)* | regtool + `csr_*` | Every target of an IP with a `gen_csr` entry (e.g. the `sim_*` targets of `asylum-communication-spi`) regenerates and compiles its CSR bank |
| *(none in this repository)* | `pbcc_gen`, `rvcc_gen` | Targets of `asylum-soc-picosoc` (`PicoSoC.core`) build the PicoBlaze and RISC-V ROMs |

### Targets

| Target | Toplevel | Description |
|--------|----------|-------------|
| `default` | *(none)* | `deps` fileset only (depends on `asylum:component:fifo`); not meant to be run |
| `lint_ghdl` | `csr_synth_top` | Lint: GHDL `-Wall` analysis and elaboration (empty simulation) of the regtool building blocks `csr_pkg`, `csr_reg` (one instance per software access model), `csr_ext`, `csr_fifo` in a wrapper with flat ports (`syn/ghdl/csr_synth_top.vhd`) |
| `lint_ghdl_synth` | `csr_synth_top` | Synthesis check: `lint_ghdl`, then `ghdl --synth -Wall` of 5 configurations (`syn/ghdl/ghdl_synth.sh`: defaults (`WIDTH = 8`, FIFO depths 0), `WIDTH = 1` with `INIT = "1"`, `INIT = x"A5"`, `csr_fifo` with FIFOs and blocking read, `csr_fifo` with FIFOs and non-blocking write), fails on a synthesis error or an inferred latch |

### How to Run

The generators run automatically when FuseSoC executes the setup stage of a target listing them in `generate:`. From a consuming IP:

```bash
make help                       # in the consuming IP
make default STEP=setup         # runs its generators (regtool for gen_csr)
fusesoc --cores-root . run --build-root build --setup --target default asylum:communication:SPI:2.0.0
```

Lint of the regtool building blocks, from this repository:

```bash
make lint_ghdl                  # GHDL -Wall lint (make nonreg_lint: every lint_* target)
make lint_ghdl_synth            # GHDL -Wall lint + ghdl --synth -Wall check
```

regtool can also be run standalone (Python 3 with `hjson`, `jsonschema`, `prettytable`, see [tools/regtool/requirements.txt](tools/regtool/requirements.txt)):

```bash
python3 tools/regtool/regtool.py tools/regtool/examples/example1.hjson --logical_name asylum \
        --vhdl_package example1_csr_pkg.vhd --vhdl_module example1_csr.vhd \
        --c_header example1_csr.h --doc_markdown example1_csr.md
```

Building the PicoBlaze tools (installs into `tools/install` by default, run from the repository root):

```bash
scripts/build_toolchain.sh -s -p          # -s: sdcc (pbccv2-src-20111024), -p: picoasm, -i <dir>: install directory
```

## Synthesis

No dedicated synthesis target. `csr_reg`, `csr_ext` and `csr_fifo` and the generated `<X>_registers` are plain synthesizable RTL (no simulation-only code). The ROM templates provide an `rtl` architecture (synchronous `case` on the address) and a `rom` architecture (constant array). Resource usage of a CSR bank depends on the register widths and on the FIFO depths given to `csr_fifo`.

## Design Notes

### csr_reg Access Models

Next value of the register (`hw` = `hw_wd_i` when `hw_we_i = 1`, else the current value):

| MODEL | Software write | Software read | Priority |
|-------|----------------|---------------|----------|
| `ro` | ignored | no effect | hardware write only |
| `rw` | `sw_wd_i` | no effect | software write over hardware write |
| `wo` | `sw_wd_i` | no effect (regtool returns 0 on the bus) | software write over hardware write |
| `rw1c` | clears bits written at 1 | no effect | `hw and not sw_wd_i` |
| `rw0c` | clears bits written at 0 | no effect | `hw and sw_wd_i` |
| `rw1s` | sets bits written at 1 | no effect | `hw or sw_wd_i` |
| `rw0s` | sets bits written at 0 | no effect | `hw or not sw_wd_i` |
| `rsw1c` | clears bits written at 1 | sets all bits | hardware write, then read |
| `rcw1s` | sets bits written at 1 | clears all bits | hardware write, then read |
| `rsw0c` | clears bits written at 0 | sets all bits | hardware write, then read |

`wo` stores the software writes exactly like `rw`; regtool does not put a `wo` register in the read data multiplexer (`<reg>_re = '0'`, `<reg>_rdata = 0`), so software reads return 0. `wo` is also used on `fifo` registers (software to hardware FIFO), as in `example1.hjson` and `SPI.hjson`.

### Generator Notes (as coded)

- The generators serialize `run` and `write` with a lock file in the work directory (`.regtool.lock`, `.pbcc.lock`, `.rvcc.lock`).
- The regtool `Makefile` regenerates an output when it is older than the hjson or than the regtool sources (`REGTOOL_FILES`: `*.py` and `*.hjson` of `tools/regtool/`).
- `tools/regtool/regtool.py` writes `<name>_dump1.hjson`, `_dump2.hjson`, `_dump3.hjson` (raw, defaults filled, after checks) in the current directory.
- `pbcc_gen` builds the ROM package with `gen_rom.py ... --data-width 18` (PicoBlaze 18-bit instructions, default 10-bit address); the ROM entity itself comes from picoasm.
- `rvcc_gen` calls `gen_rom.py` with its defaults (32-bit data, 10-bit address = 1024 words = 4 KB), while `link.ld` declares a 32 KB ROM. A program between 4 KB and 32 KB links, then `gen_rom.py` rejects the hex file and exits with status 1, which stops the generator `make`. Which size is intended (a 4 KB `link.ld`, or an `--addr-width` parameter for the ROM) is not decided by the code, so both are left unchanged.
- `gen_rom.py` exits with status 1 on any error (hex file larger than the ROM, unreadable hex or template file).
- `build_toolchain.sh` currently builds `tools/pbccv2-src-20111024/sdcc3` (the `pbccv2-src-20110901` and `sdcc-3.1.0` lines are commented out).

## Directory Structure

```
asylum-utils-generators/
├── generators.core              # FuseSoC core (asylum:utils:generators), generators: section
├── Makefile                     # Common Asylum Makefile (FuseSoC wrapper)
├── mk/
│   ├── defs.mk                  # FILE_CORE, default TARGET and TOOL
│   └── targets.txt              # Target list (generated from the .core)
├── syn/ghdl/
│   ├── csr_synth_top.vhd        # Lint / synthesis check top (csr_reg, csr_ext, csr_fifo)
│   └── ghdl_synth.sh            # ghdl --synth check (post_run hook of lint_ghdl_synth)
├── doc/
│   └── pbccv2_user_manual.pdf   # PicoBlaze C compiler manual
├── generators/
│   ├── regtool/                 # regtool.py + templates/Makefile.j2
│   ├── pbcc/                    # pbcc.py + templates/Makefile.j2
│   ├── rvcc/                    # rvcc.py + templates/{Makefile.j2,start.S,link.ld}
│   └── gen_rom/                 # gen_rom.py + ROM/{generic,xilinx,pkg} templates
├── scripts/
│   ├── build_toolchain.sh
│   ├── component.py
│   └── gen_target.sh
└── tools/
    ├── regtool/                 # regtool.py, addrmap.py, schema, hdl/, examples/
    ├── picoasm/                 # PicoBlaze assembler sources + ROM templates
    ├── pbccv2-src-20110901/     # SDCC sources (PicoBlaze port)
    ├── pbccv2-src-20111024/     # SDCC sources (PicoBlaze port, used by build_toolchain.sh)
    └── sdcc-3.1.0/              # SDCC 3.1.0 sources
```

## Dependencies

| Core | Used by (fileset) | Purpose |
|------|-------------------|---------|
| `asylum:component:fifo` | `deps` | `fifo_sync` / `fifo_pkg` used by `csr_fifo` |

Python modules: `fusesoc`, `jinja2` (generators), `hjson`, `jsonschema`, `prettytable` (regtool). External tools: GNU make, sdcc / picoasm (`PBCC_HOME`, `PICOASM_HOME`), RISC-V GCC binutils (`RISCV_PREFIX`), `hexdump`.
