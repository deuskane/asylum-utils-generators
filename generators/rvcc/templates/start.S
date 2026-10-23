.section .text
.global _start
_start:
    # Initialize stack pointer
    la sp, _estack

    # Initialize BSS section to zero
    # (_bss_start and _ebss are 4-byte aligned by link.ld)
    la t0, _bss_start
    la t1, _ebss
    bgeu t0, t1, _bss_done
_bss_loop:
    sw zero, 0(t0)
    addi t0, t0, 4
    bltu t0, t1, _bss_loop
_bss_done:

//    # Initialize Data section (copy from ROM to RAM)
//    la t0, _etext
//    la t1, _sdata
//    la t2, _edata
//    bge t1, t2, _data_done
//_data_loop:
//    lw t3, 0(t0)
//    sw t3, 0(t1)
//    addi t0, t0, 4
//    addi t1, t1, 4
//    blt t1, t2, _data_loop
//_data_done:

    # Call main
    call main

    # Loop indefinitely if main returns
_exit:
    j _exit
