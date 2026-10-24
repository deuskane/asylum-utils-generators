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

VLNV: `asylum:utils:generators:2.9.0`

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

- **`regtool`**: reads a register description (`hdl/csr/<X>.hjson`) and produces a CSR bank (`<X>_registers`, VHDL, Verilog or SystemVerilog) with its package / header, a C header and a Markdown documentation. The CSR logic has a memory interface; a bus (`sbi`, `pbi`, `apb`, `axi4lite`) is connected through a bridge `<bus>2mem`. Used by every IP with registers (`gen_csr` in their core).
- **`pbcc_gen`**: compiles a C file with the PicoBlaze port of SDCC (pbcc) or takes a KCPSM3 / PBlazeIDE assembler file, assembles it with picoasm and produces a ROM entity plus its component package (OpenBlaze8 / PicoBlaze-3 processors).
- **`rvcc_gen`**: compiles C / assembler with a RISC-V GCC toolchain (`rv32i`) and produces a ROM entity plus its component package (WardRV processor).

Every generator renders a `Makefile` from a Jinja2 template, runs `make` in the FuseSoC generator work directory under an exclusive file lock, and registers the produced files in the calling core. The core itself has no HDL fileset: its `default` target only pulls `asylum:component:fifo`, required by the `csr_fifo` building block that regtool adds to the calling core. The `sim_*` targets verify regtool (see [Verification](#verification)).

### Key Features

- regtool: hjson schema validation, 10 software access models, `reg` / `ext` / `fifo` hardware types, hjson parameters mapped to VHDL generics / Verilog / SystemVerilog parameters, conditional registers (`enable`), write aliases, shared addresses, enumerated field values
- regtool interfaces: `mem` (memory interface of the CSR logic, `reg` is its former name), and the buses `sbi`, `pbi`, `apb` (APB3), `axi4lite` through the bridges `<bus>2mem` (`interface` in the hjson or in the generator parameters)
- regtool outputs: VHDL (`<X>_csr.vhd`, `<X>_csr_pkg.vhd`), Verilog 2005 (`<X>_csr.v`, `<X>_csr_pkg.vh`, records flattened in ports) or SystemVerilog (`<X>_csr.sv`, `<X>_csr_pkg.sv`, records as packed structs; Verilog / SystemVerilog : interfaces `mem`, `apb`, `axi4lite`), `<X>_csr.h`, `<X>_csr.md`, optionally copied back into the source tree (`copy`)
- regtool code: the CSR model ([csr_model.py](tools/regtool/csr_model.py)) is separated from the generators; [gen_hdl.py](tools/regtool/gen_hdl.py) builds the CSR package and module as a generic HDL description ([hdl_model.py](tools/regtool/hdl_model.py)), written by the generic writers [gen_vhdl.py](tools/regtool/gen_vhdl.py), [gen_verilog.py](tools/regtool/gen_verilog.py) and [gen_systemverilog.py](tools/regtool/gen_systemverilog.py) (no CSR knowledge); `gen_c.py`, `gen_markdown.py` for the C header and the documentation
- CSR building blocks in VHDL and Verilog: `csr_reg`, `csr_ext`, `csr_fifo` (with optional FIFOs and blocking access), `csr_pkg` (VHDL), bridges `sbi2mem`, `pbi2mem` (VHDL), `apb2mem`, `axi4lite2mem`
- Verification: pytest unit tests of regtool, one FuseSoC simulation target per interface and scenario (VHDL), iverilog simulations of the Verilog and SystemVerilog outputs (pytest)
- pbcc_gen: C (`c`) or assembler (`kcpsm3`, `pblazeide`) input, `generic` or `xilinx` ROM model, user `cflags` (relative `-I` paths resolved from the calling core)
- rvcc_gen: C / assembler input, `start.S` and `link.ld` templates, stack size check, listing / map / size reports, `rv32i_zicsr` used when the compiler supports it
- Generated `*-gen_csr_*` directories automatically added to the include path of pbcc / rvcc (C code can include `<X>_csr.h`)
- Bundled tool sources: picoasm, PicoBlaze SDCC ports and SDCC 3.1.0, plus [doc/pbccv2_user_manual.pdf](doc/pbccv2_user_manual.pdf)
- Helper scripts: toolchain build, component package generation, pbcc target generation

## Block Diagram

- `regtool` (FuseSoC wrapper, [generators/regtool/regtool.py](generators/regtool/regtool.py)) calls the standalone tool [tools/regtool/regtool.py](tools/regtool/regtool.py) once per output file, then adds the building blocks (`csr_pkg` / `csr_reg` / `csr_ext` / `csr_fifo`, `.vhd` or `.v`), the bridge `<interface>2mem` (if the interface is not `mem`) and the generated files to the calling core.
- [tools/regtool/regtool.py](tools/regtool/regtool.py): `csr_model.py` (hjson -> checked CSR model) -> `gen_hdl.py` (CSR model -> package and module in `hdl_model`) -> `gen_vhdl.py`, `gen_verilog.py` or `gen_systemverilog.py` (generic writers); `csr_model.py` -> `gen_c.py` / `gen_markdown.py`.
- Generated `<X>_registers`: bus -> `<bus>2mem` -> memory interface (`cs` / `re` / `we` / `addr` / `wdata` / `rdata` / `busy`) -> address decode, read multiplexer, one building block per register -> `sw2hw` / `hw2sw`.
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
| regtool | Python tool | [tools/regtool/regtool.py](tools/regtool/regtool.py) (command line), [csr_model.py](tools/regtool/csr_model.py), [addrmap.py](tools/regtool/addrmap.py), [regtool_schema.hjson](tools/regtool/regtool_schema.hjson) | hjson parser / checker (CSR model) |
| regtool HDL generator | Python tool | [gen_hdl.py](tools/regtool/gen_hdl.py) | CSR model -> package / module of the CSR (`hdl_model`), calls the VHDL, Verilog or SystemVerilog writer |
| HDL model and writers | Python tool | [hdl_model.py](tools/regtool/hdl_model.py), [gen_vhdl.py](tools/regtool/gen_vhdl.py), [gen_verilog.py](tools/regtool/gen_verilog.py), [gen_systemverilog.py](tools/regtool/gen_systemverilog.py) | Generic description of a package / module (types, records, expressions, signals, assignments, instances, generate) and its VHDL / Verilog / SystemVerilog writers (the SystemVerilog writer derives the Verilog one), independent of the CSR |
| regtool documentation generators | Python tool | [gen_c.py](tools/regtool/gen_c.py), [gen_markdown.py](tools/regtool/gen_markdown.py) | C header, Markdown |
| `csr_pkg`, `csr_reg`, `csr_ext`, `csr_fifo` | VHDL, Verilog | [tools/regtool/hdl/](tools/regtool/hdl/) | CSR building blocks instantiated by generated banks |
| `sbi2mem`, `pbi2mem`, `apb2mem`, `axi4lite2mem` | VHDL (+ Verilog for apb, axi4lite) | [tools/regtool/hdl/](tools/regtool/hdl/) | Bridges from a bus to the memory interface of the CSR |
| regtool tests | pytest, VHDL, Verilog | [tools/regtool/tests/](tools/regtool/tests/), [tools/regtool/sim/](tools/regtool/sim/) | Unit tests and testbenches (see [Verification](#verification)) |
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
| `interface` | string | *(hjson `interface`)* | Replaces the interface of the hjson file: `mem`, `sbi`, `pbi`, `apb`, `axi4lite` |
| `language` | string | `vhdl` | `vhdl` (`<name>_csr_pkg.vhd`, `<name>_csr.vhd`), `verilog` (`<name>_csr_pkg.vh`, `<name>_csr.v`) or `systemverilog` (`<name>_csr_pkg.sv`, `<name>_csr.sv`, `systemVerilogSource`: compile as SystemVerilog, e.g. `iverilog -g2012`); Verilog / SystemVerilog : interfaces `mem`, `apb`, `axi4lite` |

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

The main reusable unit is the CSR bank generated by regtool, `<X>_registers` (`<X>_csr.vhd`; the Verilog module `<X>_csr.v` has the same ports, with the `sw2hw` / `hw2sw` records flattened in `sw2hw_<reg>_<item>_o` / `hw2sw_<reg>_<item>_i` and the hjson parameters as module parameters, default 0; the SystemVerilog module `<X>_csr.sv` keeps the records as packed structs `<X>_sw2hw_t` / `<X>_hw2sw_t` of `<X>_csr_pkg`):

#### Generics

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `MODULE_NAME` | string | `""` | `sbi` interface only: name reported in `sbi_tgt_o.info.name` (hjson `name` when empty, generic `DEFAULT_NAME` of `sbi2mem`) |
| one per hjson `parameters` entry | hjson `type` | *(none)* | Used in `params` (FIFO depths, ...), `enable` or field `expr` |

#### Clock & Reset

| Name | Direction | Type | Description |
|------|-----------|------|-------------|
| `clk_i` | in | std_logic | Clock |
| `arst_b_i` | in | std_logic | Asynchronous reset, active low |

#### Bus (one of five, hjson `interface`)

The CSR logic has the memory interface (`mem`); for the other interfaces the bus ports are connected to the bridge `<interface>2mem` (same port names). `<AW>` = `<X>`_ADDR_WIDTH (ceil(log2(highest address + 1)); at least 1 in Verilog), `<DW>` = hjson `width`.

| Name | Direction | Type | Description |
|------|-----------|------|-------------|
| `cs_i`, `re_i`, `we_i` | in | std_logic | `mem`: chip select, read, write |
| `addr_i` | in | std_logic_vector(`<AW>`-1 downto 0) | `mem`: byte address |
| `wdata_i` / `rdata_o` | in / out | std_logic_vector(`<DW>`-1 downto 0) | `mem`: write / read data (read data combinational) |
| `busy_o` | out | std_logic | `mem`: access not completed, the access is held until `busy_o = 0` |
| `pbi_ini_i` / `pbi_tgt_o` | in / out | pbi_ini_t / pbi_tgt_t | `pbi` (`pbi2mem`: `busy`) |
| `sbi_ini_i` / `sbi_tgt_o` | in / out | sbi_ini_t / sbi_tgt_t | `sbi` (`sbi2mem`: `ready = not busy`, `info.name`) |
| `s_apb_psel_i`, `s_apb_penable_i`, `s_apb_pwrite_i`, `s_apb_paddr_i`, `s_apb_pwdata_i` | in | std_logic, std_logic_vector | `apb` (`apb2mem`, APB3) |
| `s_apb_prdata_o`, `s_apb_pready_o`, `s_apb_pslverr_o` | out | std_logic_vector, std_logic | `apb`: `pready = not busy`, `pslverr = 0` |
| `s_axi_aw*`, `s_axi_w*` (`wstrb` not used), `s_axi_b*`, `s_axi_ar*`, `s_axi_r*` | in / out | std_logic, std_logic_vector | `axi4lite` (`axi4lite2mem`), no `awprot` / `arprot` |

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
| [tools/regtool/hdl/sbi2mem.vhd](tools/regtool/hdl/sbi2mem.vhd) | `sbi2mem` | entity | SBI -> memory interface (combinational, generics `NAME` / `DEFAULT_NAME` (if `NAME` is empty) for `info.name`) |
| [tools/regtool/hdl/pbi2mem.vhd](tools/regtool/hdl/pbi2mem.vhd) | `pbi2mem` | entity | PBI -> memory interface (combinational) |
| [tools/regtool/hdl/apb2mem.vhd](tools/regtool/hdl/apb2mem.vhd), [apb2mem.v](tools/regtool/hdl/apb2mem.v) | `apb2mem` | entity, module | APB3 -> memory interface (combinational, access phase) |
| [tools/regtool/hdl/axi4lite2mem.vhd](tools/regtool/hdl/axi4lite2mem.vhd), [axi4lite2mem.v](tools/regtool/hdl/axi4lite2mem.v) | `axi4lite2mem` | entity, module | AXI4-Lite -> memory interface (FSM, one access at a time) |
| [tools/regtool/hdl/csr_reg.v](tools/regtool/hdl/csr_reg.v), [csr_ext.v](tools/regtool/hdl/csr_ext.v), [csr_fifo.v](tools/regtool/hdl/csr_fifo.v), [csr_fifo_sync.v](tools/regtool/hdl/csr_fifo_sync.v) | `csr_reg`, `csr_ext`, `csr_fifo`, `csr_fifo_sync` | module | Verilog building blocks (same behaviour; `csr_fifo_sync` replaces `fifo_sync`) |
| [generators/gen_rom/ROM/generic/ROM_form.vhd](generators/gen_rom/ROM/generic/ROM_form.vhd) | `{name}` | template | rvcc ROM, architectures `rtl` (case) and `rom` (constant array) |
| [generators/gen_rom/ROM/xilinx/ROM_form.vhd](generators/gen_rom/ROM/xilinx/ROM_form.vhd), [ROM_form.v](generators/gen_rom/ROM/xilinx/ROM_form.v) | `{name}` | template | rvcc ROM, Xilinx model |
| [generators/gen_rom/ROM/pkg/ROM_pkg.vhd](generators/gen_rom/ROM/pkg/ROM_pkg.vhd) | `{name}_pkg` | template | ROM package: `{name}_ADDR_WIDTH`, `{name}_DATA_WIDTH`, component (`clk_i`, `cke_i`, `address_i`, `instruction_o`) |
| [tools/picoasm/ROM/](tools/picoasm/ROM/) | `{name}` | template | picoasm ROM templates (`generic`, `xilinx`), installed in `$PICOASM_HOME/share/picoasm` |
| [tools/regtool/examples/example1_csr.vhd](tools/regtool/examples/example1_csr.vhd), [example1_csr_pkg.vhd](tools/regtool/examples/example1_csr_pkg.vhd) | `example1_registers`, `example1_csr_pkg` | entity, package | regtool output for [example1.hjson](tools/regtool/examples/example1.hjson) (`mem` interface) |

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

This repository provides regtool; the register map of each IP is documented in its own generated `hdl/csr/<X>_csr.md` (e.g. [asylum-communication-spi](https://github.com/deuskane/asylum-communication-spi) `hdl/csr/SPI_csr.md`). The hjson format accepted by regtool ([tools/regtool/regtool_schema.hjson](tools/regtool/regtool_schema.hjson), checks in [tools/regtool/csr_model.py](tools/regtool/csr_model.py)):

- **Top level**: `name` (mandatory), `desc`, `width` (data width, default 32, power of 2 and >= 8), `interface` (`mem` default, `sbi`, `pbi`, `apb`, `axi4lite`; `reg` = `mem`), `parameters` (list of `name` / `type` / `desc`, become generics), `registers` (mandatory).
- **Register**: `name`, `fields` (mandatory), `desc`, `address` (default: previous address + width/8; aligned on width/8; an address can be shared by several registers if the software reads at most one of them and writes at most one of them at this address, e.g. a `wo` command register and a `ro` status register), `enable` (`True`, `False` or the name of a boolean parameter: register inside an `if generate`), `alias_write` (this register's address becomes an extra write address of the named register; its own write path is removed), `hwtype`, `hwaccess`, `swaccess`, `params` (free key / value pairs passed as generics to `csr_fifo`: `BLOCKING_READ`, `BLOCKING_WRITE`, `DEPTH_SW2HW`, `DEPTH_HW2SW`).
- **Field**: `name`, `bits` (`"n"` or `"msb:lsb"`, mandatory, no overlap), `desc`, `init` (reset value, prefix `b`, `o`, `x`, `d` or none), `expr` (VHDL expression replacing `init`, e.g. a generic; the Verilog generator translates booleans, bit strings and `(msb downto lsb)` slices), `enum` (list of `name` / `value` / `desc`).
- **`hwtype`**: `reg` (default, `csr_reg`), `ext` (`csr_ext`), `fifo` (`csr_fifo`).
- **`hwaccess`**: `rw` (default), `ro` (hardware reads), `wo` (hardware writes), `none`.
- **`swaccess`**: `rw` (default), `ro`, `wo`, `rw1c`, `rw0c`, `rw1s`, `rw0s`, `rsw1c`, `rcw1s`, `rsw0c` (passed as `MODEL` to `csr_reg`, see Design Notes).

Generated files, all named after the generator `name`:

- `<X>_csr_pkg.vhd`: `<X>_ADDR_WIDTH` (ceil(log2(highest address + 1))), `<X>_DATA_WIDTH`, one address constant per register, `sw2hw` / `hw2sw` records, enum constants (`<X>_<REG>_<FIELD>_<ENUM>` and `..._RAW` shifted to the field position), component `<X>_registers`.
- `<X>_csr.vhd`: entity `<X>_registers` (address decode, read multiplexer returning 0 on unmapped addresses, busy handling, one building block per register).
- `<X>_csr.v` (`language: verilog`): module `<X>_registers`, same architecture as the VHDL entity.
- `<X>_csr_pkg.vh` (`language: verilog`): `` `define `` of the package constants (`<X>_ADDR_WIDTH`, `<X>_DATA_WIDTH`, the register addresses and the enum values); the module copies the constants it uses as `localparam`.
- `<X>_csr_pkg.sv` / `<X>_csr.sv` (`language: systemverilog`): package `<X>_csr_pkg` (constants as `localparam`, `typedef struct packed` of the `sw2hw` / `hw2sw` records, same items as VHDL) and module `<X>_registers` importing it (ports `output <X>_sw2hw_t sw2hw_o`, `input <X>_hw2sw_t hw2sw_i`).
- `<X>_csr.h`: register addresses, field position / mask, enum values, a `<X>_t` struct with padding (one member per address, named `<reg1>_<reg2>` for a shared address).
- `<X>_csr.md`: address table and per-register / per-field descriptions.

## Verification

### Testbenches

| File | DUT | Description |
|------|-----|-------------|
| [tools/regtool/tests/](tools/regtool/tests/) | regtool (Python) | pytest unit tests: parsers, CSR model checks, generic VHDL / Verilog / SystemVerilog writers (`test_gen_vhdl.py`, `test_gen_verilog.py`, `test_gen_systemverilog.py`, on a module without CSR), CSR package / module (`test_gen_hdl.py`), C / Markdown, command line, golden files of the examples; GHDL analysis / elaboration, verilator lint and iverilog compilation / simulation when the tools are in the `PATH` |
| [tools/regtool/sim/tb_regtool_scenario.vhd](tools/regtool/sim/tb_regtool_scenario.vhd) | `tbcsr_registers` | Scenarios (generic `TEST`), clock, reset, hardware side and monitors, independent of the bus |
| [tools/regtool/sim/tb_regtool_&lt;interface&gt;.vhd](tools/regtool/sim/) | `tbcsr_registers` + bridge | One top per interface (`mem`, `sbi`, `pbi`, `apb`, `axi4lite`): DUT, bus master `tb_<interface>_master.vhd`, scenario |
| [tools/regtool/sim/tb_regtool.v](tools/regtool/sim/tb_regtool.v) | `tbcsr_registers` (Verilog, SystemVerilog with `TB_SV`) | Same scenarios for the Verilog and SystemVerilog outputs (`mem`, `apb`, `axi4lite`) plus `axi_concurrent`, run by [test_sim_verilog.py](tools/regtool/tests/test_sim_verilog.py) (44 simulations) |
| [tools/regtool/sim/tbcsr.hjson](tools/regtool/sim/tbcsr.hjson) | | CSR of the testbenches: `rw`, `ro` written by the hardware, `rw1c`, `wo`, `ext`, FIFO with blocking read (depth 2), FIFO with blocking write (depth 1) |

Scenarios (one per simulation, each one starts from reset):

| `TEST` | Checks |
|--------|--------|
| `reset` | Reset values on the bus and on the hardware side |
| `write_read` | Software write / read back (only the field bits), write strobe, write only register (reads 0) |
| `hw_write` | Register written by the hardware, read only register not written by the software, `rw1c` |
| `ext` | External register: read data from the hardware, write data and strobe to the hardware |
| `fifo_read` | Blocking read of an empty FIFO (bus wait states), FIFO order, full / empty flags |
| `fifo_write` | Blocking write of a full FIFO (bus wait states), data popped in order |
| `unmapped` | Unmapped address: reads 0, write without effect |
| `axi_concurrent` | Verilog / SystemVerilog `axi4lite` only: read and write requested together (round robin) |

The bus masters check the protocols: APB setup / access phases and `pslverr`, AXI4-Lite W one cycle after AW, `bready` / `rready` two cycles after `bvalid` / `rvalid` (the response must be held, OKAY). Mutants of the bridges and of the Verilog building blocks are detected by these scenarios. The generators are also exercised by the cores that use them (every target of an IP with a `gen_csr` entry; `pbcc_gen`, `rvcc_gen`: targets of `asylum-soc-picosoc`).

### Targets

| Target | Toplevel | Description |
|--------|----------|-------------|
| `default` | *(none)* | `deps` fileset only (depends on `asylum:component:fifo`); not meant to be run |
| `sim_regtool_example1` | `asylum.example1_registers` | Generates the CSR of example1, analyzes and elaborates it with GHDL |
| `sim_regtool_<interface>_<scenario>` | `asylum.tb_regtool_<interface>` | 35 targets: interface `mem`, `sbi`, `pbi`, `apb`, `axi4lite` x scenario of the table above (`TEST=<scenario>`) |
| `tb_regtool_<interface>` | `asylum.tb_regtool_<interface>` | Base of the `sim_regtool_<interface>_*` targets (default scenario `reset`) |

The CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs one job per `sim_*` target (`make ci_generate`) and the job `regtool_pytest`.

### How to Run

The FuseSoC targets (GHDL, `asylum-cores` library):

```bash
make help                                     # list of the targets
make sim_regtool_axi4lite_fifo_read           # one scenario
make nonreg_sim TARGETS_FILTER=^sim_regtool_apb   # every scenario of the apb interface
```

The pytest unit tests (Python 3; GHDL, iverilog and verilator are optional, the tests that need them are skipped otherwise):

```bash
pip install -r tools/regtool/requirements_test.txt   # hjson, jsonschema, prettytable, pytest, pytest-xdist
python3 -m pytest tools/regtool                      # every test, summary at the end
python3 -m pytest tools/regtool -n auto              # in parallel (pytest-xdist)
python3 -m pytest tools/regtool -k verilog -v        # only the tests with "verilog" in their name, one line per test
python3 -m pytest tools/regtool/tests/test_model.py  # one file
python3 -m pytest tools/regtool --update-golden      # rewrite the generated examples (tools/regtool/examples) after an intended change
```

pytest collects the `test_*` functions of `tools/regtool/tests/test_*.py`; a test passes if it ends without exception (`assert` failed or error). `@pytest.mark.parametrize` runs a test once per set of values (one line per case in `-v`). The fixtures (`make_csr`, `generate`, `tmp_path`, ...) are the arguments of the tests, defined in [conftest.py](tools/regtool/tests/conftest.py) or by pytest. `ASYLUM_UTILS_PKG_DIR` gives `sbi_pkg.vhd` / `pbi_pkg.vhd` to the GHDL tests of the `sbi` / `pbi` interfaces (default: `asylum-utils-pkg` next to this repository).

The generators run automatically when FuseSoC executes the setup stage of a target listing them in `generate:`. From a consuming IP:

```bash
make help                       # in the consuming IP
make default STEP=setup         # runs its generators (regtool for gen_csr)
fusesoc --cores-root . run --build-root build --setup --target default asylum:communication:SPI:2.0.0
```

regtool can also be run standalone (Python 3 with `hjson`, `jsonschema`, `prettytable`, see [tools/regtool/requirements.txt](tools/regtool/requirements.txt)):

```bash
python3 tools/regtool/regtool.py tools/regtool/examples/example1.hjson --logical_name asylum \
        --vhdl_package example1_csr_pkg.vhd --vhdl_module example1_csr.vhd \
        --c_header example1_csr.h --doc_markdown example1_csr.md
# Verilog / SystemVerilog (only if requested), with another interface
python3 tools/regtool/regtool.py tools/regtool/examples/example1.hjson --interface axi4lite \
        --verilog_module example1_csr.v --verilog_header example1_csr_pkg.vh \
        --sv_module example1_csr.sv --sv_package example1_csr_pkg.sv
```

Building the PicoBlaze tools (installs into `tools/install` by default, run from the repository root):

```bash
scripts/build_toolchain.sh -s -p          # -s: sdcc (pbccv2-src-20111024), -p: picoasm, -i <dir>: install directory
```

## Synthesis

No dedicated synthesis target. `csr_reg`, `csr_ext`, `csr_fifo`, the bridges and the generated `<X>_registers` (VHDL, Verilog and SystemVerilog) are plain synthesizable RTL (no simulation-only code); `apb2mem` and `axi4lite2mem` pass `ghdl --synth`, the Verilog / SystemVerilog files are verilator `-Wall` lint clean. The ROM templates provide an `rtl` architecture (synchronous `case` on the address) and a `rom` architecture (constant array). Resource usage of a CSR bank depends on the register widths and on the FIFO depths given to `csr_fifo`.

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

### Bus Bridges

The memory interface holds an access until `busy = 0`; the read data is combinational; the access (write, read side effect, FIFO push / pop) happens on the rising edge where `busy = 0`.

| Bridge | Timing | Notes |
|--------|--------|-------|
| `sbi2mem` | combinational | `ready = not busy`, `info.name = NAME`, or `DEFAULT_NAME` if `NAME` is empty (generated: `MODULE_NAME`, hjson `name`) |
| `pbi2mem` | combinational | `busy` |
| `apb2mem` | combinational | access in the access phase only (`psel and penable`), `pready = not busy`, `pslverr = 0`, `pstrb` / `pprot` (APB4) not used |
| `axi4lite2mem` | FSM, registered read data | AW and W accepted together (`awready = wready`), one access at a time, read / write round robin when both are requested, responses OKAY, `wstrb` not used; 1 cycle of handshake + memory access + response |

### Generator Notes (as coded)

- The generators serialize `run` and `write` with a lock file in the work directory (`.regtool.lock`, `.pbcc.lock`, `.rvcc.lock`).
- The regtool `Makefile` regenerates an output when it is older than the hjson or than the regtool sources (`REGTOOL_FILES`: `*.py` and `*.hjson` of `tools/regtool/`).
- `tools/regtool/regtool.py` writes `<name>_dump1.hjson`, `_dump2.hjson`, `_dump3.hjson` (raw, defaults filled, after checks) in the current directory (`csr_model.check_csr(csr, dump=False)` does not).
- `regtool.py` always writes the VHDL, C and Markdown outputs (default names if not set), the Verilog / SystemVerilog outputs only if `--verilog_module` / `--verilog_header` / `--sv_module` / `--sv_package` are set.
- SystemVerilog: an element of the struct input port `hw2sw_i` is read with a size cast (`8'(hw2sw_i.<reg>.<field>)`): iverilog 12 gets the width of a struct member wrong in a concatenation or a port connection.
- `pbcc_gen` builds the ROM package with `gen_rom.py ... --data-width 18` (PicoBlaze 18-bit instructions, default 10-bit address); the ROM entity itself comes from picoasm.
- `rvcc_gen` calls `gen_rom.py` with its defaults (32-bit data, 10-bit address = 1024 words = 4 KB), while `link.ld` declares a 32 KB ROM. A program between 4 KB and 32 KB links, then `gen_rom.py` rejects the hex file and exits with status 1, which stops the generator `make`. Which size is intended (a 4 KB `link.ld`, or an `--addr-width` parameter for the ROM) is not decided by the code, so both are left unchanged.
- `gen_rom.py` exits with status 1 on any error (hex file larger than the ROM, unreadable hex or template file).
- `build_toolchain.sh` currently builds `tools/pbccv2-src-20111024/sdcc3` (the `pbccv2-src-20110901` and `sdcc-3.1.0` lines are commented out).

## Directory Structure

```
asylum-utils-generators/
├── generators.core              # FuseSoC core (asylum:utils:generators), generators: section
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
    ├── regtool/                 # regtool.py, csr_model.py, gen_hdl.py, hdl_model.py, gen_*.py, addrmap.py, schema,
    │                            # hdl/ (VHDL + Verilog), examples/, sim/ (testbenches), tests/ (pytest)
    ├── picoasm/                 # PicoBlaze assembler sources + ROM templates
    ├── pbccv2-src-20110901/     # SDCC sources (PicoBlaze port)
    ├── pbccv2-src-20111024/     # SDCC sources (PicoBlaze port, used by build_toolchain.sh)
    └── sdcc-3.1.0/              # SDCC 3.1.0 sources
```

## Dependencies

| Core | Used by (fileset) | Purpose |
|------|-------------------|---------|
| `asylum:component:fifo` | `deps` | `fifo_sync` / `fifo_pkg` used by `csr_fifo` |
| `asylum:utils:pkg` | `files_regtool_sim` | `sbi_pkg` / `pbi_pkg` of the testbenches (and of `sbi2mem` / `pbi2mem` in the calling cores) |

Python modules: `fusesoc`, `jinja2`, `hjson` (generators), `hjson`, `jsonschema`, `prettytable` (regtool), `pytest`, `pytest-xdist` (tests). Optional test tools: GHDL, iverilog, verilator. External tools: GNU make, sdcc / picoasm (`PBCC_HOME`, `PICOASM_HOME`), RISC-V GCC binutils (`RISCV_PREFIX`), `hexdump`.
