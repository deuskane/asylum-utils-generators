"""
Module gen_hdl.py
HDL generator of regtool : builds the package and the module of the CSR
(hdl_model) from the CSR model (csr_model), then writes them with the
generic writer of the language (gen_vhdl.py, gen_verilog.py or
gen_systemverilog.py).

Verilog : <name>_csr_pkg.vh (`define of the package constants) and
<name>_csr.v ; SystemVerilog : <name>_csr_pkg.sv (package : constants,
sw2hw / hw2sw packed structs) and <name>_csr.sv ; interfaces mem, apb,
axi4lite (sbi / pbi are VHDL records).

Package <name>_csr_pkg : widths, register addresses, sw2hw / hw2sw records,
                         enum constants, component <name>_registers
Module  <name>_registers : bus (memory interface, or a bus through the
                         bridge <interface>2mem), address decode, read
                         multiplexer, one building block csr_<hwtype> per
                         register (hdl/), hardware side sw2hw_o / hw2sw_i
"""

import re

from   csr_model import parse_value, parse_init_value
from   hdl_model import *
import gen_vhdl
import gen_verilog
import gen_systemverilog

# Writers of each language : (package, module)
WRITERS            = {
    'vhdl'          : (gen_vhdl.write_vhdl_package       , gen_vhdl.write_vhdl_module       ),
    'verilog'       : (gen_verilog.write_verilog_header  , gen_verilog.write_verilog_module ),
    'systemverilog' : (gen_systemverilog.write_sv_package, gen_systemverilog.write_sv_module),
}

LANGUAGES          = list(WRITERS.keys())

# Interfaces of the bus types defined in a VHDL package (no Verilog)
RECORD_INTERFACES  = ['sbi','pbi']

#============================================
# hjson expressions and types (VHDL syntax)
#============================================

#--------------------------------------------
def parse_expr(text):
    """
    Expression of the hjson (field expr, enable, FIFO params, in VHDL
    syntax) : boolean, bit string "0101", integer, identifier,
    identifier(msb downto lsb), else copied as is (Raw)
    """
    text = str(text).strip()
    if text.lower() in ['true', 'false']:
        return BoolConst(text.lower() == 'true')
    m = re.fullmatch(r'"([01]+)"', text)
    if m:
        return VecConst(int(m.group(1), 2), len(m.group(1)))
    if re.fullmatch(r'\d+', text):
        return IntConst(int(text))
    if re.fullmatch(r'[A-Za-z]\w*', text):
        return Ref(text)
    m = re.fullmatch(r'([A-Za-z]\w*)\s*\(\s*(\w+)\s+downto\s+(\w+)\s*\)', text, re.I)
    if m:
        msb, lsb = [int(x) if x.isdigit() else Ref(x) for x in m.group(2, 3)]
        return Slice(Ref(m.group(1)), msb, lsb)
    return Raw(text)

#--------------------------------------------
def parse_type(text):
    """Type of a hjson parameter (VHDL type name)"""
    t = text.strip().lower()
    if t == 'boolean':
        return Boolean()
    if t in ['natural', 'integer', 'positive']:
        return Integer(t)
    if t == 'string':
        return String()
    if t == 'std_logic':
        return Bit()
    m = re.fullmatch(r'std_logic_vector\s*\(\s*(\d+)\s+downto\s+(\d+)\s*\)', t)
    if m:
        return Vector(int(m.group(1)) - int(m.group(2)) + 1)
    return ExternalType(text.strip())

#============================================
# Names
#============================================

#--------------------------------------------
def check_language(csr, language):
    """
    Checks that the csr can be generated in the language

    :raises ValueError: unknown language, or bus defined by VHDL records in Verilog
    """
    if language not in LANGUAGES:
        raise ValueError(f"language '{language}' must be in {LANGUAGES}.")
    if language != 'vhdl' and csr['interface'] in RECORD_INTERFACES:
        raise ValueError(f"interface '{csr['interface']}' is not supported in {language} (VHDL records).")

#--------------------------------------------
def addr_width(csr, language):
    """Address width (at least 1 bit in Verilog)"""
    return csr['size_addr'] if language == 'vhdl' else max(1, csr['size_addr'])

#--------------------------------------------
def const_name(csr, *names):
    """Name of a constant of the package : <NAME>_<...>"""
    return "_".join([csr['name'].upper()] + [n.upper() for n in names])

#--------------------------------------------
def init_name(reg, field=None):
    """Name of the reset value constant of a register / field"""
    return f"INIT_{reg['name']}" + (f"_{field['name']}" if field else "")

#--------------------------------------------
def csr_header(csr):
    return [f"Module      : {csr['name']}",
            f"Description : {csr['desc']}",
            f"Width       : {csr['width']}"]

#--------------------------------------------
def reg_header(reg):
    return Comment([f"Register    : {reg['name']}",
                    f"Description : {reg['desc']}",
                    f"Address     : 0x{reg['address']:X}",
                    f"Width       : {reg['width']}",
                    f"Sw Access   : {reg['swaccess']}",
                    f"Hw Access   : {reg['hwaccess']}",
                    f"Hw Type     : {reg['hwtype']}"], banner=True)

#============================================
# Hardware side records
#============================================

#--------------------------------------------
def sw2hw_items(reg):
    """Items of the sw2hw record of a register : (name, type, comment)"""
    items = []
    if reg['sw2hw_re']:
        items.append((reg['sw2hw_name_re'], Bit(), "Software read"))
    if reg['sw2hw_we']:
        items.append((reg['sw2hw_name_we'], Bit(), "Software write"))
    if reg['sw2hw_data']:
        items += [(f['name'], Vector(f['width']), f['desc']) for f in reg['fields']]
        if reg['hwtype'] in ['fifo']:
            items += [("sw2hw_empty", Bit(), "FIFO sw2hw empty"), ("sw2hw_full", Bit(), "FIFO sw2hw full")]
    if reg['hw2sw_data'] and reg['hwtype'] in ['fifo']:
        items += [("hw2sw_empty", Bit(), "FIFO hw2sw empty"), ("hw2sw_full", Bit(), "FIFO hw2sw full")]
    return items

#--------------------------------------------
def hw2sw_items(reg):
    """Items of the hw2sw record of a register : (name, type, comment)"""
    items = []
    if reg['hw2sw_re']:
        items.append((reg['hw2sw_name_re'], Bit(), "Hardware read"))
    if reg['hw2sw_we']:
        items.append((reg['hw2sw_name_we'], Bit(), "Hardware write"))
    if reg['hw2sw_data']:
        items += [(f['name'], Vector(f['width']), f['desc']) for f in reg['fields']]
    return items

#--------------------------------------------
def records(csr):
    """Record types (sw2hw_t, hw2sw_t) of the csr : (register records, sw2hw_t, hw2sw_t)"""
    module   = csr['name']
    regs     = {}
    sw2hw    = []
    hw2sw    = []
    for reg in csr['registers']:
        r = reg['name']
        if reg['sw2hw']:
            rec = RecordType(f"{module}_{r}_sw2hw_t", [RecordField(*i) for i in sw2hw_items(reg)])
            regs[(r, 'sw2hw')] = rec
            sw2hw.append(RecordField(r, rec))
        if reg['hw2sw']:
            rec = RecordType(f"{module}_{r}_hw2sw_t", [RecordField(*i) for i in hw2sw_items(reg)])
            regs[(r, 'hw2sw')] = rec
            hw2sw.append(RecordField(r, rec))
    sw2hw_t = RecordType(f"{module}_sw2hw_t", sw2hw, "Software to hardware") if sw2hw else None
    hw2sw_t = RecordType(f"{module}_hw2sw_t", hw2sw, "Hardware to software") if hw2sw else None
    return regs, sw2hw_t, hw2sw_t

#============================================
# Ports
#============================================

#--------------------------------------------
def bus_ports(csr, language):
    """Ports of the bus : (name, direction, type)"""
    addr = Vector(addr_width(csr, language))
    data = Vector(csr['width'])
    ports = {
        'mem'      : [("cs_i"           , "in" , Bit()),
                      ("re_i"           , "in" , Bit()),
                      ("we_i"           , "in" , Bit()),
                      ("addr_i"         , "in" , addr),
                      ("wdata_i"        , "in" , data),
                      ("rdata_o"        , "out", data),
                      ("busy_o"         , "out", Bit())],
        'pbi'      : [("pbi_ini_i"      , "in" , ExternalType("pbi_ini_t")),
                      ("pbi_tgt_o"      , "out", ExternalType("pbi_tgt_t"))],
        'sbi'      : [("sbi_ini_i"      , "in" , ExternalType("sbi_ini_t")),
                      ("sbi_tgt_o"      , "out", ExternalType("sbi_tgt_t"))],
        'apb'      : [("s_apb_psel_i"   , "in" , Bit()),
                      ("s_apb_penable_i", "in" , Bit()),
                      ("s_apb_pwrite_i" , "in" , Bit()),
                      ("s_apb_paddr_i"  , "in" , addr),
                      ("s_apb_pwdata_i" , "in" , data),
                      ("s_apb_prdata_o" , "out", data),
                      ("s_apb_pready_o" , "out", Bit()),
                      ("s_apb_pslverr_o", "out", Bit())],
        'axi4lite' : [("s_axi_awvalid_i", "in" , Bit()),
                      ("s_axi_awready_o", "out", Bit()),
                      ("s_axi_awaddr_i" , "in" , addr),
                      ("s_axi_wvalid_i" , "in" , Bit()),
                      ("s_axi_wready_o" , "out", Bit()),
                      ("s_axi_wdata_i"  , "in" , data),
                      ("s_axi_wstrb_i"  , "in" , Vector(max(1, csr['width']//8))),
                      ("s_axi_bvalid_o" , "out", Bit()),
                      ("s_axi_bready_i" , "in" , Bit()),
                      ("s_axi_bresp_o"  , "out", Vector(2)),
                      ("s_axi_arvalid_i", "in" , Bit()),
                      ("s_axi_arready_o", "out", Bit()),
                      ("s_axi_araddr_i" , "in" , addr),
                      ("s_axi_rvalid_o" , "out", Bit()),
                      ("s_axi_rready_i" , "in" , Bit()),
                      ("s_axi_rdata_o"  , "out", data),
                      ("s_axi_rresp_o"  , "out", Vector(2))],
    }
    return ports[csr['interface']]

#============================================
# Package
#============================================

#--------------------------------------------
def build_package(csr, language='vhdl'):
    """Package <name>_csr_pkg (Package of hdl_model)"""
    module = csr['name']
    aw     = addr_width(csr, language)
    regs, sw2hw_t, hw2sw_t = records(csr)
    addr_t = Vector(Ref(const_name(csr, 'ADDR_WIDTH')), 'unsigned')

    items  = [Comment(["Global Constants"], banner=True),
              Constant(const_name(csr, 'ADDR_WIDTH'), Integer(), IntConst(aw)),
              Constant(const_name(csr, 'DATA_WIDTH'), Integer(), IntConst(csr['width'])),
              ""]

    for reg in csr['registers']:
        r = reg['name']
        items.append(reg_header(reg))
        value = VecConst(reg['address'], aw) if aw > 0 else Fill(0, addr_t.width)
        items.append(Constant(const_name(csr, r), addr_t, value))
        items.append("")
        for kind in ['sw2hw', 'hw2sw']:
            if (r, kind) in regs:
                items.append(regs[(r, kind)])
        for field in reg['fields']:
            for enum in field.get('enum', []):
                value = parse_value(enum['value'])
                name  = const_name(csr, r, field['name'], enum['name'])
                items.append(Comment([f"Enum        : {r}.{field['name']}.{enum['name']} : {enum['desc']}"]))
                items.append(Constant(name         , Vector(field['width']), VecConst(value, field['width'])))
                items.append(Constant(name + "_RAW", Vector(csr['width'])  , VecConst(value << field['lsb'], csr['width'])))
                items.append("")

    items.append(Comment([f"Structure {module}_t"], banner=True))
    items += [t for t in [sw2hw_t, hw2sw_t] if t]

    uses   = []
    if csr['interface'] in RECORD_INTERFACES:
        uses.append(Use(csr.get('logical_name', 'work'), f"{csr['interface']}_pkg"))

    package = Package(f"{module}_csr_pkg", csr.get('logical_name', 'work'), items, uses,
                      header=[f"Generated by regtool : package of {module}", ""] + csr_header(csr))
    package.items += [Comment(["Component"], banner=True), Component(build_interface(csr, language))]
    return package

#============================================
# Module
#============================================

#--------------------------------------------
def build_interface(csr, language='vhdl'):
    """Module <name>_registers without architecture (generics and ports)"""
    _, sw2hw_t, hw2sw_t = records(csr)

    generics = []
    if csr['interface'] == 'sbi':
        generics.append(Generic("MODULE_NAME", String(), StrConst(""), f"Name of the module (\"{csr['name']}\" if empty)"))
    for param in csr['parameters']:
        generics.append(Generic(param['name'], parse_type(param['type']), None, param['desc']))

    ports  = [Comment(["Clock and Reset"]),
              Port("clk_i"   , "in", Bit(), "Clock"),
              Port("arst_b_i", "in", Bit(), "Asynchronous reset active low"),
              Comment(["Bus"])]
    ports += [Port(name, direction, t) for name, direction, t in bus_ports(csr, language)]
    ports.append(Comment(["CSR"]))
    if sw2hw_t:
        ports.append(Port("sw2hw_o", "out", sw2hw_t, "Software to hardware", prefix="sw2hw", suffix="_o"))
    if hw2sw_t:
        ports.append(Port("hw2sw_i", "in" , hw2sw_t, "Hardware to software", prefix="hw2sw", suffix="_i"))

    return Module(f"{csr['name']}_registers", generics, ports)

#--------------------------------------------
def bus_data(csr, reg, source):
    """Bus data from the packed register data : fields at their position, 0 elsewhere"""
    packed = []
    lsb    = 0
    for field in reg['fields']:
        packed.append((field, lsb))
        lsb += field['width']

    parts = []
    bit   = csr['width']
    for field, plsb in sorted(packed, key=lambda item: item[0]['lsb'], reverse=True):
        if bit > field['msb']+1:
            parts.append(Fill(0, bit-field['msb']-1))
        parts.append(Slice(Ref(source), plsb+field['width']-1, plsb))
        bit = field['lsb']
    if bit > 0:
        parts.append(Fill(0, bit))
    return Concat(parts)

#--------------------------------------------
def packed_data(reg, source):
    """Packed register data (fields from bit 0, in the order of the hjson) from the bus data"""
    return Concat([Slice(Ref(source), f['msb'], f['lsb']) for f in reversed(reg['fields'])])

#--------------------------------------------
def field_init(field):
    """Reset value of a field : init, or the expression expr"""
    if field['expr'] == f"\"{parse_init_value(field['init'],field['width'])}\"":
        return VecConst(field['init'], field['width'])
    return parse_expr(field['expr'])

#--------------------------------------------
def one(signal):
    """Condition signal = '1'"""
    return Eq(Ref(signal), BitConst(1))

#--------------------------------------------
def build_register(csr, reg):
    """Declarations and statements of a register : (decls, stmts)"""
    r      = reg['name']
    rw     = reg['width']
    data_t = Vector(Ref(const_name(csr, 'DATA_WIDTH')))

    sw2hw  = lambda item: Ref("sw2hw_o", (r, item))
    hw2sw  = lambda item: Ref("hw2sw_i", (r, item))

    # Reset values of the fields (used by the instance and by a disabled register)
    need_init = reg['hwtype'] in ['reg'] or reg['sw2hw_data']
    decls  = [reg_header(reg)]
    if need_init:
        decls += [Constant(init_name(reg, f), Vector(f['width']), field_init(f)) for f in reg['fields']]
    decls += [Signal(f"{r}_wcs"  , Bit()),
              Signal(f"{r}_wbusy", Bit()),
              Signal(f"{r}_rcs"  , Bit()),
              Signal(f"{r}_rbusy", Bit()),
              Signal(f"{r}_rdata", data_t),
              ""]

    #------------------------------------
    # Enabled register
    #------------------------------------
    gen_decls = []
    if reg['hwtype'] in ['reg']:
        inits = [Ref(init_name(reg, f)) for f in reversed(reg['fields'])]
        gen_decls.append(Constant(init_name(reg), Vector(rw), inits[0] if len(inits) == 1 else Concat(inits)))
    gen_decls += [Signal(f"{r}_re", Bit()), Signal(f"{r}_we", Bit()), Signal(f"{r}_wdata_sw", Vector(rw))]
    if reg['hw2sw_data']:
        gen_decls.append(Signal(f"{r}_wdata_hw", Vector(rw)))
    if reg['sw2hw_re']:
        gen_decls.append(Signal(f"{r}_rdata_sw", Vector(rw)))
    if reg['sw2hw_data']:
        gen_decls.append(Signal(f"{r}_rdata_hw", Vector(rw)))

    gen = []
    # Software read
    if reg['sw2hw_re']:
        gen += [CondAssign(Ref(f"{r}_rcs"), [(Eq(Ref("sig_raddr"), Ref(const_name(csr, r))), BitConst(1))], BitConst(0)),
                Assign(Ref(f"{r}_re"), And([Ref("sig_rcs"), Ref("sig_re"), Ref(f"{r}_rcs")])),
                Assign(Ref(f"{r}_rdata"), bus_data(csr, reg, f"{r}_rdata_sw"))]
    else:
        gen += [Assign(Ref(f"{r}_rcs"), BitConst(0)),
                Assign(Ref(f"{r}_re"), BitConst(0)),
                Assign(Ref(f"{r}_rdata"), Fill(0, data_t.width))]

    # Software write (own address and alias_write addresses)
    if reg['sw2hw_we']:
        conds = [Eq(Ref("sig_waddr"), Ref(const_name(csr, waddr))) for waddr in reg['address_write']]
        gen += [CondAssign(Ref(f"{r}_wcs"), [(conds[0] if len(conds) == 1 else BoolOr(conds), BitConst(1))], BitConst(0)),
                Assign(Ref(f"{r}_we"), And([Ref("sig_wcs"), Ref("sig_we"), Ref(f"{r}_wcs")])),
                Assign(Ref(f"{r}_wdata_sw"), packed_data(reg, "sig_wdata"))]
    else:
        gen += [Assign(Ref(f"{r}_wcs"), BitConst(0)),
                Assign(Ref(f"{r}_we"), BitConst(0)),
                Assign(Ref(f"{r}_wdata_sw"), Fill(0, rw))]

    # Hardware side data
    if reg['hw2sw_data']:
        gen.append(Assign(Ref(f"{r}_wdata_hw"), Concat([hw2sw(f['name']) for f in reversed(reg['fields'])])))
    if reg['sw2hw_data']:
        lsb = 0
        for f in reg['fields']:
            gen.append(Assign(sw2hw(f['name']), Slice(Ref(f"{r}_rdata_hw"), lsb+f['width']-1, lsb)))
            lsb += f['width']

    # Building block
    hw_re = hw2sw(reg['hw2sw_name_re']) if reg['hw2sw_re']   else BitConst(1)
    hw_we = hw2sw(reg['hw2sw_name_we']) if reg['hw2sw_we']   else BitConst(0)
    sw_re = sw2hw(reg['sw2hw_name_re']) if reg['sw2hw_re']   else None
    sw_we = sw2hw(reg['sw2hw_name_we']) if reg['sw2hw_we']   else None
    hw_wd = Ref(f"{r}_wdata_hw")        if reg['hw2sw_data'] else Fill(0, rw)
    hw_rd = Ref(f"{r}_rdata_hw")        if reg['sw2hw_data'] else None

    generics = [("WIDTH", IntConst(rw))]
    if reg['hwtype'] in ['reg']:
        generics += [("INIT", Ref(init_name(reg))), ("MODEL", StrConst(reg['swaccess']))]
    if reg['hwtype'] in ['fifo']:
        generics += [(param, parse_expr(value)) for param, value in reg.get('params', {}).items()]

    ports = [("clk_i"     , Ref("clk_i")),
             ("arst_b_i"  , Ref("arst_b_i")),
             ("sw_wd_i"   , Ref(f"{r}_wdata_sw")),
             ("sw_rd_o"   , Ref(f"{r}_rdata_sw") if reg['sw2hw_re'] else None),
             ("sw_we_i"   , Ref(f"{r}_we")),
             ("sw_re_i"   , Ref(f"{r}_re")),
             ("sw_rbusy_o", Ref(f"{r}_rbusy")),
             ("sw_wbusy_o", Ref(f"{r}_wbusy"))]
    if reg['hwtype'] in ['reg', 'ext']:
        ports += [("hw_wd_i"   , hw_wd),
                  ("hw_rd_o"   , hw_rd),
                  ("hw_we_i"   , hw_we),
                  ("hw_sw_re_o", sw_re),
                  ("hw_sw_we_o", sw_we)]
    if reg['hwtype'] in ['fifo']:
        hw2sw_flags = reg['hw2sw_data']
        sw2hw_flags = reg['sw2hw_data']
        ports += [("hw_tx_valid_i", hw_we),
                  ("hw_tx_ready_o", sw_re),
                  ("hw_tx_data_i" , hw_wd),
                  ("hw_tx_empty_o", sw2hw("hw2sw_empty") if hw2sw_flags else None),
                  ("hw_tx_full_o" , sw2hw("hw2sw_full" ) if hw2sw_flags else None),
                  ("hw_rx_valid_o", sw_we),
                  ("hw_rx_ready_i", hw_re),
                  ("hw_rx_data_o" , hw_rd),
                  ("hw_rx_empty_o", sw2hw("sw2hw_empty") if sw2hw_flags else None),
                  ("hw_rx_full_o" , sw2hw("sw2hw_full" ) if sw2hw_flags else None)]
    gen.append(Instance(f"csr_{reg['hwtype']}", f"ins_{r}", generics, ports))

    #------------------------------------
    # Disabled register : no access, hardware side at the reset value
    #------------------------------------
    gen_b = [Assign(Ref(f"{r}_rcs")  , BitConst(0)),
             Assign(Ref(f"{r}_rbusy"), BitConst(0)),
             Assign(Ref(f"{r}_rdata"), Fill(0, data_t.width)),
             Assign(Ref(f"{r}_wcs")  , BitConst(0)),
             Assign(Ref(f"{r}_wbusy"), BitConst(0))]
    fields = {f['name'] : f for f in reg['fields']}
    for item, _, _ in sw2hw_items(reg) if reg['sw2hw'] else []:
        if item in fields:
            value = Ref(init_name(reg, fields[item]))
        elif item in ["sw2hw_empty", "hw2sw_empty"]:
            value = BitConst(1)
        else:
            value = BitConst(0)
        gen_b.append(Assign(sw2hw(item), value))

    enable = parse_expr(reg['enable'])
    stmts  = [reg_header(reg),
              IfGenerate(f"gen_{r}", Truth(enable), gen_decls, gen, [], gen_b),
              ""]
    return decls, stmts

#--------------------------------------------
def build_module(csr, package, language='vhdl'):
    """Module <name>_registers (Module of hdl_model)"""
    module = build_interface(csr, language)
    lib    = csr.get('logical_name', 'work')
    itf    = csr['interface']
    addr_t = Vector(Ref(const_name(csr, 'ADDR_WIDTH')))
    data_t = Vector(Ref(const_name(csr, 'DATA_WIDTH')))

    module.header  = [f"Generated by regtool : module of {csr['name']}", ""] + csr_header(csr)
    module.imports = [package, Use(lib, "csr_pkg")]
    if itf in RECORD_INTERFACES:
        module.imports.append(Use(lib, f"{itf}_pkg"))

    #------------------------------------
    # Bus : ports, or memory interface of the bridge
    #------------------------------------
    decls = []
    stmts = []
    if itf == 'mem':
        mem = {'cs': "cs_i", 're': "re_i", 'we': "we_i", 'addr': "addr_i", 'wdata': "wdata_i", 'rdata': "rdata_o", 'busy': "busy_o"}
    else:
        mem = {k: f"mem_{k}" for k in ['cs', 're', 'we', 'addr', 'wdata', 'rdata', 'busy']}
        bridge = f"{itf}2mem"
        decls += [Comment([f"Memory Interface of the bridge {bridge}"]),
                  Signal("mem_cs"   , Bit()),
                  Signal("mem_re"   , Bit()),
                  Signal("mem_we"   , Bit()),
                  Signal("mem_addr" , addr_t),
                  Signal("mem_wdata", data_t),
                  Signal("mem_rdata", data_t),
                  Signal("mem_busy" , Bit()),
                  ""]
        generics = [("ADDR_WIDTH", Ref(const_name(csr, 'ADDR_WIDTH'))),
                    ("DATA_WIDTH", Ref(const_name(csr, 'DATA_WIDTH')))]
        if itf == 'sbi':
            generics += [("NAME", Ref("MODULE_NAME")), ("DEFAULT_NAME", StrConst(csr['name']))]
        ports = [("clk_i", Ref("clk_i")), ("arst_b_i", Ref("arst_b_i"))] if itf == 'axi4lite' else []
        ports+= [(name, Ref(name)) for name, _, _ in bus_ports(csr, language)]
        ports+= [(f"{k}_{'i' if k in ['rdata', 'busy'] else 'o'}", Ref(v)) for k, v in mem.items()]
        stmts += [Comment([f"Bus Interface : bridge {bridge}"]),
                  Instance(bridge, f"ins_{bridge}", generics, ports, library=lib),
                  ""]

    decls += [Signal("sig_wcs"  , Bit()),
              Signal("sig_we"   , Bit()),
              Signal("sig_waddr", Vector(addr_t.width, 'unsigned')),
              Signal("sig_wdata", data_t, "Bits without field are not used", unused_ok=True),
              Signal("sig_wbusy", Bit()),
              "",
              Signal("sig_rcs"  , Bit()),
              Signal("sig_re"   , Bit()),
              Signal("sig_raddr", Vector(addr_t.width, 'unsigned')),
              Signal("sig_rdata", data_t),
              Signal("sig_rbusy", Bit()),
              "",
              Signal("sig_busy" , Bit()),
              ""]

    stmts += [Comment(["Interface"]),
              Assign(Ref("sig_wcs")  , Ref(mem['cs'])),
              Assign(Ref("sig_we")   , Ref(mem['we'])),
              Assign(Ref("sig_waddr"), Cast(Ref(mem['addr']), 'unsigned')),
              Assign(Ref("sig_wdata"), Ref(mem['wdata'])),
              "",
              Assign(Ref("sig_rcs")  , Ref(mem['cs'])),
              Assign(Ref("sig_re")   , Ref(mem['re'])),
              Assign(Ref("sig_raddr"), Cast(Ref(mem['addr']), 'unsigned')),
              Assign(Ref(mem['rdata']), Ref("sig_rdata")),
              Assign(Ref(mem['busy']) , Ref("sig_busy")),
              "",
              CondAssign(Ref("sig_busy"), [(one("sig_we"), Ref("sig_wbusy")), (one("sig_re"), Ref("sig_rbusy"))], BitConst(0)),
              ""]

    #------------------------------------
    # Registers
    #------------------------------------
    for reg in csr['registers']:
        reg_decls, reg_stmts = build_register(csr, reg)
        decls += reg_decls
        stmts += reg_stmts

    #------------------------------------
    # Busy and read data multiplexers (an unmapped address : no busy, reads 0)
    #------------------------------------
    regs   = [reg['name'] for reg in csr['registers']]
    stmts += [Comment(["Busy and read data (unmapped address : no busy, read 0)"]),
              CondAssign(Ref("sig_wbusy"), [(one(f"{r}_wcs"), Ref(f"{r}_wbusy")) for r in regs], BitConst(0)),
              CondAssign(Ref("sig_rbusy"), [(one(f"{r}_rcs"), Ref(f"{r}_rbusy")) for r in regs], BitConst(0)),
              CondAssign(Ref("sig_rdata"), [(one(f"{r}_rcs"), Ref(f"{r}_rdata")) for r in regs], Fill(0, data_t.width))]

    module.decls = decls
    module.stmts = stmts
    return module

#============================================
# Outputs
#============================================

#--------------------------------------------
def generate_hdl_package(csr, output_path, language='vhdl'):
    """Package of the csr in the language"""
    check_language(csr, language)
    package = build_package(csr, language)
    WRITERS[language][0](package, output_path)

#--------------------------------------------
def generate_hdl_module(csr, output_path, language='vhdl'):
    """Module of the csr in the language"""
    check_language(csr, language)
    package = build_package(csr, language)
    module  = build_module(csr, package, language)
    WRITERS[language][1](module, output_path)
