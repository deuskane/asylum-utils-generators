"""
Unit tests of the generic VHDL writer (gen_vhdl.py) : hdl_model -> VHDL,
without CSR. The module DEMO (a counter with a record port, a generate and
an instance) is analyzed with GHDL when ghdl is in the PATH.
"""

import subprocess

import pytest

from conftest import tool
from hdl_model import *
from gen_vhdl  import vhdl_type, vhdl_expr, vhdl_stmts, vhdl_decls, vhdl_package, vhdl_module

#============================================
# Types and expressions
#============================================

#--------------------------------------------
@pytest.mark.parametrize("t, text", [
    (Bit()                          , "std_logic"),
    (Vector(8)                      , "std_logic_vector(7 downto 0)"),
    (Vector(Ref("W"))               , "std_logic_vector(W-1 downto 0)"),
    (Vector(4, "unsigned")          , "unsigned(3 downto 0)"),
    (Integer("positive")            , "positive"),
    (Boolean()                      , "boolean"),
    (String()                       , "string"),
    (RecordType("rec_t", [])        , "rec_t"),
    (ExternalType("sbi_ini_t")      , "sbi_ini_t"),
])
def test_type(t, text):
    assert vhdl_type(t) == text

#--------------------------------------------
@pytest.mark.parametrize("e, text", [
    (Ref("a")                               , "a"),
    (Ref("r_o", ("x", "y"))                 , "r_o.x.y"),
    (BitConst(1)                            , "'1'"),
    (VecConst(5, 4)                         , '"0101"'),
    (IntConst(3)                            , "3"),
    (BoolConst(True)                        , "true"),
    (StrConst("rw")                         , '"rw"'),
    (Fill(0, 8)                             , "(others => '0')"),
    (Slice(Ref("a"), 7, 4)                  , "a(7 downto 4)"),
    (Index(Ref("a"), 2)                     , "a(2)"),
    (Concat([Fill(0, 3), Ref("a"), BitConst(1)]), "\"000\" & a & '1'"),
    (Concat([Fill(1, Ref("W"))])            , "std_logic_vector'(W-1 downto 0 => '1')"),
    (Not(Ref("a"))                          , "not a"),
    (And([Ref("a"), Not(Ref("b"))])         , "a and (not b)"),
    (Or([Ref("a"), Ref("b")])               , "a or b"),
    (Eq(Ref("a"), BitConst(1))              , "a = '1'"),
    (BoolOr([Eq(Ref("a"), Ref("b")), Eq(Ref("c"), Ref("d"))]), "(a = b) or (c = d)"),
    (Truth(Ref("EN"))                       , "EN"),
    (Cast(Ref("a"), "unsigned")             , "unsigned(a)"),
    (Cast(Ref("a"), "slv")                  , "std_logic_vector(a)"),
    (Arith("/", Ref("W"), IntConst(8))      , "W/8"),
    (Raw("f(x)")                            , "f(x)"),
])
def test_expr(e, text):
    assert vhdl_expr(e) == text

#============================================
# Declarations and statements
#============================================

#--------------------------------------------
def test_decls_aligned():
    lines = vhdl_decls([Signal("a", Bit()), Signal("bcd", Vector(2), "comment"), "",
                        Constant("C", Integer(), IntConst(4))], "  ")
    assert lines == ["  signal   a   : std_logic;",
                     "  signal   bcd : std_logic_vector(1 downto 0); -- comment",
                     "",
                     "  constant C : natural := 4;"]

#--------------------------------------------
def test_assign_aligned():
    assert vhdl_stmts([Assign(Ref("a"), Ref("b")), Assign(Ref("abc"), BitConst(0))], "  ") == \
        ["  a   <= b;", "  abc <= '0';"]

#--------------------------------------------
def test_cond_assign():
    s = CondAssign(Ref("y"), [(Eq(Ref("s"), BitConst(1)), Ref("a")), (Eq(Ref("t"), BitConst(1)), Ref("b"))], Fill(0, 4))
    assert vhdl_stmts([s], "") == ["y <= a when s = '1' else",
                                   "     b when t = '1' else",
                                   "     (others => '0');"]

#--------------------------------------------
def test_instance():
    s = Instance("cell", "ins_cell", [("W", IntConst(4))], [("a_i", Ref("a")), ("y_o", None)])
    assert vhdl_stmts([s], "") == ["ins_cell : cell",
                                   "  generic map",
                                   "    (W => 4",
                                   "    )",
                                   "  port map",
                                   "    (a_i => a",
                                   "    ,y_o => open",
                                   "    );"]
    s = Instance("cell", "ins_cell", [], [("a_i", Ref("a"))], library="lib")
    assert vhdl_stmts([s], "")[0] == "ins_cell : entity lib.cell"

#--------------------------------------------
def test_generate():
    s = IfGenerate("gen_x", Truth(Ref("EN")), [Signal("t", Bit())], [Assign(Ref("t"), Ref("a"))],
                   [], [Assign(Ref("y"), BitConst(0))])
    assert vhdl_stmts([s], "") == ["gen_x: if (EN) generate",
                                   "  signal   t : std_logic;",
                                   "begin",
                                   "  t <= a;",
                                   "end generate gen_x;",
                                   "",
                                   "gen_x_b: if not (EN) generate",
                                   "  y <= '0';",
                                   "end generate gen_x_b;"]

#============================================
# Units
#============================================

#--------------------------------------------
REC   = RecordType("demo_t", [RecordField("count", Vector(Ref("W"))), RecordField("max", Bit(), "Count = max")])

DEMO  = Module("demo",
               generics = [Generic("W", Integer("positive"), IntConst(4), "Width"), Generic("EN", Boolean())],
               ports    = [Comment(["Clock"]), Port("clk_i", "in", Bit()), Port("arst_b_i", "in", Bit()),
                           Port("demo_o", "out", REC, prefix="demo", suffix="_o")],
               decls    = [Signal("q", Vector(Ref("W"), "unsigned"))],
               stmts    = [IfGenerate("gen_count", Truth(Ref("EN")), [], [
                              Instance("demo_cnt", "ins_cnt", [("W", Ref("W"))],
                                       [("clk_i", Ref("clk_i")), ("arst_b_i", Ref("arst_b_i")), ("q_o", Ref("q"))], library="work")],
                              [], [Assign(Ref("q"), Fill(0, Ref("W")))]),
                           Assign(Ref("demo_o", ("count",)), Cast(Ref("q"), "slv")),
                           CondAssign(Ref("demo_o", ("max",)), [(Eq(Cast(Ref("q"), "slv"), Concat([Fill(1, Ref("W"))])), BitConst(1))], BitConst(0))],
               header   = ["Demo"])

DEMO_PKG = Package("demo_pkg", "work", [REC, Component(DEMO)])

#--------------------------------------------
# Counter instantiated by DEMO (hand written)
DEMO_CNT = """
library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.NUMERIC_STD.ALL;
entity demo_cnt is
  generic (W : positive);
  port (clk_i : in std_logic; arst_b_i : in std_logic; q_o : out unsigned(W-1 downto 0));
end entity demo_cnt;
architecture rtl of demo_cnt is
  signal q : unsigned(W-1 downto 0);
begin
  process (clk_i, arst_b_i) is
  begin
    if arst_b_i = '0' then q <= (others => '0'); elsif rising_edge(clk_i) then q <= q + 1; end if;
  end process;
  q_o <= q;
end architecture rtl;
"""

#--------------------------------------------
def test_module():
    text = vhdl_module(DEMO.__class__(**{**DEMO.__dict__, "imports": [DEMO_PKG]}))
    assert text.startswith("-- Demo\n")
    assert "library work;\nuse     work.demo_pkg.ALL;\n" in text
    assert "entity demo is\n  generic (\n    W  : positive := 4 -- Width\n   ;EN : boolean\n  );\n" in text
    assert "   ;demo_o   : out demo_t\n" in text
    assert "architecture rtl of demo is" in text

#--------------------------------------------
def test_package():
    text = vhdl_package(DEMO_PKG)
    assert "type demo_t is record\n    count : std_logic_vector(W-1 downto 0);\n    max   : std_logic; -- Count = max\n" in text
    assert "  component demo is\n" in text
    assert text.rstrip().endswith("end package demo_pkg;")

#--------------------------------------------
@pytest.mark.parametrize("enable", ["true", "false"])
def test_ghdl(tmp_path, enable):
    """DEMO and its package : analysis (-Wall, no warning), elaboration and run"""
    ghdl = tool("ghdl")
    module = Module(**{**DEMO.__dict__, "imports": [DEMO_PKG]})
    # W is a generic of the package record : constant W in a package for the record
    package = Package("demo_pkg", "work", [Constant("W", Integer("positive"), IntConst(4)), REC, Component(module)])
    module.imports = [package]
    module.generics = [Generic("EN", Boolean())]
    (tmp_path / "demo_cnt.vhd").write_text(DEMO_CNT)
    (tmp_path / "demo_pkg.vhd").write_text(vhdl_package(package))
    (tmp_path / "demo.vhd"    ).write_text(vhdl_module(module))

    options = ["--std=08", f"--workdir={tmp_path}"]
    for step in [["-a", "-Wall", "demo_cnt.vhd", "demo_pkg.vhd", "demo.vhd"],
                 ["--elab-run", "demo", f"-gEN={enable}", "--stop-time=100ns"]]:
        result = subprocess.run([ghdl, step[0], *options, *step[1:]], cwd=tmp_path, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "warning" not in result.stdout + result.stderr, result.stdout + result.stderr
