#ifndef EXAMPLE1_REGISTERS_H
#define EXAMPLE1_REGISTERS_H

#include <stdint.h>

// Module      : example1
// Description : The example 1
// Width       : 32

//==================================
// Register    : reg1
// Description : Register 1
// Address     : 0x0
//==================================
#define EXAMPLE1_REG1 0x0

// Field       : reg1.field1
// Description : Field 1
// Range       : [0]
#define EXAMPLE1_REG1_FIELD1      0
#define EXAMPLE1_REG1_FIELD1_MASK 1

// Field       : reg1.field2
// Description : Field 2
// Range       : [2]
#define EXAMPLE1_REG1_FIELD2      2
#define EXAMPLE1_REG1_FIELD2_MASK 1

//==================================
// Register    : reg2
// Description : Register 2
// Address     : 0x4
//==================================
#define EXAMPLE1_REG2 0x4

// Field       : reg2.field1
// Description : Field 1
// Range       : [7:0]
#define EXAMPLE1_REG2_FIELD1      0
#define EXAMPLE1_REG2_FIELD1_MASK 255

// Field       : reg2.field2
// Description : Field 2
// Range       : [15:8]
#define EXAMPLE1_REG2_FIELD2      8
#define EXAMPLE1_REG2_FIELD2_MASK 255

//==================================
// Register    : reg3
// Description : Register 3
// Address     : 0x8
//==================================
#define EXAMPLE1_REG3 0x8

// Field       : reg3.field1
// Description : Field 1
// Range       : [7:0]
#define EXAMPLE1_REG3_FIELD1      0
#define EXAMPLE1_REG3_FIELD1_MASK 255

// Field       : reg3.field2
// Description : Field 2
// Range       : [15:8]
#define EXAMPLE1_REG3_FIELD2      8
#define EXAMPLE1_REG3_FIELD2_MASK 255

//==================================
// Register    : fifo_sw2hw
// Description : Write Fifo
// Address     : 0x10
//==================================
#define EXAMPLE1_FIFO_SW2HW 0x10

// Field       : fifo_sw2hw.field1
// Description : Field 1
// Range       : [3:0]
#define EXAMPLE1_FIFO_SW2HW_FIELD1      0
#define EXAMPLE1_FIFO_SW2HW_FIELD1_MASK 15

// Field       : fifo_sw2hw.field2
// Description : Field 2
// Range       : [15:8]
#define EXAMPLE1_FIFO_SW2HW_FIELD2      8
#define EXAMPLE1_FIFO_SW2HW_FIELD2_MASK 255

//==================================
// Register    : fifo_hw2sw
// Description : Read Fifo
// Address     : 0x14
//==================================
#define EXAMPLE1_FIFO_HW2SW 0x14

// Field       : fifo_hw2sw.field1
// Description : Field 1
// Range       : [3:0]
#define EXAMPLE1_FIFO_HW2SW_FIELD1      0
#define EXAMPLE1_FIFO_HW2SW_FIELD1_MASK 15

// Field       : fifo_hw2sw.field2
// Description : Field 2
// Range       : [15:8]
#define EXAMPLE1_FIFO_HW2SW_FIELD2      8
#define EXAMPLE1_FIFO_HW2SW_FIELD2_MASK 255

//==================================
// Register    : fifo_bidir
// Description : Read/Write Fifo
// Address     : 0x18
//==================================
#define EXAMPLE1_FIFO_BIDIR 0x18

// Field       : fifo_bidir.field1
// Description : Field 1
// Range       : [3:0]
#define EXAMPLE1_FIFO_BIDIR_FIELD1      0
#define EXAMPLE1_FIFO_BIDIR_FIELD1_MASK 15

// Field       : fifo_bidir.field2
// Description : Field 2
// Range       : [15:8]
#define EXAMPLE1_FIFO_BIDIR_FIELD2      8
#define EXAMPLE1_FIFO_BIDIR_FIELD2_MASK 255

//----------------------------------
// Structure {module}_t
//----------------------------------
typedef struct {
  uint32_t reg1; // 0x0
  uint32_t reg2; // 0x4
  uint32_t reg3; // 0x8
  uint32_t __dummy_0xC__
  uint32_t fifo_sw2hw; // 0x10
  uint32_t fifo_hw2sw; // 0x14
  uint32_t fifo_bidir; // 0x18
} example1_t;

#endif // EXAMPLE1_REGISTERS_H
