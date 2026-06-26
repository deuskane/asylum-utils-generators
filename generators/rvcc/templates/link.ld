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
    . = ALIGN(4);
    _ebss = .;
    _bss_size = _ebss - _bss_start;
  } > RAM_LOC

  /* Stack area for function calls */
  .stack :
  {
    . = ORIGIN(RAM_LOC) + LENGTH(RAM_LOC);
    . = . & ~0xF;
    _estack = .; /* Top of stack (used by start.S to initialize sp) */
  } > RAM_LOC
}