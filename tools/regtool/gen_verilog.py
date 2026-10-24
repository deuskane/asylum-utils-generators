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

The writer is the class VerilogWriter ; gen_systemverilog.py derives it
(SystemVerilog : records as packed structs, packages).
"""

import os
from   dataclasses import fields, is_dataclass

from   hdl_model import *

INDENT = "  "

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

#============================================
# Writer
#============================================

class VerilogWriter:
    """
    Verilog 2005 writer ; ports : ports of the module by name (references
    to the elements of a record port)
    """

    #------------------------------------
    def __init__(self, ports=None):
        self.ports = ports or {}

    #====================================
    # Types and expressions
    #====================================

    #------------------------------------
    def msb(self, width):
        """Most significant bit index of a vector of this width"""
        if isinstance(width, int):
            return str(width-1)
        return f"{self.expr(width)}-1"

    #------------------------------------
    def range(self, t):
        """Range of a type ("[msb:0] ", "" for a bit or a scalar)"""
        if isinstance(t, Vector):
            return f"[{self.msb(t.width)}:0] "
        if isinstance(t, (Bit, Integer, Boolean, String)):
            return ""
        if isinstance(t, ExternalType):
            return ""                           # parameter of a VHDL type : untyped
        raise TypeError(f"Type {t} has no Verilog equivalent")

    #------------------------------------
    def signal_type(self, t):
        """(keyword, type) of a signal declaration"""
        return "wire", self.range(t)

    #------------------------------------
    def constant_type(self, t):
        """(keyword, type) of a constant declaration"""
        return "localparam", self.range(t)

    #------------------------------------
    def port_type(self, t):
        """Type of a port"""
        return f"wire {self.range(t)}"

    #------------------------------------
    def param_type(self, t):
        """Type of a parameter"""
        return self.range(t)

    #------------------------------------
    def ref(self, e):
        """Reference ; the element of a record port is the flattened port"""
        if not e.path:
            return e.name
        port = self.ports.get(e.name)
        if port is None:
            raise ValueError(f"{e.name}.{'.'.join(e.path)} : only the elements of a record port are supported in Verilog")
        return port.flat_name(e.path)

    #------------------------------------
    def operand(self, e):
        """Expression, between parentheses if it is an operation"""
        text = self.expr(e)
        if isinstance(e, (Not, And, Or, Eq, BoolOr, Truth, Arith)):
            return f"({text})"
        return text

    #------------------------------------
    def name(self, e):
        """Name (part-select / bit-select are only allowed on a name)"""
        if not isinstance(e, Ref):
            raise ValueError(f"Slice of {e} : only a slice of a name is supported in Verilog")
        return self.ref(e)

    #------------------------------------
    def expr(self, e):
        """Expression"""
        if isinstance(e, Ref):
            return self.ref(e)
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
            return f"{{{self.expr(e.width)}{{1'b{e.bit}}}}}"
        if isinstance(e, Slice):
            return f"{self.name(e.expr)}[{self.expr(e.msb)}:{self.expr(e.lsb)}]"
        if isinstance(e, Index):
            return f"{self.name(e.expr)}[{self.expr(e.index)}]"
        if isinstance(e, Concat):
            return "{" + ", ".join([self.expr(p) for p in e.parts]) + "}"
        if isinstance(e, Not):
            return f"~{self.operand(e.expr)}"
        if isinstance(e, And):
            return " & ".join([self.operand(x) for x in e.exprs])
        if isinstance(e, Or):
            return " | ".join([self.operand(x) for x in e.exprs])
        if isinstance(e, Eq):
            return f"{self.operand(e.left)} == {self.operand(e.right)}"
        if isinstance(e, BoolOr):
            return " || ".join([self.operand(c) for c in e.conds])
        if isinstance(e, Truth):
            if isinstance(e.expr, BoolConst):
                return self.expr(e.expr)
            return f"({self.expr(e.expr)}) != 0"
        if isinstance(e, Cast):
            return self.expr(e.expr)
        if isinstance(e, Arith):
            return f"{self.operand(e.left)}{e.op}{self.operand(e.right)}"
        if isinstance(e, Raw):
            return e.text
        if isinstance(e, (int, str)):
            return str(e)
        raise TypeError(f"Unknown expression {e}")

    #====================================
    # Declarations and statements
    #====================================

    #------------------------------------
    def comment(self, c, indent):
        if c.banner:
            lines = [f"{indent}//=================================="]
            lines+= [f"{indent}// {line}" for line in c.lines]
            lines+= [f"{indent}//=================================="]
            return lines
        return [f"{indent}// {line}" if line else f"{indent}//" for line in c.lines]

    #------------------------------------
    def comment_tail(self, comment):
        return f" // {comment}" if comment else ""

    #------------------------------------
    def decl_type(self, d):
        """(keyword, type) of a signal or a constant"""
        return self.signal_type(d.type) if isinstance(d, Signal) else self.constant_type(d.type)

    #------------------------------------
    def decls(self, decls, indent):
        """Lines of declarations, types and names aligned"""
        widths = runs(decls, (Signal, Constant), lambda d: len(self.decl_type(d)[1]))
        names  = runs(decls, (Signal, Constant), lambda d: len(d.name))
        lines  = []
        for d, width, name in zip(decls, widths, names):
            lines += self.decl(d, indent, width, name)
        return lines

    #------------------------------------
    def decl(self, d, indent, width=0, name=0):
        """Lines of a declaration ; width, name : alignment of the type and of the name"""
        if isinstance(d, Comment):
            return self.comment(d, indent)
        if isinstance(d, Signal):
            keyword, t = self.decl_type(d)
            line = f"{indent}{keyword:<10} {t:<{width}}{d.name};{self.comment_tail(d.comment)}"
            if d.unused_ok:
                return [f"{indent}// verilator lint_off UNUSEDSIGNAL", line, f"{indent}// verilator lint_on UNUSEDSIGNAL"]
            return [line]
        if isinstance(d, Constant):
            keyword, t = self.decl_type(d)
            return [f"{indent}{keyword:<10} {t:<{width}}{d.name:<{name}} = {self.expr(d.value)};{self.comment_tail(d.comment)}"]
        if isinstance(d, (RecordType, Component, Use)):
            return []                           # Package items (VHDL)
        if d is None or d == "":
            return [""]
        raise TypeError(f"Unknown declaration {d}")

    #------------------------------------
    def map(self, items, indent):
        """Lines of a parameter / port association list"""
        width = max(len(formal) for formal, _ in items)
        lines = []
        for i, (formal, actual) in enumerate(items):
            text = "" if actual is None else self.expr(actual)
            lines.append(f"{indent}{'(' if i == 0 else ','}.{formal:<{width}} ({text})")
        return lines

    #------------------------------------
    def stmts(self, stmts, indent, depth=0):
        """Lines of statements, targets of the assignments aligned"""
        widths = runs(stmts, Assign, lambda s: len(self.expr(s.target)))
        lines  = []
        for s, width in zip(stmts, widths):
            lines += self.stmt(s, indent, depth, width)
        return lines

    #------------------------------------
    def stmt(self, s, indent, depth=0, width=0):
        """Lines of a statement ; depth : generate nesting"""
        if isinstance(s, Comment):
            return self.comment(s, indent)
        if isinstance(s, Assign):
            return [f"{indent}assign {self.expr(s.target):<{width}} = {self.expr(s.expr)};"]
        if isinstance(s, CondAssign):
            head  = f"{indent}assign {self.expr(s.target)} = "
            pad   = " " * len(head)
            lines = []
            for cond, value in s.choices:
                lines.append(f"{pad if lines else head}{self.operand(cond)} ? {self.expr(value)} :")
            lines.append(f"{pad if lines else head}{self.expr(s.default)};")
            return lines
        if isinstance(s, Instance):
            lines = [f"{indent}{s.module}"]
            if s.generics:
                params = self.map(s.generics, indent + "  ")
                lines += [f"{indent}  #" + params[0].strip()] + [f"{indent}   " + l.strip() for l in params[1:]]
                lines.append(f"{indent}   )")
            lines.append(f"{indent}{s.name}")
            lines += self.map(s.ports, indent + "  ")
            lines.append(f"{indent}  );")
            return lines
        if isinstance(s, IfGenerate):
            inner = indent + INDENT if depth == 0 else indent
            lines = [f"{indent}generate"] if depth == 0 else []
            lines+= [f"{inner}if ({self.expr(s.cond)})",
                     f"{inner}  begin : {s.name}"]
            lines+= self.decls(s.decls, inner + "    ")
            lines+= self.stmts(s.stmts, inner + "    ", depth+1)
            lines+= [f"{inner}  end // {s.name}"]
            if s.else_decls or s.else_stmts:
                lines += [f"{inner}else",
                          f"{inner}  begin : {s.name}_b"]
                lines += self.decls(s.else_decls, inner + "    ")
                lines += self.stmts(s.else_stmts, inner + "    ", depth+1)
                lines += [f"{inner}  end // {s.name}_b"]
            if depth == 0:
                lines.append(f"{indent}endgenerate")
            return lines
        if s is None or s == "":
            return [""]
        raise TypeError(f"Unknown statement {s}")

    #====================================
    # Units
    #====================================

    #------------------------------------
    def header_lines(self, header):
        return [f"// {line}" if line else "//" for line in header] + ([""] if header else [])

    #------------------------------------
    def module_ports(self, m):
        """Ports of the module : records flattened"""
        return flat_ports(m)

    #------------------------------------
    def module_imports(self, m):
        """Lines after the module name : none (Verilog has no package)"""
        return []

    #------------------------------------
    def module_constants(self, m):
        """Constants declared at the beginning of the module : the used constants of the imported packages"""
        constants = imported_constants(m)
        if not constants:
            return []
        lines  = self.comment(Comment([f"Constants of {', '.join(p.name for p in m.imports if isinstance(p, Package))}"]), INDENT)
        lines += self.decls(constants, INDENT)
        lines.append("")
        return lines

    #------------------------------------
    def module(self, m, filename=None):
        """
        Text of the module m ; filename : name of the output file (lint
        waiver if it is not the name of the module)
        """
        self.ports = {p.name: p for p in m.ports if isinstance(p, Port)}
        waivers    = []
        if filename and os.path.splitext(os.path.basename(filename))[0] != m.name:
            waivers.append("DECLFILENAME")
        if has_open_port(m.stmts):
            waivers.append("PINCONNECTEMPTY")

        lines = self.header_lines(m.header)
        lines+= [f"// verilator lint_off {w}" for w in waivers]
        lines.append(f"module {m.name}")
        lines+= self.module_imports(m)
        if m.generics:
            for i, g in enumerate(m.generics):
                default = g.default if g.default is not None else (StrConst("") if isinstance(g.type, String) else IntConst(0))
                lines.append(f"  {'#(' if i == 0 else ' ,'}parameter {self.param_type(g.type)}{g.name} = {self.expr(default)}{self.comment_tail(g.comment)}")
            lines.append("   )")
        lines.append("  (")
        first = True
        for p in self.module_ports(m):
            if isinstance(p, Comment):
                lines += self.comment(p, "    ")
                continue
            direction = "input " if p.direction == "in" else "output"
            lines.append(f"   {' ' if first else ','}{direction} {self.port_type(p.type)}{p.name}{self.comment_tail(p.comment)}")
            first = False
        lines.append("   );")
        lines.append("")

        lines += self.module_constants(m)
        lines += self.decls(m.decls, INDENT)
        lines.append("")
        lines += self.stmts(m.stmts, INDENT)
        lines.append("")
        lines.append("endmodule")
        lines += [f"// verilator lint_on {w}" for w in waivers]
        return "\n".join(lines) + "\n"

    #------------------------------------
    def package(self, p):
        """Text of the header of the package p : `define of its constants"""
        guard = f"{p.name.upper()}_VH"
        lines = self.header_lines(p.header)
        lines+= [f"`ifndef {guard}", f"`define {guard}", ""]
        for item in p.items:
            if isinstance(item, Comment):
                lines += self.comment(item, "")
            elif isinstance(item, Constant):
                lines.append(f"`define {item.name} {self.expr(item.value)}{self.comment_tail(item.comment)}")
            elif item is None or item == "":
                lines.append("")
        lines += ["", f"`endif // {guard}"]
        return "\n".join(lines) + "\n"

#============================================
# Functions
#============================================

#--------------------------------------------
def verilog_range(t, ctx=None):
    return VerilogWriter(ctx).range(t)

#--------------------------------------------
def verilog_expr(e, ctx=None):
    """Verilog expression ; ctx : ports of the module (flattened records)"""
    return VerilogWriter(ctx).expr(e)

#--------------------------------------------
def verilog_decls(decls, indent, ctx=None):
    return VerilogWriter(ctx).decls(decls, indent)

#--------------------------------------------
def verilog_stmts(stmts, indent, ctx=None, depth=0):
    return VerilogWriter(ctx).stmts(stmts, indent, depth)

#--------------------------------------------
def verilog_header(p):
    """Text of the header of the package p : `define of its constants"""
    return VerilogWriter().package(p)

#--------------------------------------------
def verilog_module(m, filename=None):
    """Text of the module m"""
    return VerilogWriter().module(m, filename)

#--------------------------------------------
def write_verilog_header(p, output_path):
    with open(output_path, 'w') as file:
        file.write(verilog_header(p))

#--------------------------------------------
def write_verilog_module(m, output_path):
    with open(output_path, 'w') as file:
        file.write(verilog_module(m, output_path))
