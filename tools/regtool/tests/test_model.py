"""
Unit tests of the CSR model (csr_model.check_csr) : schema, default values,
checks and derived fields.
"""

import jsonschema
import pytest

from conftest import field, reg, desc

#============================================
# Schema and default values
#============================================

#--------------------------------------------
def test_defaults(make_csr):
    csr = make_csr(desc([reg("r0")]))

    assert csr['desc']      == ""
    assert csr['width']     == 32
    assert csr['interface'] == "mem"
    assert csr['parameters'] == []

    r = csr['registers'][0]
    assert r['desc']     == ""
    assert r['enable']   == "True"
    assert r['hwtype']   == "reg"
    assert r['hwaccess'] == "rw"
    assert r['swaccess'] == "rw"

    f = r['fields'][0]
    assert f['init']     == 0
    assert f['desc']     == ""

#--------------------------------------------
@pytest.mark.parametrize("description", [
    {"registers": [reg()]},                                    # no name
    {"name": "test"},                                          # no registers
    desc([reg()], unknown="x"),                                # unknown key
    desc([reg(unknown="x")]),                                  # unknown register key
    desc([reg(fields=[field(unknown="x")])]),                  # unknown field key
    desc([{"name": "r"}]),                                     # no fields
    desc([reg(fields=[{"name": "f"}])]),                       # no bits
    desc([reg(swaccess="rx")]),                                # invalid swaccess
    desc([reg(hwaccess="rx")]),                                # invalid hwaccess
    desc([reg(hwtype="ram")]),                                 # invalid hwtype
    desc([reg()], interface="axi"),                            # invalid interface
    desc([reg()], width="32"),                                 # width is an integer
])
def test_schema_error(make_csr, description):
    with pytest.raises(jsonschema.exceptions.ValidationError):
        make_csr(description)

#--------------------------------------------
@pytest.mark.parametrize("interface, result", [
    ("mem"     , "mem"     ),
    ("reg"     , "mem"     ),                                  # former name of mem
    ("pbi"     , "pbi"     ),
    ("sbi"     , "sbi"     ),
    ("apb"     , "apb"     ),
    ("axi4lite", "axi4lite"),
])
def test_interface(make_csr, interface, result):
    assert make_csr(desc([reg()], interface=interface))['interface'] == result

#============================================
# Width and addresses
#============================================

#--------------------------------------------
@pytest.mark.parametrize("width, offset", [(8, 1), (16, 2), (32, 4), (64, 8)])
def test_width(make_csr, width, offset):
    csr = make_csr(desc([reg()], width=width))
    assert csr['addr_offset'] == offset

#--------------------------------------------
@pytest.mark.parametrize("width", [0, 4, 12, 24, 48])
def test_width_error(make_csr, width):
    with pytest.raises(ValueError):
        make_csr(desc([reg()], width=width))

#--------------------------------------------
def test_default_address(make_csr):
    """Without address, a register follows the previous one"""
    csr = make_csr(desc([reg("r0"), reg("r1"), reg("r2", address="x10"), reg("r3")]))
    assert [r['address'] for r in csr['registers']] == [0, 4, 16, 20]

#--------------------------------------------
@pytest.mark.parametrize("addresses, size_addr", [
    (["0"]           , 0),
    (["0", "4"]      , 3),
    (["0", "x1C"]    , 5),
    (["0", "x20"]    , 6),
])
def test_size_addr(make_csr, addresses, size_addr):
    registers = [reg(f"r{i}", address=a) for i, a in enumerate(addresses)]
    csr = make_csr(desc(registers))
    assert csr['size_addr'] == size_addr

#--------------------------------------------
@pytest.mark.parametrize("width, address", [(32, "2"), (32, "x11"), (16, "1"), (64, "4")])
def test_address_alignment_error(make_csr, width, address):
    with pytest.raises(ValueError):
        make_csr(desc([reg(address=address)], width=width))

#--------------------------------------------
def test_register_name_unique(make_csr):
    with pytest.raises(ValueError):
        make_csr(desc([reg("r0"), reg("r0")]))

#============================================
# Shared address
#============================================

#--------------------------------------------
def test_shared_address_ro_wo(make_csr):
    """A write only register and a read only register can share an address"""
    csr = make_csr(desc([reg("cmd"   , address="0", swaccess="wo"),
                         reg("status", address="0", swaccess="ro")]))
    assert [r['address'] for r in csr['registers']] == [0, 0]

#--------------------------------------------
@pytest.mark.parametrize("sw0, sw1", [("rw", "ro"), ("ro", "ro"), ("rw", "wo"), ("wo", "wo"), ("rw", "rw")])
def test_shared_address_error(make_csr, sw0, sw1):
    """Two readable (or two writable) registers at the same address"""
    with pytest.raises(ValueError):
        make_csr(desc([reg("r0", address="0", swaccess=sw0),
                       reg("r1", address="0", swaccess=sw1)]))

#--------------------------------------------
def test_shared_address_alias_error(make_csr):
    """alias_write counts as a write at the address of the alias register"""
    with pytest.raises(ValueError):
        make_csr(desc([reg("r0", address="0", swaccess="rw"),
                       reg("r1", address="4", swaccess="wo"),
                       reg("r2", address="4", swaccess="ro", alias_write="r0")]))

#============================================
# Alias
#============================================

#--------------------------------------------
def test_alias_write(make_csr):
    csr = make_csr(desc([reg("r0"), reg("r1", alias_write="r0")]))
    r0, r1 = csr['registers']

    assert r0['address_write'] == ["r0", "r1"]
    assert r1['address_write'] == []
    assert r0['sw2hw_we'] is True
    assert r1['sw2hw_we'] is False

#--------------------------------------------
@pytest.mark.parametrize("alias", ["r0", "unknown"])
def test_alias_write_error(make_csr, alias):
    with pytest.raises(KeyError):
        make_csr(desc([reg("r0", alias_write=alias)]))

#============================================
# Access
#============================================

#--------------------------------------------
@pytest.mark.parametrize("swaccess, sw_re, sw_we", [
    ("rw"   , True , True ),
    ("ro"   , True , False),
    ("wo"   , False, True ),
    ("rw1c" , True , True ),
    ("rw0c" , True , True ),
    ("rw1s" , True , True ),
    ("rw0s" , True , True ),
    ("rsw1c", True , True ),
    ("rcw1s", True , True ),
    ("rsw0c", True , True ),
])
def test_swaccess(make_csr, swaccess, sw_re, sw_we):
    r = make_csr(desc([reg(swaccess=swaccess)]))['registers'][0]
    assert r['sw2hw_re'] is sw_re
    assert r['sw2hw_we'] is sw_we

#--------------------------------------------
@pytest.mark.parametrize("hwaccess, sw2hw_data, hw2sw_data", [
    ("rw"  , True , True ),
    ("ro"  , True , False),
    ("wo"  , False, True ),
    ("none", False, False),
])
def test_hwaccess(make_csr, hwaccess, sw2hw_data, hw2sw_data):
    r = make_csr(desc([reg(hwaccess=hwaccess)]))['registers'][0]
    assert r['sw2hw_data'] is sw2hw_data
    assert r['hw2sw_data'] is hw2sw_data
    assert r['hw2sw_we']   is hw2sw_data

#--------------------------------------------
@pytest.mark.parametrize("hwtype, hwaccess, hw2sw_re, name_re, name_we", [
    ("reg" , "rw", False, "re"   , "we"   ),
    ("ext" , "rw", False, "re"   , "we"   ),
    ("fifo", "rw", True , "ready", "valid"),
    ("fifo", "wo", False, "ready", "valid"),
])
def test_hwtype(make_csr, hwtype, hwaccess, hw2sw_re, name_re, name_we):
    r = make_csr(desc([reg(hwtype=hwtype, hwaccess=hwaccess)]))['registers'][0]
    assert r['hw2sw_re']      is hw2sw_re
    assert r['sw2hw_name_re'] == name_re
    assert r['sw2hw_name_we'] == name_we

#--------------------------------------------
def test_sw2hw_hw2sw(make_csr):
    """A ro register read by the hardware only has no hw2sw item"""
    r = make_csr(desc([reg(swaccess="ro", hwaccess="ro")]))['registers'][0]
    assert r['sw2hw'] is True
    assert r['hw2sw'] is False

    r = make_csr(desc([reg(swaccess="wo", hwaccess="none")]))['registers'][0]
    assert r['sw2hw'] is True
    assert r['hw2sw'] is False

#============================================
# Enable
#============================================

#--------------------------------------------
@pytest.mark.parametrize("enable", ["True", "False", "EN"])
def test_enable(make_csr, enable):
    make_csr(desc([reg(enable=enable)], parameters=[{"name": "EN", "type": "boolean"}]))

#--------------------------------------------
@pytest.mark.parametrize("enable", ["true", "DEPTH", "UNKNOWN"])
def test_enable_error(make_csr, enable):
    with pytest.raises(KeyError):
        make_csr(desc([reg(enable=enable)], parameters=[{"name": "DEPTH", "type": "natural"}]))

#============================================
# Fields
#============================================

#--------------------------------------------
def test_fields(make_csr):
    r = make_csr(desc([reg(fields=[field("a", "0"), field("b", "15:8", init="xA5")])]))['registers'][0]
    a, b = r['fields']

    assert (a['msb'], a['lsb'], a['width']) == ( 0, 0, 1)
    assert (b['msb'], b['lsb'], b['width']) == (15, 8, 8)
    assert b['init']  == 0xA5
    assert b['expr']  == '"10100101"'
    assert r['width'] == 9

#--------------------------------------------
def test_field_expr(make_csr):
    """expr replaces the init value"""
    f = make_csr(desc([reg(fields=[field(expr="RESET_VALUE")])]))['registers'][0]['fields'][0]
    assert f['expr'] == "RESET_VALUE"

#--------------------------------------------
@pytest.mark.parametrize("fields", [
    [field("a", "0:7")],                       # msb < lsb
    [field("a", "32")],                        # msb >= width
    [field("a", "39:32")],                     # msb >= width
    [field("a", "7:0"), field("b", "7")],      # overlap
    [field("a", "7:0"), field("b", "15:4")],   # overlap
])
def test_field_error(make_csr, fields):
    with pytest.raises((KeyError, ValueError)):
        make_csr(desc([reg(fields=fields)]))
