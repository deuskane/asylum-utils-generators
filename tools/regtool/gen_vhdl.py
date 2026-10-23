"""
Module gen_vhdl.py
Generic VHDL writer : writes a package or a module described with
hdl_model (independent of the CSR, see gen_hdl.py for the CSR).
"""

from hdl_model import *

INDENT = "  "

#============================================
# Types and expressions
#============================================

#--------------------------------------------
def vhdl_msb(width):
    """Most significant bit index of a vector of this width"""
    if isinstance(width, int):
        return str(width-1)
    return f"{vhdl_expr(width)}-1"

#--------------------------------------------
def vhdl_type(t):
    """VHDL type"""
    if isinstance(t, Bit):
        return "std_logic"
    if isinstance(t, Vector):
        kind = "unsigned" if t.kind == "unsigned" else "std_logic_vector"
        return f"{kind}({vhdl_msb(t.width)} downto 0)"
    if isinstance(t, Integer):
        return t.kind
    if isinstance(t, Boolean):
        return "boolean"
    if isinstance(t, String):
        return "string"
    if isinstance(t, (RecordType, ExternalType)):
        return t.name
    raise TypeError(f"Unknown type {t}")

#--------------------------------------------
def vhdl_operand(e):
    """Expression, between parentheses if it is an operation"""
    text = vhdl_expr(e)
    if isinstance(e, (Not, And, Or, Eq, BoolOr, Arith)):
        return f"({text})"
    return text

#--------------------------------------------
def vhdl_expr(e, concat=False):
    """
    VHDL expression ; concat : operand of a concatenation (a Fill is then
    a bit string literal)
    """
    if isinstance(e, Ref):
        return ".".join([e.name, *e.path])
    if isinstance(e, BitConst):
        return f"'{e.value}'"
    if isinstance(e, VecConst):
        return f"\"{e.value:0{e.width}b}\""
    if isinstance(e, IntConst):
        return str(e.value)
    if isinstance(e, BoolConst):
        return "true" if e.value else "false"
    if isinstance(e, StrConst):
        return f"\"{e.value}\""
    if isinstance(e, Fill):
        if not concat:
            return f"(others => '{e.bit}')"
        if isinstance(e.width, int):
            return f"\"{str(e.bit)*e.width}\""
        return f"std_logic_vector'({vhdl_msb(e.width)} downto 0 => '{e.bit}')"
    if isinstance(e, Slice):
        return f"{vhdl_expr(e.expr)}({vhdl_expr(e.msb)} downto {vhdl_expr(e.lsb)})"
    if isinstance(e, Index):
        return f"{vhdl_expr(e.expr)}({vhdl_expr(e.index)})"
    if isinstance(e, Concat):
        return " & ".join([vhdl_expr(p, concat=True) for p in e.parts])
    if isinstance(e, Not):
        return f"not {vhdl_operand(e.expr)}"
    if isinstance(e, And):
        return " and ".join([vhdl_operand(x) for x in e.exprs])
    if isinstance(e, Or):
        return " or ".join([vhdl_operand(x) for x in e.exprs])
    if isinstance(e, Eq):
        return f"{vhdl_operand(e.left)} = {vhdl_operand(e.right)}"
    if isinstance(e, BoolOr):
        return " or ".join([f"({vhdl_expr(c)})" for c in e.conds])
    if isinstance(e, Truth):
        return vhdl_expr(e.expr)
    if isinstance(e, Cast):
        kind = "unsigned" if e.kind == "unsigned" else "std_logic_vector"
        return f"{kind}({vhdl_expr(e.expr)})"
    if isinstance(e, Arith):
        return f"{vhdl_operand(e.left)}{e.op}{vhdl_operand(e.right)}"
    if isinstance(e, Raw):
        return e.text
    if isinstance(e, (int, str)):
        return str(e)
    raise TypeError(f"Unknown expression {e}")

#============================================
# Declarations and statements
#============================================

#--------------------------------------------
def vhdl_comment(c, indent):
    if c.banner:
        lines = [f"{indent}--=================================="]
        lines+= [f"{indent}-- {line}" for line in c.lines]
        lines+= [f"{indent}--=================================="]
        return lines
    return [f"{indent}-- {line}" if line else f"{indent}--" for line in c.lines]

#--------------------------------------------
def vhdl_comment_tail(comment):
    return f" -- {comment}" if comment else ""

#--------------------------------------------
def vhdl_record(r, indent):
    lines = vhdl_comment(Comment([r.comment]), indent) if r.comment else []
    lines.append(f"{indent}type {r.name} is record")
    width = max(len(f.name) for f in r.fields)
    for f in r.fields:
        lines.append(f"{indent}  {f.name:<{width}} : {vhdl_type(f.type)};{vhdl_comment_tail(f.comment)}")
    lines.append(f"{indent}end record {r.name};")
    lines.append("")
    return lines

#--------------------------------------------
def runs(items, kinds, key):
    """Width of key(item) on each run of consecutive items of kinds (alignment), 0 elsewhere"""
    widths = [0] * len(items)
    i      = 0
    while i < len(items):
        j = i
        while j < len(items) and isinstance(items[j], kinds):
            j += 1
        if j > i:
            widths[i:j] = [max(key(x) for x in items[i:j])] * (j-i)
        i = max(j, i+1)
    return widths

#--------------------------------------------
def vhdl_decls(decls, indent):
    """Lines of declarations, names aligned"""
    widths = runs(decls, (Signal, Constant), lambda d: len(d.name))
    lines  = []
    for d, width in zip(decls, widths):
        lines += vhdl_decl(d, indent, width)
    return lines

#--------------------------------------------
def vhdl_decl(d, indent, width=0):
    """Lines of a declaration"""
    if isinstance(d, Comment):
        return vhdl_comment(d, indent)
    if isinstance(d, Signal):
        return [f"{indent}signal   {d.name:<{width}} : {vhdl_type(d.type)};{vhdl_comment_tail(d.comment)}"]
    if isinstance(d, Constant):
        return [f"{indent}constant {d.name:<{width}} : {vhdl_type(d.type)} := {vhdl_expr(d.value)};{vhdl_comment_tail(d.comment)}"]
    if isinstance(d, RecordType):
        return vhdl_record(d, indent)
    if isinstance(d, Component):
        return vhdl_interface(d.module, "component", indent) + [""]
    if d is None or d == "":
        return [""]
    raise TypeError(f"Unknown declaration {d}")

#--------------------------------------------
def vhdl_map(items, indent):
    """Lines of a generic map / port map association list"""
    width = max(len(formal) for formal, _ in items)
    lines = []
    for i, (formal, actual) in enumerate(items):
        text = "open" if actual is None else vhdl_expr(actual)
        lines.append(f"{indent}{'(' if i == 0 else ','}{formal:<{width}} => {text}")
    return lines

#--------------------------------------------
def vhdl_stmts(stmts, indent):
    """Lines of statements, targets of the assignments aligned"""
    widths = runs(stmts, Assign, lambda s: len(vhdl_expr(s.target)))
    lines  = []
    for s, width in zip(stmts, widths):
        lines += vhdl_stmt(s, indent, width)
    return lines

#--------------------------------------------
def vhdl_stmt(s, indent, width=0):
    """Lines of a concurrent statement"""
    if isinstance(s, Comment):
        return vhdl_comment(s, indent)
    if isinstance(s, Assign):
        return [f"{indent}{vhdl_expr(s.target):<{width}} <= {vhdl_expr(s.expr)};"]
    if isinstance(s, CondAssign):
        head  = f"{indent}{vhdl_expr(s.target)} <= "
        pad   = " " * len(head)
        lines = []
        for cond, value in s.choices:
            lines.append(f"{pad if lines else head}{vhdl_expr(value)} when {vhdl_expr(cond)} else")
        lines.append(f"{pad if lines else head}{vhdl_expr(s.default)};")
        return lines
    if isinstance(s, Instance):
        unit  = s.module if s.library is None else f"entity {s.library}.{s.module}"
        lines = [f"{indent}{s.name} : {unit}"]
        if s.generics:
            lines.append(f"{indent}  generic map")
            lines+= vhdl_map(s.generics, indent + "    ")
            lines.append(f"{indent}    )")
        lines.append(f"{indent}  port map")
        lines+= vhdl_map(s.ports, indent + "    ")
        lines.append(f"{indent}    );")
        return lines
    if isinstance(s, IfGenerate):
        cond  = vhdl_expr(s.cond)
        lines = vhdl_generate(s.name, f"({cond})", s.decls, s.stmts, indent)
        if s.else_decls or s.else_stmts:
            lines.append("")
            lines += vhdl_generate(f"{s.name}_b", f"not ({cond})", s.else_decls, s.else_stmts, indent)
        return lines
    if s is None or s == "":
        return [""]
    raise TypeError(f"Unknown statement {s}")

#--------------------------------------------
def vhdl_generate(name, cond, decls, stmts, indent):
    lines = [f"{indent}{name}: if {cond} generate"]
    lines+= vhdl_decls(decls, indent + INDENT)
    if decls:
        lines.append(f"{indent}begin")
    lines+= vhdl_stmts(stmts, indent + INDENT)
    lines.append(f"{indent}end generate {name};")
    return lines

#============================================
# Units
#============================================

#--------------------------------------------
def vhdl_header(header):
    return [f"-- {line}" if line else "--" for line in header] + ([""] if header else [])

#--------------------------------------------
def vhdl_context(imports):
    """Context clause : IEEE, then one library / use per imported package"""
    lines = ["library IEEE;",
             "use     IEEE.STD_LOGIC_1164.ALL;",
             "use     IEEE.NUMERIC_STD.ALL;",
             ""]
    libraries = []
    for p in imports:
        if p.library not in libraries:
            libraries.append(p.library)
    for library in libraries:
        lines.append(f"library {library};")
        for p in imports:
            if p.library == library:
                lines.append(f"use     {library}.{p.name if isinstance(p, Package) else p.package}.ALL;")
        lines.append("")
    return lines

#--------------------------------------------
def vhdl_interface(m, kind, indent=""):
    """Entity or component declaration of the module m"""
    lines = [f"{indent}{kind} {m.name} is"]
    if m.generics:
        lines.append(f"{indent}  generic (")
        width = max(len(g.name) for g in m.generics)
        for i, g in enumerate(m.generics):
            default = "" if g.default is None else f" := {vhdl_expr(g.default)}"
            lines.append(f"{indent}   {' ' if i == 0 else ';'}{g.name:<{width}} : {vhdl_type(g.type)}{default}{vhdl_comment_tail(g.comment)}")
        lines.append(f"{indent}  );")
    lines.append(f"{indent}  port (")
    width = max([len(p.name) for p in m.ports if isinstance(p, Port)] + [0])
    first = True
    for p in m.ports:
        if isinstance(p, Comment):
            lines += vhdl_comment(p, indent + "    ")
            continue
        lines.append(f"{indent}   {' ' if first else ';'}{p.name:<{width}} : {p.direction:<3} {vhdl_type(p.type)}{vhdl_comment_tail(p.comment)}")
        first = False
    lines.append(f"{indent}  );")
    lines.append(f"{indent}end {kind} {m.name};")
    return lines

#--------------------------------------------
def vhdl_package(p):
    """Text of the package p"""
    lines  = vhdl_header(p.header)
    lines += vhdl_context(p.uses)
    lines.append(f"package {p.name} is")
    lines.append("")
    lines += vhdl_decls(p.items, INDENT)
    lines.append("")
    lines.append(f"end package {p.name};")
    return "\n".join(lines) + "\n"

#--------------------------------------------
def vhdl_module(m):
    """Text of the module m (entity and architecture rtl)"""
    lines  = vhdl_header(m.header)
    lines += vhdl_context(m.imports)
    lines += vhdl_interface(m, "entity")
    lines.append("")
    lines.append(f"architecture rtl of {m.name} is")
    lines.append("")
    lines += vhdl_decls(m.decls, INDENT)
    lines.append("")
    lines.append("begin  -- architecture rtl")
    lines.append("")
    lines += vhdl_stmts(m.stmts, INDENT)
    lines.append("")
    lines.append("end architecture rtl;")
    return "\n".join(lines) + "\n"

#--------------------------------------------
def write_vhdl_package(p, output_path):
    with open(output_path, 'w') as file:
        file.write(vhdl_package(p))

#--------------------------------------------
def write_vhdl_module(m, output_path):
    with open(output_path, 'w') as file:
        file.write(vhdl_module(m))
