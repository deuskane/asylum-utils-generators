.section .text
.global _start
_start:
    # Clear the registers x1..x31 : a CPU restarted after a fault (lock-step /
    # TMR) must have the same register file as the other CPUs
    .irp reg, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    li x\reg, 0
    .endr

    # Initialize stack pointer
    la sp, _estack

//    # Initialize BSS section to zero
//    la t0, _bss_start
//    la t1, _bss_size
//    li t2, 0
//    blez t1, _bss_done
//_bss_loop:
//    sw t2, 0(t0)
//    addi t0, t0, 4
//    addi t1, t1, -4
//    bgtz t1, _bss_loop
//_bss_done:

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
