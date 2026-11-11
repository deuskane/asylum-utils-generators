"""
Module hdl_model.py
Generic description of a HDL package and of a HDL module, independent of the
language and of the CSR : written by the generic writers gen_vhdl.py and
gen_verilog.py, built by gen_hdl.py.

- Types       : Bit, Vector, Integer, Boolean, String, RecordType, ExternalType
- Expressions : Ref, BitConst, VecConst, IntConst, BoolConst, StrConst, Fill,
                Slice, Index, Concat, Not, And, Or, Eq, BoolOr, Truth, Cast,
                Arith, Raw
- Declarations: Signal, Constant, Comment
- Statements  : Assign, CondAssign, Instance, IfGenerate, Comment
- Units       : Generic, Port, Package (Use, Component), Module
"""

from dataclasses import dataclass, field as _field
from typing      import Any, List, Optional, Tuple, Union

#============================================
# Types
#============================================

#--------------------------------------------
@dataclass
class Bit:
    """Single bit (VHDL std_logic, Verilog wire)"""

#--------------------------------------------
@dataclass
class Vector:
    """Bit vector [width-1:0] ; width : int or expression ; kind : "slv" or "unsigned" (VHDL)"""
    width : Any
    kind  : str = "slv"

#--------------------------------------------
@dataclass
class Integer:
    """Integer (VHDL natural / integer / positive, Verilog untyped parameter)"""
    kind  : str = "natural"

#--------------------------------------------
@dataclass
class Boolean:
    """Boolean (Verilog : 0 / 1)"""

#--------------------------------------------
@dataclass
class String:
    """Character string (generics / parameters)"""

#--------------------------------------------
@dataclass
class RecordField:
    name    : str
    type    : Any
    comment : str = ""

#--------------------------------------------
@dataclass
class RecordType:
    """
    Record (VHDL record type, declared in a package).
    The Verilog writer flattens a port of a record type in one port per
    field : <port prefix>_<field>[_<subfield>...]<port suffix>
    """
    name    : str
    fields  : List[RecordField]
    comment : str = ""

#--------------------------------------------
@dataclass
class ExternalType:
    """Type declared outside the generated files (VHDL only, ex : sbi_ini_t)"""
    name    : str

#============================================
# Expressions
#============================================

#--------------------------------------------
@dataclass
class Ref:
    """Reference to a signal, port, constant or generic ; path : record elements"""
    name : str
    path : Tuple[str, ...] = ()

#--------------------------------------------
@dataclass
class BitConst:
    """Bit constant 0 / 1"""
    value : int

#--------------------------------------------
@dataclass
class VecConst:
    """Vector constant of an integer width"""
    value : int
    width : int

#--------------------------------------------
@dataclass
class IntConst:
    value : int

#--------------------------------------------
@dataclass
class BoolConst:
    value : bool

#--------------------------------------------
@dataclass
class StrConst:
    value : str

#--------------------------------------------
@dataclass
class Fill:
    """Vector of width bits, all at bit (VHDL (others => bit) outside a concatenation)"""
    bit   : int
    width : Any

#--------------------------------------------
@dataclass
class Slice:
    """expr[msb:lsb]"""
    expr : Any
    msb  : Any
    lsb  : Any

#--------------------------------------------
@dataclass
class Index:
    """expr[index]"""
    expr  : Any
    index : Any

#--------------------------------------------
@dataclass
class Concat:
    """Concatenation, most significant part first"""
    parts : List[Any]

#--------------------------------------------
@dataclass
class Not:
    """Bitwise not"""
    expr : Any

#--------------------------------------------
@dataclass
class And:
    """Bitwise and"""
    exprs : List[Any]

#--------------------------------------------
@dataclass
class Or:
    """Bitwise or"""
    exprs : List[Any]

#--------------------------------------------
@dataclass
class Eq:
    """Condition left = right"""
    left  : Any
    right : Any

#--------------------------------------------
@dataclass
class BoolOr:
    """Condition c0 or c1 ..."""
    conds : List[Any]

#--------------------------------------------
@dataclass
class Truth:
    """Condition from a boolean expression (boolean generic, BoolConst)"""
    expr : Any

#--------------------------------------------
@dataclass
class Cast:
    """Conversion between vector kinds (VHDL unsigned() / std_logic_vector())"""
    expr : Any
    kind : str

#--------------------------------------------
@dataclass
class Arith:
    """Integer arithmetic left op right (op : + - * /)"""
    op    : str
    left  : Any
    right : Any

#--------------------------------------------
@dataclass
class Raw:
    """Text copied as is in every language"""
    text : str

#============================================
# Declarations and statements
#============================================

#--------------------------------------------
@dataclass
class Comment:
    """Comment lines ; banner : between two lines of ="""
    lines  : List[str]
    banner : bool = False

#--------------------------------------------
@dataclass
class Signal:
    """Signal / wire ; unused_ok : some bits are not used (lint waiver)"""
    name      : str
    type      : Any
    comment   : str  = ""
    unused_ok : bool = False

#--------------------------------------------
@dataclass
class Constant:
    """Constant (VHDL constant, Verilog localparam / `define in a header)"""
    name    : str
    type    : Any
    value   : Any
    comment : str = ""

#--------------------------------------------
@dataclass
class Assign:
    """Concurrent assignment target <= expr"""
    target : Any
    expr   : Any

#--------------------------------------------
@dataclass
class CondAssign:
    """target <= expr0 when cond0 else expr1 when cond1 ... else default"""
    target  : Any
    choices : List[Tuple[Any, Any]]
    default : Any

#--------------------------------------------
@dataclass
class Instance:
    """
    Instance of module (VHDL : component of a used package if library is
    None, else entity <library>.<module>) ; port actual None : open
    """
    module   : str
    name     : str
    generics : List[Tuple[str, Any]] = _field(default_factory=list)
    ports    : List[Tuple[str, Any]] = _field(default_factory=list)
    library  : Optional[str]         = None

#--------------------------------------------
@dataclass
class IfGenerate:
    """Conditional block (else block named <name>_b), with local declarations"""
    name       : str
    cond       : Any
    decls      : List[Any] = _field(default_factory=list)
    stmts      : List[Any] = _field(default_factory=list)
    else_decls : List[Any] = _field(default_factory=list)
    else_stmts : List[Any] = _field(default_factory=list)

#============================================
# Units
#============================================

#--------------------------------------------
@dataclass
class Generic:
    """Generic / parameter ; default None : mandatory (Verilog : 0)"""
    name    : str
    type    : Any
    default : Any = None
    comment : str = ""

#--------------------------------------------
@dataclass
class Port:
    """
    Port ; a port of a record type is flattened by the Verilog writer in
    <prefix>_<field>...<suffix> (prefix / suffix : name without / with its
    direction suffix, ex : "sw2hw" / "_o" for "sw2hw_o")
    """
    name      : str
    direction : str                    # "in" / "out"
    type      : Any
    comment   : str = ""
    prefix    : Optional[str] = None
    suffix    : str = ""

    def flat_name(self, path):
        """Name of the Verilog port of the record element path"""
        prefix = self.prefix if self.prefix is not None else self.name
        return "_".join([prefix, *path]) + self.suffix

#--------------------------------------------
@dataclass
class Use:
    """VHDL context clause (library.package.all) of a package not generated"""
    library : str
    package : str

#--------------------------------------------
@dataclass
class Component:
    """Component declaration of a module (VHDL package)"""
    module : Any

#--------------------------------------------
@dataclass
class Package:
    """
    Package : constants, record types, components. The Verilog writer
    writes the constants in a header (`define) and copies them as
    localparam in the modules that import the package.
    """
    name    : str
    library : str
    items   : List[Any] = _field(default_factory=list)
    uses    : List[Any] = _field(default_factory=list)
    header  : List[str] = _field(default_factory=list)

#--------------------------------------------
@dataclass
class Module:
    """
    Module / entity with one architecture ; imports : packages (Package :
    generated, Use : external, VHDL only) ; ports : Port or Comment
    """
    name     : str
    generics : List[Generic]   = _field(default_factory=list)
    ports    : List[Any]       = _field(default_factory=list)
    decls    : List[Any]       = _field(default_factory=list)
    stmts    : List[Any]       = _field(default_factory=list)
    imports  : List[Any]       = _field(default_factory=list)
    header   : List[str]       = _field(default_factory=list)

    def port(self, name):
        """Port of this name, or None"""
        return next((p for p in self.ports if isinstance(p, Port) and p.name == name), None)
