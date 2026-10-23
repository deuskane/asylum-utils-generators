OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  ROM (rx)      : ORIGIN = 0x00000000, LENGTH = 32K
  RAM_GLB (rw)  : ORIGIN = 0x80000040, LENGTH = 64
  RAM_LOC (rw)  : ORIGIN = 0x80000080, LENGTH = 128
}

SECTIONS
{
  /* Executable code */
  .text :
  {
    *(.text.init)
    *(.text)
    *(.text.*)
    . = ALIGN(4);
    _etext = .;
  } > ROM

  /* Read Only Data (constant) */
  .rodata :
  {
    . = ALIGN(4);
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
    . = ALIGN(4);
    _erodata = .;
    ASSERT(SIZEOF(.rodata) == 0 , "Error: .rodata section is not empty");
  } > ROM

  /* Initialized data */
  .data :
  {
    . = ALIGN(4);
    *(.data)
    *(.data.*)
    *(.sdata)
    *(.sdata.*)
    . = ALIGN(4);
    _edata = .;
    
    ASSERT(SIZEOF(.data) == 0 , "Error: .data section is not empty");
    
  } > RAM_LOC

  /* Uninitialized data (zeroed at startup) */
  .bss :
  {
    . = ALIGN(4);
    _bss_start = .;
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
    *(.scommon)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
    _bss_size = _ebss - _bss_start;
  } > RAM_LOC

  /* Stack area for function calls : from the top of RAM_LOC down to _ebss */
  /* (absolute expression: inside an output section, "." is section relative) */
  _estack = (ORIGIN(RAM_LOC) + LENGTH(RAM_LOC)) & ~0xF; /* Top of stack (used by start.S to initialize sp) */

  /* Reserve the stack size (given by --defsym=_stack_size=<bytes>) */
  _stack_size = DEFINED(_stack_size) ? _stack_size : 128;
  ASSERT(_estack - _ebss >= _stack_size, "Error: not enough space left in RAM_LOC for the stack")
}