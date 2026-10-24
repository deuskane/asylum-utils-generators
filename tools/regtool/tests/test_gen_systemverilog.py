"""
Unit tests of the generic SystemVerilog writer (gen_systemverilog.py) :
hdl_model -> SystemVerilog, without CSR. The module DEMO (a counter with a
struct port, a package, a generate and an instance) is linted with
verilator and simulated with iverilog when they are in the PATH.
"""

import subprocess

import pytest

from conftest import tool
from hdl_model import *
from gen_systemverilog import SystemVerilogWriter, sv_expr, sv_package, sv_module

#============================================
# Types and expressions
#============================================

#--------------------------------------------
@pytest.mark.parametrize("t, text", [
    (Bit()                          , "logic "),
    (Vector(8)                      , "logic [7:0] "),
    (Vector(Ref("W"))               , "logic [W-1:0] "),
    (Integer()                      , "int "),
    (Boolean()                      , "bit "),
    (String()                       , "string "),
    (RecordType("rec_t", [])        , "rec_t "),
])
def test_type(t, text):
    assert SystemVerilogWriter().type(t, "test") == text

#--------------------------------------------
def test_external_type():
    """A VHDL type : no port / signal, untyped parameter"""
    w = SystemVerilogWriter()
    with pytest.raises(ValueError):
        w.port_type(ExternalType("sbi_ini_t"))
    assert w.param_type(ExternalType("my_t")) == ""

#--------------------------------------------
REC  = RecordType("rec_t", [RecordField("x", Bit()), RecordField("sub", RecordType("sub_t", [RecordField("y", Vector(2))]))])

#--------------------------------------------
def test_record_element():
    """Element of a record : <name>.<field> ; read from an input port : size cast"""
    w = SystemVerilogWriter({"r_o": Port("r_o", "out", REC), "r_i": Port("r_i", "in", REC)})
    assert w.expr(Ref("r_o", ("sub", "y")))                       == "r_o.sub.y"
    assert w.expr(Ref("r_i", ("x",)))                             == "1'(r_i.x)"
    assert w.expr(Concat([Ref("r_i", ("sub", "y")), Ref("a")]))   == "{2'(r_i.sub.y), a}"
    assert w.expr(Slice(Ref("r_i", ("sub", "y")), 1, 1))          == "r_i.sub.y[1:1]"
    assert w.expr(Ref("s", ("x",)))                               == "s.x"

#--------------------------------------------
@pytest.mark.parametrize("e, text", [
    (VecConst(26, 5)                        , "5'h1A"),
    (Fill(0, Ref("W"))                      , "{W{1'b0}}"),
    (Eq(Ref("a"), BitConst(1))              , "a == 1'b1"),
    (Truth(Ref("EN"))                       , "(EN) != 0"),
])
def test_expr(e, text):
    """Same as Verilog"""
    assert sv_expr(e) == text

#============================================
# Declarations
#============================================

#--------------------------------------------
def test_decls():
    lines = SystemVerilogWriter().decls([Signal("a", Bit()), Signal("bcd", Vector(2), "comment"), "",
                                         Constant("C", Integer(), IntConst(4)), Constant("D", Vector(4), VecConst(4, 4)),
                                         "", Signal("r", REC)], "  ")
    assert lines == ["  logic            a;",
                     "  logic      [1:0] bcd; // comment",
                     "",
                     "  localparam int         C = 4;",
                     "  localparam logic [3:0] D = 4'h4;",
                     "",
                     "  rec_t      r;"]

#--------------------------------------------
def test_struct():
    lines = SystemVerilogWriter().decls([RecordType("pair_t", [RecordField("a", Bit(), "A"), RecordField("bb", Vector(4))], "Pair")], "")
    assert lines == ["// Pair",
                     "typedef struct packed {",
                     "  logic       a;  // A",
                     "  logic [3:0] bb;",
                     "} pair_t;",
                     ""]

#============================================
# Units
#============================================

#--------------------------------------------
REC_DEMO = RecordType("demo_t", [RecordField("count", Vector(Ref("DEMO_W"))), RecordField("max", Bit(), "Count = max")])
PKG      = Package("demo_pkg", "work", [Comment(["Constants"]), Constant("DEMO_W", Integer(), IntConst(4)), "",
                                        REC_DEMO, Component(Module("x")), Use("lib", "other_pkg")])

DEMO     = Module("demo",
                  generics = [Generic("EN", Boolean(), comment="Enable")],
                  ports    = [Comment(["Clock"]), Port("clk_i", "in", Bit()), Port("arst_b_i", "in", Bit()),
                              Port("demo_o", "out", REC_DEMO)],
                  decls    = [Signal("q", Vector(Ref("DEMO_W"), "unsigned"))],
                  stmts    = [IfGenerate("gen_count", Truth(Ref("EN")), [], [
                                 Instance("demo_cnt", "ins_cnt", [("W", Ref("DEMO_W"))],
                                          [("clk_i", Ref("clk_i")), ("arst_b_i", Ref("arst_b_i")), ("q_o", Ref("q")), ("unused_o", None)])],
                                 [], [Assign(Ref("q"), Fill(0, Ref("DEMO_W")))]),
                              Assign(Ref("demo_o", ("count",)), Cast(Ref("q"), "slv")),
                              CondAssign(Ref("demo_o", ("max",)), [(Eq(Ref("q"), Fill(1, Ref("DEMO_W"))), BitConst(1))], BitConst(0))],
                  imports  = [PKG, Use("lib", "other_pkg")],
                  header   = ["Demo"])

#--------------------------------------------
def test_package():
    text = sv_package(PKG, "demo_pkg.sv")
    assert "// verilator lint_off UNUSEDPARAM\npackage demo_pkg;\n" in text
    assert "  localparam int DEMO_W = 4;\n" in text
    assert "  typedef struct packed {\n    logic [DEMO_W-1:0] count;\n    logic              max;   // Count = max\n  } demo_t;\n" in text
    assert text.rstrip().endswith("endpackage : demo_pkg\n// verilator lint_on UNUSEDPARAM".rstrip())
    assert "DECLFILENAME" not in text
    assert "DECLFILENAME" in sv_package(PKG, "other.sv")
    assert "other_pkg" not in text and "component" not in text           # VHDL only

#--------------------------------------------
def test_module():
    text = sv_module(DEMO, "demo.sv")
    assert text.startswith("// Demo\n")
    assert "module demo\n  import demo_pkg::*;\n  #(parameter EN = 0 // Enable\n   )\n" in text
    assert "   ,output demo_t demo_o\n" in text
    assert "  assign demo_o.count = q;\n" in text
    assert "other_pkg" not in text
    assert "localparam" not in text                                       # imported, not copied

#--------------------------------------------
DEMO_CNT = """
module demo_cnt #(parameter W = 1) (input wire clk_i, input wire arst_b_i, output reg [W-1:0] q_o, output wire unused_o);
  always @(posedge clk_i or negedge arst_b_i)
    if (!arst_b_i) q_o <= {W{1'b0}}; else q_o <= q_o + 1'b1;
  assign unused_o = 1'b0;
endmodule
"""

DEMO_TB = """
`timescale 1ns/1ps
module tb;
  import demo_pkg::*;
  logic  clk = 0, arst_b = 0;
  demo_t d;
  always #5 clk = ~clk;
  initial #12 arst_b = 1;
  demo #(.EN(1)) dut (.clk_i(clk), .arst_b_i(arst_b), .demo_o(d));
  initial begin
    wait (d.max);
    if (d.count !== 4'hF) $display("ERROR");
    else                  $display("OK %0t", $time);
    $finish;
  end
endmodule
"""

#--------------------------------------------
def write_demo(tmp_path):
    (tmp_path / "demo_pkg.sv").write_text(sv_package(PKG, "demo_pkg.sv"))
    (tmp_path / "demo.sv").write_text(sv_module(DEMO, "demo.sv"))
    (tmp_path / "demo_cnt.v").write_text(DEMO_CNT)
    (tmp_path / "tb.sv").write_text(DEMO_TB)

#--------------------------------------------
def test_verilator(tmp_path):
    verilator = tool("verilator")
    write_demo(tmp_path)
    for enable in ["0", "1"]:
        result = subprocess.run([verilator, "--lint-only", "-Wall", "-Wno-UNUSEDSIGNAL", "-Wno-DECLFILENAME",
                                 "--top-module", "demo", f"-GEN={enable}", "demo_pkg.sv", "demo_cnt.v", "demo.sv"],
                                cwd=tmp_path, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr

#--------------------------------------------
def test_iverilog(tmp_path):
    """The counter of DEMO reaches its maximum value"""
    iverilog = tool("iverilog")
    vvp      = tool("vvp")
    write_demo(tmp_path)
    build = subprocess.run([iverilog, "-g2012", "-o", "tb.vvp", "demo_pkg.sv", "demo_cnt.v", "demo.sv", "tb.sv"],
                           cwd=tmp_path, capture_output=True, text=True)
    assert build.returncode == 0, build.stdout + build.stderr
    run   = subprocess.run([vvp, "-n", "tb.vvp"], cwd=tmp_path, capture_output=True, text=True)
    assert "OK" in run.stdout and "ERROR" not in run.stdout, run.stdout
