"""
Unit tests of the generic Verilog writer (gen_verilog.py) : hdl_model ->
Verilog, without CSR. The module DEMO (a counter with a record port, a
generate and an instance) is linted with verilator and simulated with
iverilog when they are in the PATH.
"""

import subprocess

import pytest

from conftest import tool
from hdl_model import *
from gen_verilog import (verilog_range, verilog_expr, verilog_decls, verilog_stmts, verilog_header,
                         verilog_module, flat_ports, imported_constants)

#============================================
# Types and expressions
#============================================

#--------------------------------------------
@pytest.mark.parametrize("t, text", [
    (Bit()                          , ""),
    (Vector(8)                      , "[7:0] "),
    (Vector(1)                      , "[0:0] "),
    (Vector(Ref("W"))               , "[W-1:0] "),
    (Vector(4, "unsigned")          , "[3:0] "),
    (Integer()                      , ""),
    (Boolean()                      , ""),
])
def test_range(t, text):
    assert verilog_range(t) == text

#--------------------------------------------
@pytest.mark.parametrize("e, text", [
    (Ref("a")                               , "a"),
    (BitConst(1)                            , "1'b1"),
    (VecConst(26, 5)                        , "5'h1A"),
    (IntConst(3)                            , "3"),
    (BoolConst(False)                       , "0"),
    (StrConst("rw")                         , '"rw"'),
    (Fill(0, 8)                             , "{8{1'b0}}"),
    (Fill(1, Ref("W"))                      , "{W{1'b1}}"),
    (Slice(Ref("a"), 7, 4)                  , "a[7:4]"),
    (Index(Ref("a"), 2)                     , "a[2]"),
    (Concat([Fill(0, 3), Ref("a"), BitConst(1)]), "{{3{1'b0}}, a, 1'b1}"),
    (Not(Ref("a"))                          , "~a"),
    (And([Ref("a"), Not(Ref("b"))])         , "a & (~b)"),
    (Or([Ref("a"), Ref("b")])               , "a | b"),
    (Eq(Ref("a"), BitConst(1))              , "a == 1'b1"),
    (BoolOr([Eq(Ref("a"), Ref("b")), Eq(Ref("c"), Ref("d"))]), "(a == b) || (c == d)"),
    (Truth(Ref("EN"))                       , "(EN) != 0"),
    (Truth(BoolConst(True))                 , "1"),
    (Cast(Ref("a"), "unsigned")             , "a"),
    (Arith("/", Ref("W"), IntConst(8))      , "W/8"),
    (Raw("f(x)")                            , "f(x)"),
])
def test_expr(e, text):
    assert verilog_expr(e) == text

#--------------------------------------------
REC  = RecordType("rec_t", [RecordField("x", Bit()), RecordField("sub", RecordType("sub_t", [RecordField("y", Vector(2))]))])
PORT = Port("r_o", "out", REC, prefix="r", suffix="_o")

#--------------------------------------------
def test_record_element():
    """A record element is the flattened port"""
    ctx = {"r_o": PORT}
    assert verilog_expr(Ref("r_o", ("x",)), ctx)              == "r_x_o"
    assert verilog_expr(Ref("r_o", ("sub", "y")), ctx)        == "r_sub_y_o"
    assert verilog_expr(Slice(Ref("r_o", ("sub", "y")), 1, 1), ctx) == "r_sub_y_o[1:1]"

#--------------------------------------------
@pytest.mark.parametrize("e", [Ref("s", ("x",)), Slice(Concat([Ref("a")]), 1, 0)])
def test_unsupported_expr(e):
    """Element of a record signal (not a port), slice of an expression"""
    with pytest.raises(ValueError):
        verilog_expr(e, {})

#--------------------------------------------
def test_flat_ports():
    ports = flat_ports(Module("m", ports=[Comment(["c"]), Port("a_i", "in", Bit()), PORT]))
    assert [p.name if isinstance(p, Port) else "#" for p in ports] == ["#", "a_i", "r_x_o", "r_sub_y_o"]
    assert ports[-1].type == Vector(2) and ports[-1].direction == "out"

#--------------------------------------------
def test_external_port():
    with pytest.raises(ValueError):
        flat_ports(Module("m", ports=[Port("s_i", "in", ExternalType("sbi_ini_t"))]))

#============================================
# Declarations and statements
#============================================

#--------------------------------------------
def test_decls_aligned():
    lines = verilog_decls([Signal("a", Bit()), Signal("bcd", Vector(2), "comment"), "",
                           Constant("C", Vector(4), VecConst(4, 4)), Signal("u", Bit(), unused_ok=True)], "  ", {})
    assert lines == ["  wire             a;",
                     "  wire       [1:0] bcd; // comment",
                     "",
                     "  localparam [3:0] C = 4'h4;",
                     "  // verilator lint_off UNUSEDSIGNAL",
                     "  wire             u;",
                     "  // verilator lint_on UNUSEDSIGNAL"]

#--------------------------------------------
def test_cond_assign():
    s = CondAssign(Ref("y"), [(Eq(Ref("s"), BitConst(1)), Ref("a")), (Eq(Ref("t"), BitConst(1)), Ref("b"))], Fill(0, 4))
    assert verilog_stmts([s], "", {}) == ["assign y = (s == 1'b1) ? a :",
                                          "           (t == 1'b1) ? b :",
                                          "           {4{1'b0}};"]

#--------------------------------------------
def test_instance():
    s = Instance("cell", "ins_cell", [("W", IntConst(4)), ("M", StrConst("rw"))],
                 [("a_i", Ref("a")), ("y_o", None)], library="lib")
    assert verilog_stmts([s], "", {}) == ["cell",
                                          "  #(.W (4)",
                                          "   ,.M (\"rw\")",
                                          "   )",
                                          "ins_cell",
                                          "  (.a_i (a)",
                                          "  ,.y_o ()",
                                          "  );"]

#--------------------------------------------
def test_generate():
    """generate keyword only at the top level, local declarations, else block <name>_b"""
    inner = IfGenerate("gen_in", Truth(Ref("B")), [], [Assign(Ref("u"), Ref("v"))])
    s     = IfGenerate("gen_x", Truth(Ref("EN")), [Signal("t", Bit())], [Assign(Ref("t"), Ref("a")), inner],
                       [], [Assign(Ref("y"), BitConst(0))])
    assert verilog_stmts([s], "", {}) == ["generate",
                                          "  if ((EN) != 0)",
                                          "    begin : gen_x",
                                          "      wire       t;",
                                          "      assign t = a;",
                                          "      if ((B) != 0)",
                                          "        begin : gen_in",
                                          "          assign u = v;",
                                          "        end // gen_in",
                                          "    end // gen_x",
                                          "  else",
                                          "    begin : gen_x_b",
                                          "      assign y = 1'b0;",
                                          "    end // gen_x_b",
                                          "endgenerate"]

#============================================
# Units
#============================================

#--------------------------------------------
PKG = Package("demo_pkg", "work", [Comment(["Constants"]),
                                   Constant("DEMO_W"  , Integer(), IntConst(4)),
                                   Constant("DEMO_MAX", Vector(Ref("DEMO_W")), VecConst(15, 4)),
                                   Constant("DEMO_NU" , Integer(), IntConst(9))])

#--------------------------------------------
def test_imported_constants():
    """Only the constants used by the module, with their dependencies"""
    m = Module("m", ports=[Port("a_o", "out", Bit())], stmts=[Assign(Ref("a_o"), Eq(Ref("x"), Ref("DEMO_MAX")))],
               imports=[PKG, Use("lib", "other_pkg")])
    assert [c.name for c in imported_constants(m)] == ["DEMO_W", "DEMO_MAX"]

#--------------------------------------------
def test_header():
    text = verilog_header(PKG)
    assert text.startswith("`ifndef DEMO_PKG_VH\n`define DEMO_PKG_VH\n")
    assert "`define DEMO_W 4\n" in text
    assert "`define DEMO_MAX 4'hF\n" in text
    assert "// Constants\n" in text
    assert text.rstrip().endswith("`endif // DEMO_PKG_VH")

#--------------------------------------------
REC_DEMO = RecordType("demo_t", [RecordField("count", Vector(Ref("W"))), RecordField("max", Bit(), "Count = max")])

DEMO     = Module("demo",
                  generics = [Generic("W", Integer("positive"), IntConst(4), "Width"), Generic("EN", Boolean())],
                  ports    = [Comment(["Clock"]), Port("clk_i", "in", Bit()), Port("arst_b_i", "in", Bit()),
                              Port("demo_o", "out", REC_DEMO, prefix="demo", suffix="_o")],
                  decls    = [Signal("q", Vector(Ref("W"), "unsigned"))],
                  stmts    = [IfGenerate("gen_count", Truth(Ref("EN")), [], [
                                 Instance("demo_cnt", "ins_cnt", [("W", Ref("W"))],
                                          [("clk_i", Ref("clk_i")), ("arst_b_i", Ref("arst_b_i")), ("q_o", Ref("q")), ("unused_o", None)])],
                                 [], [Assign(Ref("q"), Fill(0, Ref("W")))]),
                              Assign(Ref("demo_o", ("count",)), Cast(Ref("q"), "slv")),
                              CondAssign(Ref("demo_o", ("max",)), [(Eq(Ref("q"), Fill(1, Ref("W"))), BitConst(1))], BitConst(0))],
                  header   = ["Demo"])

#--------------------------------------------
def test_module():
    text = verilog_module(DEMO, "demo.v")
    assert text.startswith("// Demo\n")
    assert "// verilator lint_off PINCONNECTEMPTY\nmodule demo\n" in text      # open port
    assert "DECLFILENAME" not in text                                          # file demo.v
    assert "  #(parameter W = 4 // Width\n   ,parameter EN = 0\n   )\n" in text
    assert "   ,output wire [W-1:0] demo_count_o\n" in text
    assert "   ,output wire demo_max_o // Count = max\n" in text
    assert "DECLFILENAME" in verilog_module(DEMO, "other.v")

#--------------------------------------------
# Counter instantiated by DEMO and testbench (hand written)
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
  reg clk = 0, arst_b = 0;
  wire [3:0] count;
  wire       max;
  always #5 clk = ~clk;
  initial #12 arst_b = 1;
  demo #(.W(4), .EN(1)) dut (.clk_i(clk), .arst_b_i(arst_b), .demo_count_o(count), .demo_max_o(max));
  initial begin
    wait (max);
    if (count !== 4'hF) $display("ERROR");
    else                $display("OK %0t", $time);
    $finish;
  end
endmodule
"""

#--------------------------------------------
def test_verilator(tmp_path):
    verilator = tool("verilator")
    (tmp_path / "demo.v").write_text(verilog_module(DEMO, "demo.v"))
    (tmp_path / "demo_cnt.v").write_text(DEMO_CNT)
    for enable in ["0", "1"]:
        result = subprocess.run([verilator, "--lint-only", "-Wall", "-Wno-UNUSEDSIGNAL", "-Wno-DECLFILENAME",
                                 "--top-module", "demo", f"-GEN={enable}", "demo.v", "demo_cnt.v"],
                                cwd=tmp_path, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr

#--------------------------------------------
def test_iverilog(tmp_path):
    """The counter of DEMO reaches its maximum value"""
    iverilog = tool("iverilog")
    vvp      = tool("vvp")
    (tmp_path / "demo.v").write_text(verilog_module(DEMO, "demo.v"))
    (tmp_path / "demo_cnt.v").write_text(DEMO_CNT)
    (tmp_path / "tb.v").write_text(DEMO_TB)
    build = subprocess.run([iverilog, "-g2005", "-o", "tb.vvp", "demo.v", "demo_cnt.v", "tb.v"],
                           cwd=tmp_path, capture_output=True, text=True)
    assert build.returncode == 0, build.stdout + build.stderr
    run   = subprocess.run([vvp, "-n", "tb.vvp"], cwd=tmp_path, capture_output=True, text=True)
    assert "OK" in run.stdout and "ERROR" not in run.stdout, run.stdout
