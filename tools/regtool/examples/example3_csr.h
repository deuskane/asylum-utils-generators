#ifndef EXAMPLE3_REGISTERS_H
#define EXAMPLE3_REGISTERS_H

#include <stdint.h>

// Module      : example3
// Description : test
// Width       : 32

//==================================
// Register    : regA
// Description : A
// Address     : 0x0
//==================================
#define EXAMPLE3_REGA 0x0

// Field       : regA.a
// Description : a
// Range       : [7:0]
#define EXAMPLE3_REGA_A      0
#define EXAMPLE3_REGA_A_MASK 255

// Field       : regA.b
// Description : b
// Range       : [15:8]
#define EXAMPLE3_REGA_B      8
#define EXAMPLE3_REGA_B_MASK 255

//----------------------------------
// Structure example3_t
//----------------------------------
typedef struct {
  uint32_t regA; // 0x0
} example3_t;

#endif // EXAMPLE3_REGISTERS_H
