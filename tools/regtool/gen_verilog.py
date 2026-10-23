"""
Module gen_verilog.py
Generic Verilog (2005) writer : writes a module or the header of a package
described with hdl_model (independent of the CSR, see gen_hdl.py for the
CSR).

- a port of a record type is flattened in one port per record element
  (Port.flat_name), a reference to a record element uses this port
- the constants of the imported packages used by the module are copied as
  localparam (Verilog has no package) ; the header of a package defines
  them as `define
- VHDL only items are ignored : Use, Component, RecordType declarations,
  library of an instance, Cast
"""

import os
from   dataclasses import fields, is_dataclass

from   hdl_model import *

INDENT = "  "

#============================================
# Types and expressions
#============================================

#--------------------------------------------
def verilog_msb(width, ctx=None):
    """Most significant bit index of a vector of this width"""
    if isinstance(width, int):
        return str(width-1)
    return f"{verilog_expr(width, ctx)}-1"

#--------------------------------------------
def verilog_range(t, ctx=None):
    """Range of a type ("[msb:0] ", "" for a bit or a scalar)"""
    if isinstance(t, Vector):
        return f"[{verilog_msb(t.width, ctx)}:0] "
    if isinstance(t, (Bit, Integer, Boolean, String)):
        return ""
    if isinstance(t, ExternalType):
        return ""                               # parameter of a VHDL type : untyped
    raise TypeError(f"Type {t} has no Verilog equivalent")

#--------------------------------------------
def verilog_operand(e, ctx):
    """Expression, between parentheses if it is an operation"""
    text = verilog_expr(e, ctx)
    if isinstance(e, (Not, And, Or, Eq, BoolOr, Truth, Arith)):
        return f"({text})"
    return text

#--------------------------------------------
def verilog_expr(e, ctx=None):
    """Verilog expression ; ctx : ports of the module (flattened records)"""
    if isinstance(e, Ref):
        if not e.path:
            return e.name
        port = (ctx or {}).get(e.name)
        if port is None:
            raise ValueError(f"{e.name}.{'.'.join(e.path)} : only the elements of a record port are supported in Verilog")
        return port.flat_name(e.path)
    if isinstance(e, BitConst):
        return f"1'b{e.value}"
    if isinstance(e, VecConst):
        return f"{e.width}'h{e.value:X}"
    if isinstance(e, IntConst):
        return str(e.value)
    if isinstance(e, BoolConst):
        return "1" if e.value else "0"
    if isinstance(e, StrConst):
        return f"\"{e.value}\""
    if isinstance(e, Fill):
        return f"{{{verilog_expr(e.width, ctx)}{{1'b{e.bit}}}}}"
    if isinstance(e, Slice):
        return f"{verilog_ref(e.expr, ctx)}[{verilog_expr(e.msb, ctx)}:{verilog_expr(e.lsb, ctx)}]"
    if isinstance(e, Index):
        return f"{verilog_ref(e.expr, ctx)}[{verilog_expr(e.index, ctx)}]"
    if isinstance(e, Concat):
        return "{" + ", ".join([verilog_expr(p, ctx) for p in e.parts]) + "}"
    if isinstance(e, Not):
        return f"~{verilog_operand(e.expr, ctx)}"
    if isinstance(e, And):
        return " & ".join([verilog_operand(x, ctx) for x in e.exprs])
    if isinstance(e, Or):
        return " | ".join([verilog_operand(x, ctx) for x in e.exprs])
    if isinstance(e, Eq):
        return f"{verilog_operand(e.left, ctx)} == {verilog_operand(e.right, ctx)}"
    if isinstance(e, BoolOr):
        return " || ".join([verilog_operand(c, ctx) for c in e.conds])
    if isinstance(e, Truth):
        if isinstance(e.expr, BoolConst):
            return verilog_expr(e.expr, ctx)
        return f"({verilog_expr(e.expr, ctx)}) != 0"
    if isinstance(e, Cast):
        return verilog_expr(e.expr, ctx)
    if isinstance(e, Arith):
        return f"{verilog_operand(e.left, ctx)}{e.op}{verilog_operand(e.right, ctx)}"
    if isinstance(e, Raw):
        return e.text
    if isinstance(e, (int, str)):
        return str(e)
    raise TypeError(f"Unknown expression {e}")

#--------------------------------------------
def verilog_ref(e, ctx):
    """Name (part-select / bit-select are only allowed on a name)"""
    if not isinstance(e, Ref):
        raise ValueError(f"Slice of {e} : only a slice of a name is supported in Verilog")
    return verilog_expr(e, ctx)

#============================================
# Analysis of the model
#============================================

#--------------------------------------------
def refs(node, names=None):
    """Names referenced (Ref) in a model node"""
    names = set() if names is None else names
    if isinstance(node, Ref):
        names.add(node.name)
    elif isinstance(node, (list, tuple)):
        for item in node:
            refs(item, names)
    elif is_dataclass(node) and not isinstance(node, type):
        for f in fields(node):
            if not (isinstance(node, Port) and f.name == "type"):
                refs(getattr(node, f.name), names)
    return names

#--------------------------------------------
def imported_constants(m):
    """Constants of the imported packages used by the module (and their dependencies), in order"""
    constants = [c for p in m.imports if isinstance(p, Package) for c in p.items if isinstance(c, Constant)]
    used      = refs([m.generics, [p.type for p in m.ports if isinstance(p, Port)], m.decls, m.stmts])
    while True:
        needed = set(used)
        for c in constants:
            if c.name in used:
                refs([c.type, c.value], needed)
        if needed == used:
            break
        used = needed
    return [c for c in constants if c.name in used]

#--------------------------------------------
def has_open_port(stmts):
    """True if an instance has an unconnected port"""
    for s in stmts:
        if isinstance(s, Instance) and any(actual is None for _, actual in s.ports):
            return True
        if isinstance(s, IfGenerate) and (has_open_port(s.stmts) or has_open_port(s.else_stmts)):
            return True
    return False

#--------------------------------------------
def flat_ports(m):
    """Ports of the module, records flattened : list of Port or Comment"""
    result = []
    for p in m.ports:
        if isinstance(p, Comment):
            result.append(p)
        elif isinstance(p.type, RecordType):
            result += flatten(p, p.type, ())
        elif isinstance(p.type, ExternalType):
            raise ValueError(f"Port {p.name} : type {p.type.name} has no Verilog equivalent")
        else:
            result.append(p)
    return result

#--------------------------------------------
def flatten(port, record, path):
    result = []
    for f in record.fields:
        if isinstance(f.type, RecordType):
            result += flatten(port, f.type, path + (f.name,))
        else:
            result.append(Port(port.flat_name(path + (f.name,)), port.direction, f.type, f.comment))
    return result

#============================================
# Declarations and statements
#============================================

#--------------------------------------------
def verilog_comment(c, indent):
    if c.banner:
        lines = [f"{indent}//=================================="]
        lines+= [f"{indent}// {line}" for line in c.lines]
        lines+= [f"{indent}//=================================="]
        return lines
    return [f"{indent}// {line}" if line else f"{indent}//" for line in c.lines]

#--------------------------------------------
def verilog_comment_tail(comment):
    return f" // {comment}" if comment else ""

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
def verilog_decls(decls, indent, ctx):
    """Lines of declarations, names aligned"""
    widths = runs(decls, (Signal, Constant), lambda d: len(verilog_range(d.type, ctx)))
    names  = runs(decls, (Signal, Constant), lambda d: len(d.name))
    lines  = []
    for d, width, name in zip(decls, widths, names):
        lines += verilog_decl(d, indent, ctx, width, name)
    return lines

#--------------------------------------------
def verilog_decl(d, indent, ctx, width=0, name=0):
    """Lines of a declaration ; width, name : alignment of the range and of the name"""
    if isinstance(d, Comment):
        return verilog_comment(d, indent)
    if isinstance(d, Signal):
        line = f"{indent}wire       {verilog_range(d.type, ctx):<{width}}{d.name};{verilog_comment_tail(d.comment)}"
        if d.unused_ok:
            return [f"{indent}// verilator lint_off UNUSEDSIGNAL", line, f"{indent}// verilator lint_on UNUSEDSIGNAL"]
        return [line]
    if isinstance(d, Constant):
        return [f"{indent}localparam {verilog_range(d.type, ctx):<{width}}{d.name:<{name}} = {verilog_expr(d.value, ctx)};{verilog_comment_tail(d.comment)}"]
    if isinstance(d, (RecordType, Component)):
        return []                               # VHDL only
    if d is None or d == "":
        return [""]
    raise TypeError(f"Unknown declaration {d}")

#--------------------------------------------
def verilog_map(items, indent, ctx):
    """Lines of a parameter / port association list"""
    width = max(len(formal) for formal, _ in items)
    lines = []
    for i, (formal, actual) in enumerate(items):
        text = "" if actual is None else verilog_expr(actual, ctx)
        lines.append(f"{indent}{'(' if i == 0 else ','}.{formal:<{width}} ({text})")
    return lines

#--------------------------------------------
def verilog_stmts(stmts, indent, ctx, depth=0):
    """Lines of statements, targets of the assignments aligned"""
    widths = runs(stmts, Assign, lambda s: len(verilog_expr(s.target, ctx)))
    lines  = []
    for s, width in zip(stmts, widths):
        lines += verilog_stmt(s, indent, ctx, depth, width)
    return lines

#--------------------------------------------
def verilog_stmt(s, indent, ctx, depth=0, width=0):
    """Lines of a statement ; depth : generate nesting"""
    if isinstance(s, Comment):
        return verilog_comment(s, indent)
    if isinstance(s, Assign):
        return [f"{indent}assign {verilog_expr(s.target, ctx):<{width}} = {verilog_expr(s.expr, ctx)};"]
    if isinstance(s, CondAssign):
        head  = f"{indent}assign {verilog_expr(s.target, ctx)} = "
        pad   = " " * len(head)
        lines = []
        for cond, value in s.choices:
            lines.append(f"{pad if lines else head}{verilog_operand(cond, ctx)} ? {verilog_expr(value, ctx)} :")
        lines.append(f"{pad if lines else head}{verilog_expr(s.default, ctx)};")
        return lines
    if isinstance(s, Instance):
        lines = [f"{indent}{s.module}"]
        if s.generics:
            params = verilog_map(s.generics, indent + "  ", ctx)
            lines += [f"{indent}  #" + params[0].strip()] + [f"{indent}   " + l.strip() for l in params[1:]]
            lines.append(f"{indent}   )")
        lines.append(f"{indent}{s.name}")
        lines += verilog_map(s.ports, indent + "  ", ctx)
        lines.append(f"{indent}  );")
        return lines
    if isinstance(s, IfGenerate):
        inner = indent + INDENT if depth == 0 else indent
        lines = [f"{indent}generate"] if depth == 0 else []
        lines+= [f"{inner}if ({verilog_expr(s.cond, ctx)})",
                 f"{inner}  begin : {s.name}"]
        lines+= verilog_decls(s.decls, inner + "    ", ctx)
        lines+= verilog_stmts(s.stmts, inner + "    ", ctx, depth+1)
        lines+= [f"{inner}  end // {s.name}"]
        if s.else_decls or s.else_stmts:
            lines += [f"{inner}else",
                      f"{inner}  begin : {s.name}_b"]
            lines += verilog_decls(s.else_decls, inner + "    ", ctx)
            lines += verilog_stmts(s.else_stmts, inner + "    ", ctx, depth+1)
            lines += [f"{inner}  end // {s.name}_b"]
        if depth == 0:
            lines.append(f"{indent}endgenerate")
        return lines
    if s is None or s == "":
        return [""]
    raise TypeError(f"Unknown statement {s}")

#============================================
# Units
#============================================

#--------------------------------------------
def verilog_header_lines(header):
    return [f"// {line}" if line else "//" for line in header] + ([""] if header else [])

#--------------------------------------------
def verilog_header(p):
    """Text of the header of the package p : `define of its constants"""
    guard = f"{p.name.upper()}_VH"
    lines = verilog_header_lines(p.header)
    lines+= [f"`ifndef {guard}", f"`define {guard}", ""]
    for item in p.items:
        if isinstance(item, Comment):
            lines += verilog_comment(item, "")
        elif isinstance(item, Constant):
            lines.append(f"`define {item.name} {verilog_expr(item.value)}{verilog_comment_tail(item.comment)}")
        elif item is None or item == "":
            lines.append("")
    lines += ["", f"`endif // {guard}"]
    return "\n".join(lines) + "\n"

#--------------------------------------------
def verilog_module(m, filename=None):
    """
    Text of the module m ; filename : name of the output file (lint
    waiver if it is not the name of the module)
    """
    ctx     = {p.name: p for p in m.ports if isinstance(p, Port)}
    waivers = []
    if filename and os.path.splitext(os.path.basename(filename))[0] != m.name:
        waivers.append("DECLFILENAME")
    if has_open_port(m.stmts):
        waivers.append("PINCONNECTEMPTY")

    lines = verilog_header_lines(m.header)
    lines+= [f"// verilator lint_off {w}" for w in waivers]
    lines.append(f"module {m.name}")
    if m.generics:
        for i, g in enumerate(m.generics):
            default = g.default if g.default is not None else (StrConst("") if isinstance(g.type, String) else IntConst(0))
            lines.append(f"  {'#(' if i == 0 else ' ,'}parameter {verilog_range(g.type)}{g.name} = {verilog_expr(default)}{verilog_comment_tail(g.comment)}")
        lines.append("   )")
    lines.append("  (")
    ports = flat_ports(m)
    first = True
    for p in ports:
        if isinstance(p, Comment):
            lines += verilog_comment(p, "    ")
            continue
        direction = "input " if p.direction == "in" else "output"
        lines.append(f"   {' ' if first else ','}{direction} wire {verilog_range(p.type, ctx)}{p.name}{verilog_comment_tail(p.comment)}")
        first = False
    lines.append("   );")
    lines.append("")

    constants = imported_constants(m)
    if constants:
        lines += verilog_comment(Comment([f"Constants of {', '.join(p.name for p in m.imports if isinstance(p, Package))}"]), INDENT)
        lines += verilog_decls(constants, INDENT, ctx)
        lines.append("")
    lines += verilog_decls(m.decls, INDENT, ctx)
    lines.append("")
    lines += verilog_stmts(m.stmts, INDENT, ctx)
    lines.append("")
    lines.append("endmodule")
    lines += [f"// verilator lint_on {w}" for w in waivers]
    return "\n".join(lines) + "\n"

#--------------------------------------------
def write_verilog_header(p, output_path):
    with open(output_path, 'w') as file:
        file.write(verilog_header(p))

#--------------------------------------------
def write_verilog_module(m, output_path):
    with open(output_path, 'w') as file:
        file.write(verilog_module(m, output_path))
