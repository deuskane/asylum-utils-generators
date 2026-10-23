"""
Unit tests of the VHDL generator (gen_vhdl.py) : text checks, then analysis
and elaboration with GHDL when ghdl is in the PATH (skipped otherwise).
"""

import os
import re
import subprocess

import pytest

from conftest import field, reg, desc, tool, HDL_DIR
from gen_vhdl import generate_vhdl_package, generate_vhdl_module

#--------------------------------------------
def ports(text):
    """Port names of the entity <name>_registers"""
    entity = text[text.index("entity test_registers is"):text.index("end entity test_registers;")]
    return re.findall(r"^\s*;?(\w+)\s*:\s*(?:in|out)\b", entity[entity.index("port ("):], re.M)

#============================================
# Package
#============================================

#--------------------------------------------
def test_package_constants(make_csr, generate):
    csr  = make_csr(desc([reg("r0"), reg("r1", address="x1C")]))
    text = generate(generate_vhdl_package, csr)

    assert "package test_csr_pkg is" in text
    assert "constant TEST_ADDR_WIDTH : natural := 5;"  in text
    assert "constant TEST_DATA_WIDTH : natural := 32;" in text
    assert "constant TEST_R1 : unsigned(TEST_ADDR_WIDTH-1 downto 0) := to_unsigned(28, TEST_ADDR_WIDTH);" in text

#--------------------------------------------
def test_package_records(make_csr, generate):
    csr  = make_csr(desc([reg("ctrl"  , swaccess="rw", hwaccess="ro"),
                          reg("status", swaccess="ro", hwaccess="wo")]))
    text = generate(generate_vhdl_package, csr)

    assert "type test_ctrl_sw2hw_t is record"   in text
    assert "type test_ctrl_hw2sw_t is record"   not in text
    assert "type test_status_hw2sw_t is record" in text
    assert "ctrl : test_ctrl_sw2hw_t;"          in text
    assert "status : test_status_hw2sw_t;"      in text

#--------------------------------------------
def test_package_no_hw2sw(make_csr, generate):
    """No hw2sw record (and no hw2sw_i port) if no register is written by the hardware"""
    csr  = make_csr(desc([reg(hwaccess="ro")]))
    assert "type test_hw2sw_t" not in generate(generate_vhdl_package, csr)
    assert "hw2sw_i"           not in ports(generate(generate_vhdl_module, csr))

#--------------------------------------------
def test_package_enum(make_csr, generate):
    enum = [{"name": "run", "value": "x2"}]
    csr  = make_csr(desc([reg("cmd", fields=[field("op", "5:4", enum=enum)])], width=8))
    text = generate(generate_vhdl_package, csr)

    assert 'constant TEST_CMD_OP_RUN     : std_logic_vector(2-1 downto 0) := "10";'     in text
    assert 'constant TEST_CMD_OP_RUN_RAW : std_logic_vector(8-1 downto 0) := "00100000";' in text

#--------------------------------------------
def test_package_component(make_csr, generate):
    text = generate(generate_vhdl_package, make_csr(desc([reg()])))
    assert "component test_registers is" in text

#============================================
# Module
#============================================

#--------------------------------------------
@pytest.mark.parametrize("interface, bus", [
    ("reg", ["cs_i", "re_i", "we_i", "addr_i", "wdata_i", "rdata_o", "busy_o"]),
    ("pbi", ["pbi_ini_i", "pbi_tgt_o"]),
    ("sbi", ["sbi_ini_i", "sbi_tgt_o"]),
])
def test_module_interface(make_csr, generate, interface, bus):
    csr  = make_csr(desc([reg()], interface=interface))
    assert ports(generate(generate_vhdl_module, csr)) == ["clk_i", "arst_b_i"] + bus + ["sw2hw_o", "hw2sw_i"]

#--------------------------------------------
def test_module_sbi_name(make_csr, generate):
    text = generate(generate_vhdl_module, make_csr(desc([reg()], interface="sbi")))
    assert 'sbi_tgt_o.info.name <= to_sbi_name("test");'   in text
    assert "sbi_tgt_o.info.name <= to_sbi_name(MODULE_NAME);" in text

#--------------------------------------------
def test_module_parameters(make_csr, generate):
    csr  = make_csr(desc([reg(enable="EN")], parameters=[{"name": "EN", "type": "boolean", "desc": "Enable"}]))
    text = generate(generate_vhdl_module, csr)
    assert "   ;EN : boolean -- Enable\n" in text
    assert "  gen_r: if (EN)\n"           in text
    assert "  gen_r_b: if not (EN)\n"     in text

#--------------------------------------------
@pytest.mark.parametrize("hwtype", ["reg", "ext", "fifo"])
def test_module_instance(make_csr, generate, hwtype):
    text = generate(generate_vhdl_module, make_csr(desc([reg(hwtype=hwtype)])))
    assert f"    ins_r : csr_{hwtype}\n" in text

#--------------------------------------------
def test_module_init(make_csr, generate):
    csr  = make_csr(desc([reg(swaccess="rw1c", fields=[field("a", "0", init="1"), field("b", "11:4", expr="X")])]))
    text = generate(generate_vhdl_module, csr)
    assert '    tmp(0 downto 0) := "1"; -- a\n' in text
    assert '    tmp(8 downto 1) := X; -- b\n'   in text
    assert '        ,MODEL         => "rw1c"\n' in text

#--------------------------------------------
def test_module_alias_write(make_csr, generate):
    text = generate(generate_vhdl_module, make_csr(desc([reg("r0"), reg("r1", alias_write="r0")])))
    assert re.search(r"r0_wcs\s+<= '1' when\s+\(sig_waddr = test_R0\)\s+or\s*\(sig_waddr = test_R1\)\s+else '0';", text)

#--------------------------------------------
def test_module_wbusy_single_driver(make_csr, generate):
    """A register without software write : <reg>_wbusy driven by the instance only"""
    text = generate(generate_vhdl_module, make_csr(desc([reg(swaccess="ro")])))
    assert len(re.findall(r"^\s*r_wbusy\s*<=", text, re.M)) == 1   # in the disabled branch only

#--------------------------------------------
def test_module_read_mux(make_csr, generate):
    text = generate(generate_vhdl_module, make_csr(desc([reg("r0"), reg("r1")])))
    assert "    r0_rdata when r0_rcs = '1' else\n" in text
    assert "    r1_rdata when r1_rcs = '1' else\n" in text
    assert "    (others => '0'); -- Bad Address, return 0\n" in text

#============================================
# GHDL
#============================================

#--------------------------------------------
GHDL_DESC = desc([
    reg("ctrl"  , swaccess="rw"   , hwaccess="ro", fields=[field("en", "0"), field("div", "15:8", init="x10")]),
    reg("status", swaccess="ro"   , hwaccess="wo", fields=[field("busy", "0")]),
    reg("irq"   , swaccess="rw1c" , hwaccess="rw", fields=[field("flags", "3:0")]),
    reg("cmd"   , swaccess="wo"   , hwaccess="ro", fields=[field("op", "1:0")], address="x10"),
    reg("data"  , swaccess="rw"   , hwaccess="rw", hwtype="ext"),
    reg("opt"   , swaccess="rw"   , hwaccess="ro", enable="OPT_ENABLE"),
], parameters=[{"name": "OPT_ENABLE", "type": "boolean"}])

#--------------------------------------------
def ghdl(*args, cwd):
    result = subprocess.run([tool("ghdl"), *args], cwd=cwd, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr

#--------------------------------------------
@pytest.mark.parametrize("enable", ["true", "false"])
def test_ghdl_elaborate(make_csr, tmp_path, enable):
    """The generated package and module of a 'reg' CSR (no FIFO) are analyzed and elaborated"""
    tool("ghdl")
    csr = make_csr(GHDL_DESC)
    generate_vhdl_package(csr, str(tmp_path / "test_csr_pkg.vhd"))
    generate_vhdl_module (csr, str(tmp_path / "test_csr.vhd"))

    options = ["--std=08", "--work=asylum", f"--workdir={tmp_path}"]
    files   = [os.path.join(HDL_DIR, f) for f in ["csr_pkg.vhd", "csr_reg.vhd", "csr_ext.vhd"]]
    files  += [str(tmp_path / "test_csr_pkg.vhd"), str(tmp_path / "test_csr.vhd")]

    # The generics of the top are set at run time (elaboration of the generate statements)
    ghdl("-a"        , *options, *files, cwd=tmp_path)
    ghdl("--elab-run", *options, "test_registers", f"-gOPT_ENABLE={enable}", "--stop-time=1ns", cwd=tmp_path)
