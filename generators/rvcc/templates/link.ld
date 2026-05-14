OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
  RAM (rw)  : ORIGIN = 0x80000000, LENGTH = 128
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
    
  } > RAM

  /* Uninitialized data (zeroed at startup) */
  .bss :
  {
    . = ALIGN(4);
    *(.bss)
    *(.bss.*)
    . = ALIGN(4);
    _ebss = .;
  } > RAM

  /* Stack area for function calls */
  .stack :
  {
    . = ALIGN(16);
    _estack = .; /* Top of stack (used by start.S to initialize sp) */
  } > RAM
}