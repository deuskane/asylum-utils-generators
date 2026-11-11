"""
Unit tests of the value parsers of csr_model.py
"""

import pytest

from csr_model import parse_value, parse_init_value, parse_bits

#--------------------------------------------
@pytest.mark.parametrize("text, value", [
    ("0"      ,   0),
    ("42"     ,  42),
    ("d42"    ,  42),
    ("b101"   ,   5),
    ("o17"    ,  15),
    ("xFF"    , 255),
    ("xff"    , 255),
    ("x10"    ,  16),
    ("04"     ,   4),
])
def test_parse_value(text, value):
    assert parse_value(text) == value

#--------------------------------------------
@pytest.mark.parametrize("text", ["", "x", "b102", "0x10", "abc"])
def test_parse_value_invalid(text):
    with pytest.raises(ValueError):
        parse_value(text)

#--------------------------------------------
@pytest.mark.parametrize("value, width, text", [
    (0 , 1, "0"),
    (1 , 1, "1"),
    (5 , 4, "0101"),
    (255, 8, "11111111"),
])
def test_parse_init_value(value, width, text):
    assert parse_init_value(value, width) == text

#--------------------------------------------
@pytest.mark.parametrize("bits, msb, lsb", [
    ("0"   ,  0,  0),
    ("7"   ,  7,  7),
    ("7:0" ,  7,  0),
    ("15:8", 15,  8),
])
def test_parse_bits(bits, msb, lsb):
    assert parse_bits(bits) == (msb, lsb)
