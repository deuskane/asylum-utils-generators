"""
Unit tests of the C header generator (gen_c.py)
"""

import re

from conftest import field, reg, desc
from gen_c import generate_c_header

#--------------------------------------------
def struct_members(text):
    """Members of the typedef struct, in order"""
    body = text[text.index("typedef struct {"):text.index("} test_t;")]
    return re.findall(r"uint\d+_t (\w+);", body)

#--------------------------------------------
def test_guard_and_include(make_csr, generate):
    text = generate(generate_c_header, make_csr(desc([reg()])))
    assert text.startswith("#ifndef TEST_REGISTERS_H\n#define TEST_REGISTERS_H\n")
    assert "#include <stdint.h>" in text
    assert text.rstrip().endswith("#endif // TEST_REGISTERS_H")

#--------------------------------------------
def test_defines(make_csr, generate):
    csr  = make_csr(desc([reg("ctrl", address="x8", fields=[field("en", "0"), field("div", "15:8")])]))
    text = generate(generate_c_header, csr)

    assert "#define TEST_CTRL 0x8\n"              in text
    assert "#define TEST_CTRL_EN      0\n"        in text
    assert "#define TEST_CTRL_EN_MASK 1\n"        in text
    assert "#define TEST_CTRL_DIV      8\n"       in text
    assert "#define TEST_CTRL_DIV_MASK 255\n"     in text

#--------------------------------------------
def test_enum(make_csr, generate):
    enum = [{"name": "idle", "value": "0"}, {"name": "run", "value": "x2"}]
    csr  = make_csr(desc([reg("cmd", fields=[field("op", "5:4", enum=enum)])]))
    text = generate(generate_c_header, csr)

    assert "#define TEST_CMD_OP_RUN     0x2\n"     in text
    assert "#define TEST_CMD_OP_RUN_RAW (0x2<<4)\n" in text

#--------------------------------------------
def test_struct_padding(make_csr, generate):
    """One member per address, padding between registers"""
    csr  = make_csr(desc([reg("r0", address="0"), reg("r1", address="xC")]))
    assert struct_members(generate(generate_c_header, csr)) == \
        ["r0", "__dummy_0x4__", "__dummy_0x8__", "r1"]

#--------------------------------------------
def test_struct_width(make_csr, generate):
    csr  = make_csr(desc([reg("r0"), reg("r1")], width=8))
    text = generate(generate_c_header, csr)
    assert "  uint8_t r0; // 0x0\n" in text
    assert "  uint8_t r1; // 0x1\n" in text

#--------------------------------------------
def test_struct_shared_address(make_csr, generate):
    """Registers sharing an address : one member <reg1>_<reg2>"""
    csr  = make_csr(desc([reg("cmd", address="0", swaccess="wo"),
                          reg("status", address="0", swaccess="ro"),
                          reg("data")]))
    assert struct_members(generate(generate_c_header, csr)) == ["cmd_status", "data"]
