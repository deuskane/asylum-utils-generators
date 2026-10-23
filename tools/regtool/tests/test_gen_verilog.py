"""
Unit tests of the Verilog generator (gen_verilog.py) : text checks, then lint
with verilator and compilation with iverilog when they are in the PATH
(skipped otherwise).
"""

import glob
import os
import re
import subprocess

import pytest

from conftest import field, reg, desc, tool, HDL_DIR
from gen_verilog import (generate_verilog_module, generate_verilog_header, check_verilog,
                         verilog_expr, verilog_param_range, verilog_init, verilog_bus_data)

#--------------------------------------------
def ports(text):
    """Port names of the module test_registers"""
    header = text[text.index("module test_registers"):text.index(");")]
    return re.findall(r"^\s*,?(?:input|output)\s+wire\s+(?:\[[^\]]*\]\s*)?(\w+)", header, re.M)

#============================================
# Helpers
#============================================

#--------------------------------------------
@pytest.mark.parametrize("interface", ["pbi", "sbi"])
def test_check_verilog(make_csr, interface):
    with pytest.raises(ValueError):
        check_verilog(make_csr(desc([reg()], interface=interface)))

#--------------------------------------------
@pytest.mark.parametrize("vhdl, verilog", [
    ("True"                        , "1"),
    ("false"                       , "0"),
    ('"0101"'                      , "4'b0101"),
    ("PARAM"                       , "PARAM"),
    ("PARAM(7 downto 0)"           , "PARAM[7:0]"),
    ("PARAM(15 downto 8)"          , "PARAM[15:8]"),
    ("DEPTH_TX"                    , "DEPTH_TX"),
    ("4"                           , "4"),
])
def test_verilog_expr(vhdl, verilog):
    assert verilog_expr(vhdl) == verilog

#--------------------------------------------
@pytest.mark.parametrize("vhdl, verilog", [
    ("boolean"                     , ""),
    ("natural"                     , ""),
    ("std_logic_vector(7 downto 0)", "[7:0] "),
])
def test_verilog_param_range(vhdl, verilog):
    assert verilog_param_range(vhdl) == verilog

#--------------------------------------------
def test_verilog_init(make_csr):
    """Fields packed from bit 0 in the order of the hjson, expr masked and shifted"""
    r = make_csr(desc([reg(fields=[field("a", "0", init="1"), field("b", "11:4", init="x5A"), field("c", "13:12", expr="P")])],
                      parameters=[{"name": "P", "type": "natural"}]))['registers'][0]
    assert verilog_init(r) == "11'hB5 | ((P & {2{1'b1}}) << 9)"

#--------------------------------------------
def test_verilog_bus_data(make_csr):
    """Each field at its bus position, 0 in the gaps"""
    csr = make_csr(desc([reg(fields=[field("a", "0"), field("b", "11:4"), field("c", "13:12")])], width=16))
    assert verilog_bus_data(csr, csr['registers'][0], "d") == "{2'b0, d[10:9], d[8:1], 3'b0, d[0:0]}"

#============================================
# Module
#============================================

#--------------------------------------------
BUS_PORTS = {
    "mem"      : ["cs_i", "re_i", "we_i", "addr_i", "wdata_i", "rdata_o", "busy_o"],
    "apb"      : ["s_apb_psel_i", "s_apb_penable_i", "s_apb_pwrite_i", "s_apb_paddr_i", "s_apb_pwdata_i",
                  "s_apb_prdata_o", "s_apb_pready_o", "s_apb_pslverr_o"],
    "axi4lite" : ["s_axi_awvalid_i", "s_axi_awready_o", "s_axi_awaddr_i",
                  "s_axi_wvalid_i", "s_axi_wready_o", "s_axi_wdata_i", "s_axi_wstrb_i",
                  "s_axi_bvalid_o", "s_axi_bready_i", "s_axi_bresp_o",
                  "s_axi_arvalid_i", "s_axi_arready_o", "s_axi_araddr_i",
                  "s_axi_rvalid_o", "s_axi_rready_i", "s_axi_rdata_o", "s_axi_rresp_o"],
}

#--------------------------------------------
@pytest.mark.parametrize("interface", BUS_PORTS.keys())
def test_module_interface(make_csr, generate, interface):
    text = generate(generate_verilog_module, make_csr(desc([reg(fields=[field("a", "0"), field("b", "11:4")])],
                                                           interface=interface)))
    assert ports(text) == ["clk_i", "arst_b_i"] + BUS_PORTS[interface] + \
        ["sw2hw_r_re_o", "sw2hw_r_we_o", "sw2hw_r_a_o", "sw2hw_r_b_o", "hw2sw_r_we_i", "hw2sw_r_a_i", "hw2sw_r_b_i"]
    assert ("2mem" in text) == (interface != "mem")

#--------------------------------------------
def test_module_fifo_ports(make_csr, generate):
    """Flattened records of a FIFO register (same items as the VHDL records)"""
    text = generate(generate_verilog_module, make_csr(desc([reg("q", hwtype="fifo")])))
    assert ports(text)[-10:] == ["sw2hw_q_ready_o", "sw2hw_q_valid_o", "sw2hw_q_f_o",
                                 "sw2hw_q_sw2hw_empty_o", "sw2hw_q_sw2hw_full_o",
                                 "sw2hw_q_hw2sw_empty_o", "sw2hw_q_hw2sw_full_o",
                                 "hw2sw_q_ready_i", "hw2sw_q_valid_i", "hw2sw_q_f_i"]

#--------------------------------------------
def test_module_parameters(make_csr, generate):
    csr  = make_csr(desc([reg(enable="EN")], parameters=[{"name": "EN", "type": "boolean", "desc": "Enable"},
                                                         {"name": "V" , "type": "std_logic_vector(7 downto 0)"}]))
    text = generate(generate_verilog_module, csr)
    assert "  #(parameter EN = 0 // Enable\n" in text
    assert "   ,parameter [7:0] V = 0 // \n"  in text
    assert "    if ((EN) != 0)\n"             in text

#--------------------------------------------
def test_module_alias_write(make_csr, generate):
    text = generate(generate_verilog_module, make_csr(desc([reg("r0"), reg("r1", alias_write="r0")])))
    assert "assign r0_wcs   = (sig_waddr == ADDR_R0) | (sig_waddr == ADDR_R1);" in text

#--------------------------------------------
def test_module_fifo_params(make_csr, generate):
    params = {"BLOCKING_READ": "True", "DEPTH_HW2SW": "DEPTH"}
    text   = generate(generate_verilog_module, make_csr(desc([reg("q", hwtype="fifo", params=params)],
                                                             parameters=[{"name": "DEPTH", "type": "natural"}])))
    assert ",.BLOCKING_READ  (1)"     in text
    assert ",.DEPTH_HW2SW    (DEPTH)" in text

#--------------------------------------------
def test_header(make_csr, generate):
    enum = [{"name": "run", "value": "x2", "desc": "Run"}]
    csr  = make_csr(desc([reg("r0"), reg("cmd", address="x10", fields=[field("op", "5:4", enum=enum)])], width=8))
    text = generate(generate_verilog_header, csr)
    assert "`ifndef TEST_CSR_PKG_VH\n"           in text
    assert "`define TEST_ADDR_WIDTH 5\n"         in text
    assert "`define TEST_DATA_WIDTH 8\n"         in text
    assert "`define TEST_CMD 5'h10\n"            in text
    assert "`define TEST_CMD_OP_RUN     2'h2\n"  in text
    assert "`define TEST_CMD_OP_RUN_RAW 8'h20\n" in text

#============================================
# verilator and iverilog
#============================================

#--------------------------------------------
TOOLS_DESC = desc([
    reg("ctrl"  , swaccess="rw"   , hwaccess="ro", fields=[field("en", "0"), field("div", "15:8", init="x10")]),
    reg("status", swaccess="ro"   , hwaccess="wo", fields=[field("busy", "0")]),
    reg("irq"   , swaccess="rw1c" , hwaccess="rw", fields=[field("flags", "3:0")]),
    reg("cmd"   , swaccess="wo"   , hwaccess="ro", fields=[field("op", "1:0")], address="x10"),
    reg("data"  , swaccess="rw"   , hwaccess="rw", hwtype="ext"),
    reg("rx"    , swaccess="ro"   , hwaccess="wo", hwtype="fifo", params={"BLOCKING_READ": "True", "DEPTH_HW2SW": "DEPTH"}),
    reg("tx"    , swaccess="wo"   , hwaccess="ro", hwtype="fifo", params={"DEPTH_SW2HW": "4"}),
    reg("opt"   , swaccess="rw"   , hwaccess="ro", enable="OPT_ENABLE", fields=[field("v", "7:0", expr="INIT")]),
], parameters=[{"name": "OPT_ENABLE", "type": "boolean"}, {"name": "DEPTH", "type": "natural"},
               {"name": "INIT", "type": "std_logic_vector(7 downto 0)"}])

#--------------------------------------------
def generate_files(make_csr, tmp_path, interface):
    csr = make_csr(dict(TOOLS_DESC, interface=interface))
    generate_verilog_module(csr, str(tmp_path / "test_csr.v"))
    generate_verilog_header(csr, str(tmp_path / "test_csr_pkg.vh"))
    return sorted(glob.glob(os.path.join(HDL_DIR, "*.v"))) + [str(tmp_path / "test_csr.v")]

#--------------------------------------------
def run(*args, cwd):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout + result.stderr

#--------------------------------------------
@pytest.mark.parametrize("interface", BUS_PORTS.keys())
@pytest.mark.parametrize("enable", ["1", "0"])
def test_verilator_lint(make_csr, tmp_path, interface, enable):
    """Lint clean (-Wall), except the unused signals of a disabled register"""
    verilator = tool("verilator")
    files     = generate_files(make_csr, tmp_path, interface)
    run(verilator, "--lint-only", "-Wall", "-Wno-UNUSEDSIGNAL", "--top-module", "test_registers",
        f"-GOPT_ENABLE={enable}", "-GDEPTH=2", "-GINIT=8'h5A", *files, cwd=tmp_path)

#--------------------------------------------
@pytest.mark.parametrize("interface", BUS_PORTS.keys())
def test_iverilog_compile(make_csr, tmp_path, interface):
    iverilog = tool("iverilog")
    files    = generate_files(make_csr, tmp_path, interface)
    run(iverilog, "-g2005", "-Wall", "-s", "test_registers", "-o", "test.vvp",
        "-Ptest_registers.OPT_ENABLE=1", "-Ptest_registers.DEPTH=2", *files, cwd=tmp_path)
