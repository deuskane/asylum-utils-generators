.section .text
.global _start
_start:
    # Initialize stack pointer
    la sp, _estack

    # Call main
    call main

    # Loop indefinitely if main returns
_exit:
    j _exit
