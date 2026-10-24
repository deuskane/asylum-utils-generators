"""
Unit tests of the HDL generator of the CSR (gen_hdl.py) : CSR model ->
package and module (hdl_model), written in VHDL, Verilog and SystemVerilog. Text checks,
then GHDL (analysis, elaboration), verilator (lint) and iverilog
(compilation) when they are in the PATH (skipped otherwise).
"""

import glob
import os
import re
import subprocess

import pytest

from conftest import field, reg, desc, tool, utils_pkg_dir, HDL_DIR
from gen_hdl  import (build_package, build_module, generate_hdl_package, generate_hdl_module,
                      parse_expr, parse_type)
from hdl_model import *
import gen_vhdl
import gen_verilog
import gen_systemverilog

#--------------------------------------------
def vhdl(csr):
    """VHDL texts (package, module) of the csr"""
    package = build_package(csr, "vhdl")
    return gen_vhdl.vhdl_package(package), gen_vhdl.vhdl_module(build_module(csr, package, "vhdl"))

#--------------------------------------------
def ports(text, kind="entity"):
    """Port names of the entity / component test_registers"""
    unit = text[text.index(f"{kind} test_registers is"):text.index(f"end {kind} test_registers;")]
    return re.findall(r"^\s*;?(\w+)\s*:\s*(?:in|out)\b", unit[unit.index("port ("):], re.M)

#============================================
# hjson expressions and types
#============================================

#--------------------------------------------
@pytest.mark.parametrize("text, expr", [
    ("True"                , BoolConst(True)),
    ("false"               , BoolConst(False)),
    ('"0101"'              , VecConst(5, 4)),
    ("4"                   , IntConst(4)),
    ("DEPTH_TX"            , Ref("DEPTH_TX")),
    ("P(7 downto 0)"       , Slice(Ref("P"), 7, 0)),
    ("P(N downto 0)"       , Slice(Ref("P"), Ref("N"), 0)),
    ("P + 1"               , Raw("P + 1")),
])
def test_parse_expr(text, expr):
    assert parse_expr(text) == expr

#--------------------------------------------
@pytest.mark.parametrize("text, type", [
    ("boolean"                     , Boolean()),
    ("natural"                     , Integer("natural")),
    ("positive"                    , Integer("positive")),
    ("std_logic"                   , Bit()),
    ("std_logic_vector(7 downto 0)", Vector(8)),
    ("my_type_t"                   , ExternalType("my_type_t")),
])
def test_parse_type(text, type):
    assert parse_type(text) == type

#============================================
# Package
#============================================

#--------------------------------------------
def test_package_constants(make_csr):
    pkg, _ = vhdl(make_csr(desc([reg("r0"), reg("r1", address="x1C")])))

    assert "package test_csr_pkg is" in pkg
    assert "constant TEST_ADDR_WIDTH : natural := 5;"  in pkg
    assert "constant TEST_DATA_WIDTH : natural := 32;" in pkg
    assert 'constant TEST_R1 : unsigned(TEST_ADDR_WIDTH-1 downto 0) := "11100";' in pkg

#--------------------------------------------
def test_package_records(make_csr):
    pkg, _ = vhdl(make_csr(desc([reg("ctrl"  , swaccess="rw", hwaccess="ro"),
                                 reg("status", swaccess="ro", hwaccess="wo")])))

    assert "type test_ctrl_sw2hw_t is record"   in pkg
    assert "type test_ctrl_hw2sw_t is record"   not in pkg
    assert "type test_status_hw2sw_t is record" in pkg
    assert re.search(r"ctrl\s+: test_ctrl_sw2hw_t;", pkg)
    assert re.search(r"status\s+: test_status_hw2sw_t;", pkg)

#--------------------------------------------
def test_package_record_items(make_csr):
    """Items of the records (same as the former generator : the IP use them)"""
    pkg, _ = vhdl(make_csr(desc([reg("q", hwtype="fifo", fields=[field("d", "0")])])))
    sw2hw  = pkg[pkg.index("type test_q_sw2hw_t is record"):pkg.index("end record test_q_sw2hw_t;")]
    hw2sw  = pkg[pkg.index("type test_q_hw2sw_t is record"):pkg.index("end record test_q_hw2sw_t;")]

    assert re.findall(r"^\s+(\w+)\s+:", sw2hw, re.M) == ["ready", "valid", "d", "sw2hw_empty", "sw2hw_full", "hw2sw_empty", "hw2sw_full"]
    assert re.findall(r"^\s+(\w+)\s+:", hw2sw, re.M) == ["ready", "valid", "d"]
    assert re.search(r"\bd\s+: std_logic_vector\(0 downto 0\);", sw2hw)          # 1-bit field : vector

#--------------------------------------------
def test_package_no_hw2sw(make_csr):
    """No hw2sw record (and no hw2sw_i port) if no register is written by the hardware"""
    pkg, mod = vhdl(make_csr(desc([reg(hwaccess="ro")])))
    assert "type test_hw2sw_t" not in pkg
    assert "hw2sw_i"           not in ports(mod)

#--------------------------------------------
def test_package_enum(make_csr):
    enum   = [{"name": "run", "value": "x2"}]
    pkg, _ = vhdl(make_csr(desc([reg("cmd", fields=[field("op", "5:4", enum=enum)])], width=8)))

    assert re.search(r'constant TEST_CMD_OP_RUN\s+: std_logic_vector\(1 downto 0\) := "10";', pkg)
    assert re.search(r'constant TEST_CMD_OP_RUN_RAW : std_logic_vector\(7 downto 0\) := "00100000";', pkg)

#--------------------------------------------
def test_package_component(make_csr):
    csr      = make_csr(desc([reg()], interface="sbi"))
    pkg, mod = vhdl(csr)
    assert ports(pkg, "component") == ports(mod)
    assert "use     asylum.sbi_pkg.ALL;" in pkg

#============================================
# Module
#============================================

BUS_PORTS = {
    "mem"      : ["cs_i", "re_i", "we_i", "addr_i", "wdata_i", "rdata_o", "busy_o"],
    "pbi"      : ["pbi_ini_i", "pbi_tgt_o"],
    "sbi"      : ["sbi_ini_i", "sbi_tgt_o"],
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
def test_module_interface(make_csr, interface):
    _, mod = vhdl(make_csr(desc([reg()], interface=interface)))
    assert ports(mod) == ["clk_i", "arst_b_i"] + BUS_PORTS[interface] + ["sw2hw_o", "hw2sw_i"]

#--------------------------------------------
@pytest.mark.parametrize("interface", ["pbi", "sbi", "apb", "axi4lite"])
def test_module_bridge(make_csr, interface):
    """The bus is connected to the memory interface through the bridge <interface>2mem"""
    _, mod = vhdl(make_csr(desc([reg()], interface=interface)))

    assert f"  ins_{interface}2mem : entity asylum.{interface}2mem\n" in mod
    for port in BUS_PORTS[interface]:
        assert re.search(rf"^      [(,]{port}\s+=> {port}$", mod, re.M), port
    for port, signal in [("cs_o", "mem_cs"), ("addr_o", "mem_addr"), ("rdata_i", "mem_rdata"), ("busy_i", "mem_busy")]:
        assert re.search(rf"^      ,{port}\s+=> {signal}$", mod, re.M), port
    assert bool(re.search(r"^      \(clk_i\s+=> clk_i$", mod, re.M)) == (interface == "axi4lite")

#--------------------------------------------
def test_module_no_bridge(make_csr):
    _, mod = vhdl(make_csr(desc([reg()], interface="mem")))
    assert "2mem" not in mod
    assert re.search(r"^  sig_wcs\s+<= cs_i;$"    , mod, re.M)
    assert re.search(r"^  busy_o\s+<= sig_busy;$" , mod, re.M)

#--------------------------------------------
@pytest.mark.parametrize("interface", BUS_PORTS.keys())
def test_module_name(make_csr, interface):
    """sbi : MODULE_NAME generic, the name of the CSR if empty (DEFAULT_NAME of sbi2mem)"""
    _, mod = vhdl(make_csr(desc([reg()], interface=interface)))
    assert ("MODULE_NAME : string := \"\"" in mod) == (interface == "sbi")
    if interface == "sbi":
        assert re.search(r',NAME\s+=> MODULE_NAME$'      , mod, re.M)
        assert re.search(r',DEFAULT_NAME\s+=> "test"$'   , mod, re.M)

#--------------------------------------------
def test_module_parameters(make_csr):
    _, mod = vhdl(make_csr(desc([reg(enable="EN")], parameters=[{"name": "EN", "type": "boolean", "desc": "Enable"}])))
    assert "    EN : boolean -- Enable\n"         in mod
    assert "  gen_r: if (EN) generate\n"          in mod
    assert "  gen_r_b: if not (EN) generate\n"    in mod

#--------------------------------------------
@pytest.mark.parametrize("hwtype", ["reg", "ext", "fifo"])
def test_module_instance(make_csr, hwtype):
    _, mod = vhdl(make_csr(desc([reg(hwtype=hwtype)])))
    assert f"    ins_r : csr_{hwtype}\n" in mod

#--------------------------------------------
def test_module_init(make_csr):
    """Reset value : one constant per field (init or expr), concatenated for csr_reg"""
    csr    = make_csr(desc([reg(swaccess="rw1c", fields=[field("a", "0", init="1"), field("b", "11:4", expr="X")])]))
    _, mod = vhdl(csr)
    assert re.search(r'constant INIT_r_a\s+: std_logic_vector\(0 downto 0\) := "1";', mod)
    assert re.search(r'constant INIT_r_b\s+: std_logic_vector\(7 downto 0\) := X;'  , mod)
    assert re.search(r'constant INIT_r\s+: std_logic_vector\(8 downto 0\) := INIT_r_b & INIT_r_a;', mod)
    assert re.search(r',MODEL\s+=> "rw1c"$', mod, re.M)

#--------------------------------------------
def test_module_alias_write(make_csr):
    _, mod = vhdl(make_csr(desc([reg("r0"), reg("r1", alias_write="r0")])))
    assert "r0_wcs <= '1' when (sig_waddr = TEST_R0) or (sig_waddr = TEST_R1) else" in mod

#--------------------------------------------
def test_module_wbusy_single_driver(make_csr):
    """A register without software write : <reg>_wbusy driven by the instance only"""
    _, mod = vhdl(make_csr(desc([reg(swaccess="ro")])))
    assert len(re.findall(r"^\s*r_wbusy\s*<=", mod, re.M)) == 1   # in the disabled branch only

#--------------------------------------------
def test_module_read_mux(make_csr):
    """Read data multiplexer : an unmapped address reads 0"""
    _, mod = vhdl(make_csr(desc([reg("r0"), reg("r1")])))
    assert "sig_rdata <= r0_rdata when r0_rcs = '1' else" in mod
    assert re.search(r"^\s+r1_rdata when r1_rcs = '1' else$", mod, re.M)
    assert re.search(r"^\s+\(others => '0'\);$", mod, re.M)

#--------------------------------------------
def test_module_disabled(make_csr):
    """Disabled register : hardware side at the reset value"""
    _, mod = vhdl(make_csr(desc([reg(enable="False", hwaccess="ro", fields=[field("a", "3:0", init="x5")])])))
    disabled = mod[mod.index("gen_r_b: if not (false) generate"):mod.index("end generate gen_r_b;")]
    assert re.search(r"sw2hw_o.r.a\s+<= INIT_r_a;", disabled)
    assert re.search(r"r_rdata\s+<= \(others => '0'\);", disabled)

#--------------------------------------------
def test_generate_files(make_csr, tmp_path):
    csr = make_csr(desc([reg()]))
    generate_hdl_package(csr, str(tmp_path / "p.vhd"), "vhdl")
    generate_hdl_module (csr, str(tmp_path / "m.vhd"), "vhdl")
    assert (tmp_path / "p.vhd").read_text() == vhdl(csr)[0]
    assert (tmp_path / "m.vhd").read_text() == vhdl(csr)[1]

#--------------------------------------------
def test_unknown_language(make_csr, tmp_path):
    with pytest.raises(ValueError):
        generate_hdl_module(make_csr(desc([reg()])), str(tmp_path / "m"), "systemc")

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
    reg("opt"   , swaccess="rw"   , hwaccess="ro", enable="OPT_ENABLE", fields=[field("v", "7:0", expr="INIT")]),
], parameters=[{"name": "OPT_ENABLE", "type": "boolean"}, {"name": "INIT", "type": "std_logic_vector(7 downto 0)"}])

#--------------------------------------------
def ghdl(*args, cwd):
    result = subprocess.run([tool("ghdl"), *args], cwd=cwd, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout + result.stderr

#--------------------------------------------
@pytest.mark.parametrize("interface", ["mem", "apb", "axi4lite", "pbi", "sbi"])
@pytest.mark.parametrize("enable", ["true", "false"])
def test_ghdl_elaborate(make_csr, tmp_path, enable, interface):
    """The generated package and module of a CSR (no FIFO) are analyzed (-Wall, no warning) and elaborated"""
    tool("ghdl")
    csr = make_csr(dict(GHDL_DESC, interface=interface))
    generate_hdl_package(csr, str(tmp_path / "test_csr_pkg.vhd"), "vhdl")
    generate_hdl_module (csr, str(tmp_path / "test_csr.vhd")    , "vhdl")

    options = ["--std=08", "--work=asylum", f"--workdir={tmp_path}"]
    files   = []
    if interface in ["pbi", "sbi"]:
        files += [os.path.join(utils_pkg_dir(), f) for f in ["types_pkg.vhd", f"{interface}_pkg.vhd"]]
    files  += [os.path.join(HDL_DIR, f) for f in ["csr_pkg.vhd", "csr_reg.vhd", "csr_ext.vhd"]]
    if interface != "mem":
        files += [os.path.join(HDL_DIR, f"{interface}2mem.vhd")]
    ghdl("-a", *options, *files, cwd=tmp_path)
    output = ghdl("-a", "-Wall", *options, str(tmp_path / "test_csr_pkg.vhd"), str(tmp_path / "test_csr.vhd"), cwd=tmp_path)
    assert "warning" not in output, output

    if interface in ["pbi", "sbi"]:
        return                                  # Unconstrained record ports : analysis only

    # The generics of the top are set at run time (elaboration of the generate statements)
    ghdl("--elab-run", *options, "test_registers", f"-gOPT_ENABLE={enable}", "-gINIT=01011010", "--stop-time=1ns", cwd=tmp_path)

#============================================
# Verilog
#============================================

#--------------------------------------------
def verilog(csr):
    """Verilog texts (header, module) of the csr"""
    package = build_package(csr, "verilog")
    return gen_verilog.verilog_header(package), gen_verilog.verilog_module(build_module(csr, package, "verilog"))

#--------------------------------------------
def vports(text):
    """Port names of the module test_registers"""
    header = text[text.index("module test_registers"):text.index("   );")]
    return re.findall(r"^\s*,?(?:input|output)\s+wire\s+(?:\[[^\]]*\]\s*)?(\w+)", header, re.M)

#--------------------------------------------
@pytest.mark.parametrize("interface", ["pbi", "sbi"])
def test_verilog_record_interface(make_csr, tmp_path, interface):
    """No Verilog for the buses defined by VHDL records"""
    with pytest.raises(ValueError):
        generate_hdl_module(make_csr(desc([reg()], interface=interface)), str(tmp_path / "m.v"), "verilog")

#--------------------------------------------
@pytest.mark.parametrize("interface", ["mem", "apb", "axi4lite"])
def test_verilog_interface(make_csr, interface):
    """sw2hw / hw2sw records flattened in sw2hw_<reg>_<item>_o / hw2sw_<reg>_<item>_i"""
    _, mod = verilog(make_csr(desc([reg(fields=[field("a", "0"), field("b", "11:4")])], interface=interface)))
    assert vports(mod) == ["clk_i", "arst_b_i"] + BUS_PORTS[interface] + \
        ["sw2hw_r_re_o", "sw2hw_r_we_o", "sw2hw_r_a_o", "sw2hw_r_b_o", "hw2sw_r_we_i", "hw2sw_r_a_i", "hw2sw_r_b_i"]
    assert ("2mem" in mod) == (interface != "mem")

#--------------------------------------------
def test_verilog_fifo_ports(make_csr):
    """Flattened records of a FIFO register (same items as the VHDL records)"""
    _, mod = verilog(make_csr(desc([reg("q", hwtype="fifo")])))
    assert vports(mod)[-10:] == ["sw2hw_q_ready_o", "sw2hw_q_valid_o", "sw2hw_q_f_o",
                                 "sw2hw_q_sw2hw_empty_o", "sw2hw_q_sw2hw_full_o",
                                 "sw2hw_q_hw2sw_empty_o", "sw2hw_q_hw2sw_full_o",
                                 "hw2sw_q_ready_i", "hw2sw_q_valid_i", "hw2sw_q_f_i"]

#--------------------------------------------
def test_verilog_parameters(make_csr):
    csr    = make_csr(desc([reg(enable="EN")], parameters=[{"name": "EN", "type": "boolean", "desc": "Enable"},
                                                           {"name": "V" , "type": "std_logic_vector(7 downto 0)"}]))
    _, mod = verilog(csr)
    assert "  #(parameter EN = 0 // Enable\n" in mod
    assert "   ,parameter [7:0] V = 0\n"      in mod
    assert "    if ((EN) != 0)\n"             in mod

#--------------------------------------------
def test_verilog_constants(make_csr):
    """Constants of the package used by the module copied as localparam"""
    enum   = [{"name": "run", "value": "x2"}]
    _, mod = verilog(make_csr(desc([reg("r0"), reg("cmd", address="x10", fields=[field("op", "5:4", enum=enum)])])))
    assert re.search(r"localparam\s+TEST_ADDR_WIDTH\s+= 5;", mod)
    assert re.search(r"localparam \[TEST_ADDR_WIDTH-1:0\] TEST_CMD\s+= 5'h10;", mod)
    assert "TEST_CMD_OP_RUN" not in mod                         # not used by the module

#--------------------------------------------
def test_verilog_alias_write(make_csr):
    _, mod = verilog(make_csr(desc([reg("r0"), reg("r1", alias_write="r0")])))
    assert "assign r0_wcs = ((sig_waddr == TEST_R0) || (sig_waddr == TEST_R1)) ? 1'b1 :" in mod

#--------------------------------------------
def test_verilog_fifo_params(make_csr):
    params = {"BLOCKING_READ": "True", "DEPTH_HW2SW": "DEPTH"}
    _, mod = verilog(make_csr(desc([reg("q", hwtype="fifo", params=params)],
                                   parameters=[{"name": "DEPTH", "type": "natural"}])))
    assert re.search(r",\.BLOCKING_READ\s+\(1\)$"   , mod, re.M)
    assert re.search(r",\.DEPTH_HW2SW\s+\(DEPTH\)$" , mod, re.M)

#--------------------------------------------
def test_verilog_header(make_csr):
    enum   = [{"name": "run", "value": "x2", "desc": "Run"}]
    hdr, _ = verilog(make_csr(desc([reg("r0"), reg("cmd", address="x10", fields=[field("op", "5:4", enum=enum)])], width=8)))
    assert "`ifndef TEST_CSR_PKG_VH\n"       in hdr
    assert "`define TEST_ADDR_WIDTH 5\n"     in hdr
    assert "`define TEST_DATA_WIDTH 8\n"     in hdr
    assert "`define TEST_CMD 5'h10\n"        in hdr
    assert "`define TEST_CMD_OP_RUN 2'h2\n"  in hdr
    assert "`define TEST_CMD_OP_RUN_RAW 8'h20\n" in hdr

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
def verilog_files(make_csr, tmp_path, interface):
    csr = make_csr(dict(TOOLS_DESC, interface=interface))
    generate_hdl_module (csr, str(tmp_path / "test_csr.v")     , "verilog")
    generate_hdl_package(csr, str(tmp_path / "test_csr_pkg.vh"), "verilog")
    return sorted(glob.glob(os.path.join(HDL_DIR, "*.v"))) + [str(tmp_path / "test_csr.v")]

#--------------------------------------------
def run(*args, cwd):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout + result.stderr

#--------------------------------------------
@pytest.mark.parametrize("interface", ["mem", "apb", "axi4lite"])
@pytest.mark.parametrize("enable", ["1", "0"])
def test_verilator_lint(make_csr, tmp_path, interface, enable):
    """Lint clean (-Wall), except the unused signals of a disabled register"""
    verilator = tool("verilator")
    files     = verilog_files(make_csr, tmp_path, interface)
    run(verilator, "--lint-only", "-Wall", "-Wno-UNUSEDSIGNAL", "--top-module", "test_registers",
        f"-GOPT_ENABLE={enable}", "-GDEPTH=2", "-GINIT=8'h5A", *files, cwd=tmp_path)

#--------------------------------------------
@pytest.mark.parametrize("interface", ["mem", "apb", "axi4lite"])
def test_iverilog_compile(make_csr, tmp_path, interface):
    iverilog = tool("iverilog")
    files    = verilog_files(make_csr, tmp_path, interface)
    run(iverilog, "-g2005", "-Wall", "-s", "test_registers", "-o", "test.vvp",
        "-Ptest_registers.OPT_ENABLE=1", "-Ptest_registers.DEPTH=2", *files, cwd=tmp_path)

#============================================
# SystemVerilog
#============================================

#--------------------------------------------
def systemverilog(csr):
    """SystemVerilog texts (package, module) of the csr"""
    package = build_package(csr, "systemverilog")
    return gen_systemverilog.sv_package(package), gen_systemverilog.sv_module(build_module(csr, package, "systemverilog"))

#--------------------------------------------
@pytest.mark.parametrize("interface", ["pbi", "sbi"])
def test_sv_record_interface(make_csr, tmp_path, interface):
    """No SystemVerilog for the buses defined by VHDL records"""
    with pytest.raises(ValueError):
        generate_hdl_module(make_csr(desc([reg()], interface=interface)), str(tmp_path / "m.sv"), "systemverilog")

#--------------------------------------------
@pytest.mark.parametrize("interface", ["mem", "apb", "axi4lite"])
def test_sv_interface(make_csr, interface):
    """Same bus ports as Verilog, hardware side : structs sw2hw_o / hw2sw_i"""
    _, mod = systemverilog(make_csr(desc([reg(fields=[field("a", "0"), field("b", "11:4")])], interface=interface)))
    assert vports(mod.replace("logic", "wire")) == ["clk_i", "arst_b_i"] + BUS_PORTS[interface]
    assert "   ,output test_sw2hw_t sw2hw_o" in mod
    assert "   ,input  test_hw2sw_t hw2sw_i" in mod
    assert "module test_registers\n  import test_csr_pkg::*;\n" in mod

#--------------------------------------------
def test_sv_package(make_csr):
    """Constants, structs with the items of the VHDL records"""
    enum   = [{"name": "run", "value": "x2"}]
    pkg, _ = systemverilog(make_csr(desc([reg("q", hwtype="fifo", fields=[field("d", "0")]),
                                          reg("cmd", address="x10", fields=[field("op", "5:4", enum=enum)])])))
    assert "package test_csr_pkg;" in pkg
    assert re.search(r"localparam int\s+TEST_ADDR_WIDTH = 5;", pkg)
    assert re.search(r"localparam logic \[TEST_ADDR_WIDTH-1:0\] TEST_CMD = 5'h10;", pkg)
    assert re.search(r"localparam logic \[1:0\]\s+TEST_CMD_OP_RUN\s+= 2'h2;", pkg)
    sw2hw = pkg[pkg.index("typedef struct packed"):pkg.index("} test_q_sw2hw_t;")]
    assert re.findall(r"^\s+logic\s*(?:\[[^\]]*\])?\s+(\w+);", sw2hw, re.M) == \
        ["ready", "valid", "d", "sw2hw_empty", "sw2hw_full", "hw2sw_empty", "hw2sw_full"]
    assert re.search(r"test_q_sw2hw_t\s+q;", pkg)
    assert "} test_sw2hw_t;" in pkg

#--------------------------------------------
def test_sv_struct_elements(make_csr):
    """sw2hw_o.<reg>.<item> written, hw2sw_i.<reg>.<item> read with a size cast"""
    _, mod = systemverilog(make_csr(desc([reg(fields=[field("a", "0"), field("b", "11:4")])])))
    assert re.search(r"assign sw2hw_o\.r\.b\s+= r_rdata_hw\[8:1\];", mod)
    assert re.search(r"assign r_wdata_hw\s+= \{8'\(hw2sw_i\.r\.b\), 1'\(hw2sw_i\.r\.a\)\};", mod)
    assert re.search(r",\.hw_we_i\s+\(1'\(hw2sw_i\.r\.we\)\)", mod)
    assert re.search(r",\.hw_sw_re_o\s+\(sw2hw_o\.r\.re\)", mod)

#--------------------------------------------
def sv_files(make_csr, tmp_path, interface):
    csr = make_csr(dict(TOOLS_DESC, interface=interface))
    generate_hdl_package(csr, str(tmp_path / "test_csr_pkg.sv"), "systemverilog")
    generate_hdl_module (csr, str(tmp_path / "test_csr.sv")    , "systemverilog")
    return sorted(glob.glob(os.path.join(HDL_DIR, "*.v"))) + [str(tmp_path / "test_csr_pkg.sv"), str(tmp_path / "test_csr.sv")]

#--------------------------------------------
@pytest.mark.parametrize("interface", ["mem", "apb", "axi4lite"])
@pytest.mark.parametrize("enable", ["1", "0"])
def test_sv_verilator_lint(make_csr, tmp_path, interface, enable):
    """Lint clean (-Wall), except the unused signals of a disabled register"""
    verilator = tool("verilator")
    files     = sv_files(make_csr, tmp_path, interface)
    run(verilator, "--lint-only", "-Wall", "-Wno-UNUSEDSIGNAL", "--top-module", "test_registers",
        f"-GOPT_ENABLE={enable}", "-GDEPTH=2", "-GINIT=8'h5A", *files, cwd=tmp_path)

#--------------------------------------------
@pytest.mark.parametrize("interface", ["mem", "apb", "axi4lite"])
def test_sv_iverilog_compile(make_csr, tmp_path, interface):
    """Compilation without warning (iverilog 12, -g2012)"""
    iverilog = tool("iverilog")
    files    = sv_files(make_csr, tmp_path, interface)
    output   = run(iverilog, "-g2012", "-Wall", "-s", "test_registers", "-o", "test.vvp",
                   "-Ptest_registers.OPT_ENABLE=1", "-Ptest_registers.DEPTH=2", *files, cwd=tmp_path)
    assert "warning" not in output, output
