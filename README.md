# generators

A collection of useful generators for asylum

## Tools

### sdcc
It's Small Device C Compiler [SDCC](https://sdcc.sourceforge.net/) targeted for PicoBlaze.

Original portage can be found in this [link](https://www.fit.vutbr.cz/~meduna/work/doku.php?id=projects:vlam:pbcc:pbcc)

### picoasm
Picoasm is an assembler for the Xilinx PicoBlaze-3 soft-core processor. The assembler has an command line interface and can export to VHDL and Verilog.

Original project can be found in this [link](https://marksix.home.xs4all.nl/picoasm.html)

### regtool
The register tool is used to construct register documentation, register RTL and header files.

The initial idead in base of the regtool of [OpenTitan](https://opentitan.org/book/util/reggen/index.html)

## Generators

### pbcc
Invoke sdcc and picoasm to compil C files and generate ROM for PicoBlaze

### regtool
Invoke regtool to read hjson and generate CSR (Configurations and Status Registers) and C header files.
