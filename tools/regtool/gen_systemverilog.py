"""
Module gen_systemverilog.py
Generic SystemVerilog (IEEE 1800-2012) writer : writes a module or a
package described with hdl_model (independent of the CSR, see gen_hdl.py
for the CSR). Derived from the Verilog writer (gen_verilog.VerilogWriter) :

- types : logic, logic [msb:0], int, bit, string ; boolean parameter :
  untyped (an integer value does not need a cast)
- a record is a packed struct (typedef struct packed) declared in the
  package ; a port of a record type keeps its type, a reference to a
  record element is <port>.<field>...
- the package declares its constants (localparam) and its structs, the
  module imports it (import <package>::*)
- an element of a record input port is read with a size cast (iverilog 12
  gets the width of a member of a struct port wrong)
- VHDL only items are ignored : Use, Component, library of an instance, Cast
"""

import os

from gen_verilog import VerilogWriter, INDENT
from hdl_model   import *

#============================================
# Writer
#============================================

class SystemVerilogWriter(VerilogWriter):
    """SystemVerilog writer"""

    #====================================
    # Types and references
    #====================================

    #------------------------------------
    def type(self, t, what):
        """Type ("logic [7:0] ", "int ", "demo_t ", ...) ; what : for the error message"""
        if isinstance(t, Bit):
            return "logic "
        if isinstance(t, Vector):
            return f"logic {self.range(t)}"
        if isinstance(t, Integer):
            return "int "
        if isinstance(t, Boolean):
            return "bit "
        if isinstance(t, String):
            return "string "
        if isinstance(t, RecordType):
            return f"{t.name} "
        raise ValueError(f"{what} : type {t.name if isinstance(t, ExternalType) else t} has no SystemVerilog equivalent")

    #------------------------------------
    def signal_type(self, t):
        if isinstance(t, (Bit, Vector)):
            return "logic", self.range(t)
        return self.type(t, "Signal").strip(), ""

    #------------------------------------
    def constant_type(self, t):
        return "localparam", self.type(t, "Constant")

    #------------------------------------
    def port_type(self, t):
        return self.type(t, "Port")

    #------------------------------------
    def param_type(self, t):
        if isinstance(t, (ExternalType, Boolean)):
            return ""                           # parameter of a VHDL type, boolean : untyped
        return self.type(t, "Parameter")

    #------------------------------------
    def ref(self, e):
        """Reference ; record element : <name>.<field>..."""
        return ".".join([e.name, *e.path])

    #------------------------------------
    def input_element_type(self, e):
        """Type of the element of a record input port referenced by e, or None"""
        port = self.ports.get(e.name) if isinstance(e, Ref) and e.path else None
        if port is None or port.direction != "in":
            return None
        t = port.type
        for name in e.path:
            if not isinstance(t, RecordType):
                return None
            t = next((f.type for f in t.fields if f.name == name), None)
        return t

    #------------------------------------
    def expr(self, e):
        """
        Expression ; an element of a record input port (always read) has a
        size cast : iverilog 12 gets the width of a member of a struct port
        wrong (concatenation, port connection)
        """
        t = self.input_element_type(e)
        if isinstance(t, (Bit, Vector)):
            width = 1 if isinstance(t, Bit) else t.width
            size  = str(width) if isinstance(width, int) else f"({super().expr(width)})"
            return f"{size}'({self.ref(e)})"
        return super().expr(e)

    #====================================
    # Declarations
    #====================================

    #------------------------------------
    def decl(self, d, indent, width=0, name=0):
        if isinstance(d, RecordType):
            return self.struct(d, indent)
        return super().decl(d, indent, width, name)

    #------------------------------------
    def struct(self, r, indent):
        """typedef struct packed of a record (first field : most significant bits)"""
        types = [self.type(f.type, f"Field {r.name}.{f.name}") for f in r.fields]
        width = max(len(t) for t in types)
        names = max(len(f.name) for f in r.fields) + 1
        lines = self.comment(Comment([r.comment]), indent) if r.comment else []
        lines.append(f"{indent}typedef struct packed {{")
        for f, t in zip(r.fields, types):
            field = f"{f.name};"
            lines.append(f"{indent}  {t:<{width}}{field:<{names}}{self.comment_tail(f.comment)}".rstrip())
        lines.append(f"{indent}}} {r.name};")
        lines.append("")
        return lines

    #====================================
    # Units
    #====================================

    #------------------------------------
    def module_ports(self, m):
        """Ports of the module, records kept"""
        for p in m.ports:
            if isinstance(p, Port):
                self.port_type(p.type)          # Error if no SystemVerilog type
        return m.ports

    #------------------------------------
    def module_imports(self, m):
        return [f"  import {p.name}::*;" for p in m.imports if isinstance(p, Package)]

    #------------------------------------
    def module_constants(self, m):
        return []                               # imported

    #------------------------------------
    def package(self, p, filename=None):
        """
        Text of the package p : constants and structs ; filename : name of
        the output file (lint waiver if it is not the name of the package).
        The constants are an interface for the users : unused ones are not
        a lint warning.
        """
        waivers = ["UNUSEDPARAM"]
        if filename and os.path.splitext(os.path.basename(filename))[0] != p.name:
            waivers.append("DECLFILENAME")
        lines = self.header_lines(p.header)
        lines+= [f"// verilator lint_off {w}" for w in waivers]
        lines.append(f"package {p.name};")
        lines.append("")
        lines+= self.decls(p.items, INDENT)
        lines.append("")
        lines.append(f"endpackage : {p.name}")
        lines+= [f"// verilator lint_on {w}" for w in waivers]
        return "\n".join(lines) + "\n"

#============================================
# Functions
#============================================

#--------------------------------------------
def sv_expr(e):
    return SystemVerilogWriter().expr(e)

#--------------------------------------------
def sv_package(p, filename=None):
    """Text of the package p"""
    return SystemVerilogWriter().package(p, filename)

#--------------------------------------------
def sv_module(m, filename=None):
    """Text of the module m"""
    return SystemVerilogWriter().module(m, filename)

#--------------------------------------------
def write_sv_package(p, output_path):
    with open(output_path, 'w') as file:
        file.write(sv_package(p, output_path))

#--------------------------------------------
def write_sv_module(m, output_path):
    with open(output_path, 'w') as file:
        file.write(sv_module(m, output_path))
