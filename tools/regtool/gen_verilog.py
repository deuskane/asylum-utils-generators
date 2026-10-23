"""
Module gen_verilog.py
Verilog generator of regtool : CSR module and header with the constants.

Same architecture as the VHDL module (gen_vhdl.py), with the Verilog
building blocks of hdl/ (csr_reg.v, csr_ext.v, csr_fifo.v, <bus>2mem.v).
The sw2hw / hw2sw records of the VHDL module are flattened in ports :
  sw2hw_<reg>_<item>_o / hw2sw_<reg>_<item>_i
Interfaces : mem, apb, axi4lite (sbi and pbi are VHDL records).
Field "expr", parameter types and FIFO "params" are VHDL : literals,
booleans, slices "(msb downto lsb)" and std_logic_vector types are
translated, other expressions are copied as is.
"""

import re
from   csr_model import parse_value, parse_init_value

VERILOG_INTERFACES = ['mem','apb','axi4lite']

#--------------------------------------------
#--------------------------------------------
def check_verilog(csr):
    """
    Checks that the csr can be generated in Verilog

    :param csr: Dictionary of csr
    :raises ValueError: If the interface has no Verilog bridge
    """
    if csr['interface'] not in VERILOG_INTERFACES:
        raise ValueError(f"interface '{csr['interface']}' is not supported by the Verilog generator (must be in {VERILOG_INTERFACES}).")

#--------------------------------------------
#--------------------------------------------
def verilog_expr(expr):
    """
    Translate a VHDL expression of the hjson in Verilog :
    boolean, bit string "0101", slice X(7 downto 0)

    :param expr: VHDL expression
    :return: Verilog expression
    """
    expr = expr.strip()

    if expr.lower() == 'true':
        return "1"
    if expr.lower() == 'false':
        return "0"

    bits = re.fullmatch(r'"([01]+)"', expr)
    if bits:
        return f"{len(bits.group(1))}'b{bits.group(1)}"

    return re.sub(r'\(\s*(\w+)\s+downto\s+(\w+)\s*\)', r'[\1:\2]', expr)

#--------------------------------------------
#--------------------------------------------
def verilog_range(width):
    """
    Range of a vector

    :param width: Width (int or Verilog expression)
    :return: "[width-1:0] " or "" for a single bit
    """
    if width == 1:
        return ""
    if isinstance(width, int):
        return f"[{width-1}:0] "
    return f"[{width}-1:0] "

#--------------------------------------------
#--------------------------------------------
def verilog_param_range(type):
    """
    Range of a parameter from its VHDL type (std_logic_vector(msb downto lsb))

    :param type: VHDL type of the hjson parameter
    :return: "[msb:lsb] " or ""
    """
    slv = re.fullmatch(r'\s*std_logic_vector\s*\(\s*(\w+)\s+downto\s+(\w+)\s*\)\s*', type, re.I)
    if slv:
        return f"[{slv.group(1)}:{slv.group(2)}] "
    return ""

#--------------------------------------------
#--------------------------------------------
def verilog_addr_width(csr):
    """Address width of the Verilog module (at least 1 bit)"""
    return max(1, csr['size_addr'])

#--------------------------------------------
#--------------------------------------------
def verilog_csr_ports(csr):
    """
    Hardware side ports (flattened sw2hw / hw2sw records of the VHDL module)

    :param csr: Dictionary of csr
    :return: List of (direction, width, name, register, item)
    """
    ports = []
    for reg in csr['registers']:
        r = reg['name']
        if reg['sw2hw']:
            if reg['sw2hw_re']:
                ports.append(("output", 1, f"sw2hw_{r}_{reg['sw2hw_name_re']}_o", reg, reg['sw2hw_name_re']))
            if reg['sw2hw_we']:
                ports.append(("output", 1, f"sw2hw_{r}_{reg['sw2hw_name_we']}_o", reg, reg['sw2hw_name_we']))
            if reg['sw2hw_data']:
                for field in reg['fields']:
                    ports.append(("output", field['width'], f"sw2hw_{r}_{field['name']}_o", reg, field['name']))
                if reg['hwtype'] in ['fifo']:
                    ports.append(("output", 1, f"sw2hw_{r}_sw2hw_empty_o", reg, "sw2hw_empty"))
                    ports.append(("output", 1, f"sw2hw_{r}_sw2hw_full_o" , reg, "sw2hw_full"))
            if reg['hw2sw_data']:
                if reg['hwtype'] in ['fifo']:
                    ports.append(("output", 1, f"sw2hw_{r}_hw2sw_empty_o", reg, "hw2sw_empty"))
                    ports.append(("output", 1, f"sw2hw_{r}_hw2sw_full_o" , reg, "hw2sw_full"))
        if reg['hw2sw']:
            if reg['hw2sw_re']:
                ports.append(("input" , 1, f"hw2sw_{r}_{reg['hw2sw_name_re']}_i", reg, reg['hw2sw_name_re']))
            if reg['hw2sw_we']:
                ports.append(("input" , 1, f"hw2sw_{r}_{reg['hw2sw_name_we']}_i", reg, reg['hw2sw_name_we']))
            if reg['hw2sw_data']:
                for field in reg['fields']:
                    ports.append(("input" , field['width'], f"hw2sw_{r}_{field['name']}_i", reg, field['name']))
    return ports

#--------------------------------------------
#--------------------------------------------
def verilog_bus_ports(csr):
    """
    Ports of the bus

    :param csr: Dictionary of csr
    :return: List of (direction, width, name)
    """
    addr = verilog_addr_width(csr)
    data = csr['width']
    ports = {
        'mem'      : [("input" , 1      , "cs_i"           ),
                      ("input" , 1      , "re_i"           ),
                      ("input" , 1      , "we_i"           ),
                      ("input" , addr   , "addr_i"         ),
                      ("input" , data   , "wdata_i"        ),
                      ("output", data   , "rdata_o"        ),
                      ("output", 1      , "busy_o"         )],
        'apb'      : [("input" , 1      , "s_apb_psel_i"   ),
                      ("input" , 1      , "s_apb_penable_i"),
                      ("input" , 1      , "s_apb_pwrite_i" ),
                      ("input" , addr   , "s_apb_paddr_i"  ),
                      ("input" , data   , "s_apb_pwdata_i" ),
                      ("output", data   , "s_apb_prdata_o" ),
                      ("output", 1      , "s_apb_pready_o" ),
                      ("output", 1      , "s_apb_pslverr_o")],
        'axi4lite' : [("input" , 1      , "s_axi_awvalid_i"),
                      ("output", 1      , "s_axi_awready_o"),
                      ("input" , addr   , "s_axi_awaddr_i" ),
                      ("input" , 1      , "s_axi_wvalid_i" ),
                      ("output", 1      , "s_axi_wready_o" ),
                      ("input" , data   , "s_axi_wdata_i"  ),
                      ("input" , max(1,data//8), "s_axi_wstrb_i"),
                      ("output", 1      , "s_axi_bvalid_o" ),
                      ("input" , 1      , "s_axi_bready_i" ),
                      ("output", 2      , "s_axi_bresp_o"  ),
                      ("input" , 1      , "s_axi_arvalid_i"),
                      ("output", 1      , "s_axi_arready_o"),
                      ("input" , addr   , "s_axi_araddr_i" ),
                      ("output", 1      , "s_axi_rvalid_o" ),
                      ("input" , 1      , "s_axi_rready_i" ),
                      ("output", data   , "s_axi_rdata_o"  ),
                      ("output", 2      , "s_axi_rresp_o"  )],
    }
    return ports[csr['interface']]

#--------------------------------------------
#--------------------------------------------
def verilog_init(reg):
    """
    Reset value of a register (fields packed from bit 0, in the order of the hjson)

    :param reg: Dictionary of register
    :return: Verilog constant expression
    """
    value = 0
    exprs = []
    lsb   = 0
    for field in reg['fields']:
        if field['expr'] == f"\"{parse_init_value(field['init'],field['width'])}\"":
            value |= field['init'] << lsb
        else:
            mask   = f"{{{field['width']}{{1'b1}}}}"
            exprs.append(f"(({verilog_expr(field['expr'])} & {mask}) << {lsb})")
        lsb += field['width']

    return " | ".join([f"{reg['width']}'h{value:X}"] + exprs)

#--------------------------------------------
#--------------------------------------------
def verilog_field_init(field):
    """
    Reset value of a field

    :param field: Dictionary of field
    :return: Verilog constant expression
    """
    if field['expr'] == f"\"{parse_init_value(field['init'],field['width'])}\"":
        return f"{field['width']}'h{field['init']:X}"
    return verilog_expr(field['expr'])

#--------------------------------------------
#--------------------------------------------
def verilog_bus_data(csr, reg, source):
    """
    Bus data from the packed register data : each field at its position, 0 elsewhere

    :param csr: Dictionary of csr
    :param reg: Dictionary of register
    :param source: Name of the packed register data (fields packed from bit 0)
    :return: Verilog concatenation
    """
    # packed position of each field
    packed = []
    lsb    = 0
    for field in reg['fields']:
        packed.append((field, lsb))
        lsb += field['width']

    parts = []
    bit   = csr['width']
    for field, plsb in sorted(packed, key=lambda item: item[0]['lsb'], reverse=True):
        if bit > field['msb']+1:
            parts.append(f"{bit-field['msb']-1}'b0")
        parts.append(f"{source}[{plsb+field['width']-1}:{plsb}]")
        bit = field['lsb']
    if bit > 0:
        parts.append(f"{bit}'b0")

    return "{" + ", ".join(parts) + "}"

#--------------------------------------------
#--------------------------------------------
def verilog_packed_data(reg, source):
    """
    Packed register data (fields packed from bit 0) from the bus data

    :param reg: Dictionary of register
    :param source: Name of the bus data
    :return: Verilog concatenation
    """
    parts = [f"{source}[{field['msb']}:{field['lsb']}]" for field in reversed(reg['fields'])]
    return "{" + ", ".join(parts) + "}"

#--------------------------------------------
#--------------------------------------------
def print_verilog_header_csr(csr,file):
    file.write( "//==================================\n")
    file.write(f"// Module      : {csr['name']}\n")
    file.write(f"// Description : {csr['desc']}\n")
    file.write(f"// Width       : {csr['width']}\n")
    file.write( "//==================================\n")

#--------------------------------------------
#--------------------------------------------
def print_verilog_header_reg(reg,file):
    file.write( "  //==================================\n")
    file.write(f"  // Register    : {reg['name']}\n")
    file.write(f"  // Description : {reg['desc']}\n")
    file.write(f"  // Address     : 0x{reg['address']:X}\n")
    file.write(f"  // Width       : {reg['width']}\n")
    file.write(f"  // Sw Access   : {reg['swaccess']}\n")
    file.write(f"  // Hw Access   : {reg['hwaccess']}\n")
    file.write(f"  // Hw Type     : {reg['hwtype']}\n")
    file.write( "  //==================================\n")

#--------------------------------------------
#--------------------------------------------
def generate_verilog_header(csr, output_path):
    """
    Header with the constants of the csr (macros prefixed by the module name)
    """
    check_verilog(csr)
    module = csr['name']
    MODULE = module.upper()
    aw     = verilog_addr_width(csr)

    with open(output_path, 'w') as file:
        file.write(f"// Generated Verilog Header for {module}\n\n")
        file.write(f"`ifndef {MODULE}_CSR_PKG_VH\n")
        file.write(f"`define {MODULE}_CSR_PKG_VH\n\n")
        print_verilog_header_csr(csr,file)
        file.write( "\n")
        file.write(f"`define {MODULE}_ADDR_WIDTH {aw}\n")
        file.write(f"`define {MODULE}_DATA_WIDTH {csr['width']}\n")
        file.write( "\n")

        for reg in csr['registers']:
            file.write(f"// Register    : {reg['name']}\n")
            file.write(f"`define {MODULE}_{reg['name'].upper()} {aw}'h{reg['address']:X}\n")
            for field in reg['fields']:
                for enum in field.get('enum', []):
                    value = parse_value(enum['value'])
                    name  = f"{MODULE}_{reg['name'].upper()}_{field['name'].upper()}_{enum['name'].upper()}"
                    file.write(f"// Enum        : {reg['name']}.{field['name']}.{enum['name']} : {enum['desc']}\n")
                    file.write(f"`define {name}     {field['width']}'h{value:X}\n")
                    file.write(f"`define {name}_RAW {csr['width']}'h{value<<field['lsb']:X}\n")
            file.write( "\n")

        file.write(f"`endif // {MODULE}_CSR_PKG_VH\n")

#--------------------------------------------
#--------------------------------------------
def generate_verilog_module(csr, output_path):
    """
    Module <name>_registers
    """
    check_verilog(csr)
    module = csr['name']
    aw     = verilog_addr_width(csr)
    dw     = csr['width']

    with open(output_path, 'w') as file:
        file.write(f"// Generated Verilog Module for {module}\n\n")
        print_verilog_header_csr(csr,file)

        # File <name>_csr.v for the module <name>_registers (as in VHDL),
        # unconnected outputs of the building blocks are left open
        file.write( "// verilator lint_off DECLFILENAME\n")
        file.write( "// verilator lint_off PINCONNECTEMPTY\n")

        #------------------------------------
        # Module
        #------------------------------------
        file.write(f"module {module}_registers\n")
        if csr['parameters'] != []:
            prefix = "#("
            for param in csr['parameters']:
                file.write(f"  {prefix}parameter {verilog_param_range(param['type'])}{param['name']} = 0 // {param['desc']}\n")
                prefix = " ,"
            file.write( "   )\n")

        file.write( "  (\n")
        file.write( "    // Clock and Reset\n")
        file.write( "    input  wire clk_i\n")
        file.write( "   ,input  wire arst_b_i\n")
        file.write( "    // Bus\n")
        for direction, width, name in verilog_bus_ports(csr):
            file.write(f"   ,{direction:<6} wire {verilog_range(width)}{name}\n")
        file.write( "    // CSR\n")
        for direction, width, name, _, _ in verilog_csr_ports(csr):
            file.write(f"   ,{direction:<6} wire {verilog_range(width)}{name}\n")
        file.write( "   );\n")
        file.write( "\n")

        #------------------------------------
        # Declarations
        #------------------------------------
        file.write(f"  localparam ADDR_WIDTH = {aw};\n")
        file.write(f"  localparam DATA_WIDTH = {dw};\n")
        file.write( "\n")
        for reg in csr['registers']:
            file.write(f"  localparam [ADDR_WIDTH-1:0] ADDR_{reg['name'].upper()} = {aw}'h{reg['address']:X};\n")
        file.write( "\n")

        file.write( "  wire                  sig_wcs;\n")
        file.write( "  wire                  sig_we;\n")
        file.write( "  wire [ADDR_WIDTH-1:0] sig_waddr;\n")
        file.write( "  // verilator lint_off UNUSEDSIGNAL\n")
        file.write( "  wire [DATA_WIDTH-1:0] sig_wdata;          // Bits without field are not used\n")
        file.write( "  // verilator lint_on UNUSEDSIGNAL\n")
        file.write( "  wire                  sig_wbusy;\n")
        file.write( "\n")
        file.write( "  wire                  sig_rcs;\n")
        file.write( "  wire                  sig_re;\n")
        file.write( "  wire [ADDR_WIDTH-1:0] sig_raddr;\n")
        file.write( "  wire [DATA_WIDTH-1:0] sig_rdata;\n")
        file.write( "  wire                  sig_rbusy;\n")
        file.write( "\n")
        file.write( "  wire                  sig_busy;\n")
        file.write( "\n")

        #------------------------------------
        # Interface
        #------------------------------------
        if csr['interface'] == 'mem':
            file.write( "  // Interface\n")
            file.write( "  assign sig_wcs   = cs_i;\n")
            file.write( "  assign sig_we    = we_i;\n")
            file.write( "  assign sig_waddr = addr_i;\n")
            file.write( "  assign sig_wdata = wdata_i;\n")
            file.write( "\n")
            file.write( "  assign sig_rcs   = cs_i;\n")
            file.write( "  assign sig_re    = re_i;\n")
            file.write( "  assign sig_raddr = addr_i;\n")
            file.write( "  assign rdata_o   = sig_rdata;\n")
            file.write( "  assign busy_o    = sig_busy;\n")
        else:
            bridge = f"{csr['interface']}2mem"
            file.write(f"  // Interface : bridge {bridge}\n")
            file.write( "  wire                  mem_cs;\n")
            file.write( "  wire                  mem_re;\n")
            file.write( "  wire                  mem_we;\n")
            file.write( "  wire [ADDR_WIDTH-1:0] mem_addr;\n")
            file.write( "  wire [DATA_WIDTH-1:0] mem_wdata;\n")
            file.write( "  wire [DATA_WIDTH-1:0] mem_rdata;\n")
            file.write( "  wire                  mem_busy;\n")
            file.write( "\n")
            file.write(f"  {bridge}\n")
            file.write( "    #(.ADDR_WIDTH      (ADDR_WIDTH)\n")
            file.write( "     ,.DATA_WIDTH      (DATA_WIDTH)\n")
            file.write( "     )\n")
            file.write(f"  ins_{bridge}\n")
            prefix = "("
            if csr['interface'] == 'axi4lite':
                file.write( "    (.clk_i           (clk_i)\n")
                file.write( "    ,.arst_b_i        (arst_b_i)\n")
                prefix = ","
            for _, _, name in verilog_bus_ports(csr):
                file.write(f"    {prefix}.{name:<15} ({name})\n")
                prefix = ","
            file.write( "    ,.cs_o            (mem_cs)\n")
            file.write( "    ,.re_o            (mem_re)\n")
            file.write( "    ,.we_o            (mem_we)\n")
            file.write( "    ,.addr_o          (mem_addr)\n")
            file.write( "    ,.wdata_o         (mem_wdata)\n")
            file.write( "    ,.rdata_i         (mem_rdata)\n")
            file.write( "    ,.busy_i          (mem_busy)\n")
            file.write( "    );\n")
            file.write( "\n")
            file.write( "  assign sig_wcs   = mem_cs;\n")
            file.write( "  assign sig_we    = mem_we;\n")
            file.write( "  assign sig_waddr = mem_addr;\n")
            file.write( "  assign sig_wdata = mem_wdata;\n")
            file.write( "\n")
            file.write( "  assign sig_rcs   = mem_cs;\n")
            file.write( "  assign sig_re    = mem_re;\n")
            file.write( "  assign sig_raddr = mem_addr;\n")
            file.write( "  assign mem_rdata = sig_rdata;\n")
            file.write( "  assign mem_busy  = sig_busy;\n")
        file.write( "\n")
        file.write( "  assign sig_busy  = sig_we ? sig_wbusy :\n")
        file.write( "                     sig_re ? sig_rbusy :\n")
        file.write( "                     1'b0;\n")
        file.write( "\n")

        #------------------------------------
        # Registers
        #------------------------------------
        csr_ports = verilog_csr_ports(csr)

        for reg in csr['registers']:
            r  = reg['name']
            rw = reg['width']

            print_verilog_header_reg(reg,file)
            # Signals of the read data and busy multiplexers
            file.write(f"  wire          {r}_wcs;\n")
            file.write(f"  wire          {r}_wbusy;\n")
            file.write(f"  wire          {r}_rcs;\n")
            file.write(f"  wire          {r}_rbusy;\n")
            file.write(f"  wire [{dw}-1:0] {r}_rdata;\n")
            file.write( "\n")

            file.write( "  generate\n")
            file.write(f"    if (({verilog_expr(reg['enable'])}) != 0)\n")
            file.write(f"      begin : gen_{r}\n")
            if reg['hwtype'] in ['reg']:
                file.write(f"        localparam [{rw}-1:0] INIT_{r} = {verilog_init(reg)};\n")
                file.write( "\n")
            file.write(f"        wire          {r}_re;\n")
            file.write(f"        wire          {r}_we;\n")
            file.write(f"        wire [{rw}-1:0] {r}_wdata_sw;\n")
            if reg['hw2sw_data']:
                file.write(f"        wire [{rw}-1:0] {r}_wdata_hw;\n")
            if reg['sw2hw_re']:
                file.write(f"        wire [{rw}-1:0] {r}_rdata_sw;\n")
            if reg['sw2hw_data']:
                file.write(f"        wire [{rw}-1:0] {r}_rdata_hw;\n")
            file.write( "\n")

            # Read
            if reg['sw2hw_re']:
                file.write(f"        assign {r}_rcs   = (sig_raddr == ADDR_{r.upper()});\n")
                file.write(f"        assign {r}_re    = sig_rcs & sig_re & {r}_rcs;\n")
                file.write(f"        assign {r}_rdata = {verilog_bus_data(csr,reg,r+'_rdata_sw')};\n")
            else:
                file.write(f"        assign {r}_rcs   = 1'b0;\n")
                file.write(f"        assign {r}_re    = 1'b0;\n")
                file.write(f"        assign {r}_rdata = {{{dw}{{1'b0}}}};\n")

            # Write
            if reg['sw2hw_we']:
                waddr = " | ".join([f"(sig_waddr == ADDR_{waddr.upper()})" for waddr in reg['address_write']])
                file.write(f"        assign {r}_wcs   = {waddr};\n")
                file.write(f"        assign {r}_we    = sig_wcs & sig_we & {r}_wcs;\n")
                file.write(f"        assign {r}_wdata_sw = {verilog_packed_data(reg,'sig_wdata')};\n")
            else:
                file.write(f"        assign {r}_wcs   = 1'b0;\n")
                file.write(f"        assign {r}_we    = 1'b0;\n")
                file.write(f"        assign {r}_wdata_sw = {{{rw}{{1'b0}}}};\n")

            # Hardware side data
            if reg['hw2sw_data']:
                fields = ", ".join([f"hw2sw_{r}_{field['name']}_i" for field in reversed(reg['fields'])])
                file.write(f"        assign {r}_wdata_hw = {{{fields}}};\n")
            if reg['sw2hw_data']:
                lsb=0
                for field in reg['fields']:
                    msb=lsb+field['width']-1
                    file.write(f"        assign sw2hw_{r}_{field['name']}_o = {r}_rdata_hw[{msb}:{lsb}];\n")
                    lsb=msb+1
            file.write( "\n")

            # Instance
            file.write(f"        csr_{reg['hwtype']}\n")
            file.write(f"          #(.WIDTH          ({rw})\n")
            if reg['hwtype'] in ['reg']:
                file.write(f"           ,.INIT           (INIT_{r})\n")
                file.write(f"           ,.MODEL          (\"{reg['swaccess']}\")\n")
            if reg['hwtype'] in ['fifo']:
                for param, value in reg.get('params', {}).items():
                    file.write(f"           ,.{param:<14} ({verilog_expr(str(value))})\n")
            file.write( "           )\n")
            file.write(f"        ins_{r}\n")
            file.write( "          (.clk_i           (clk_i)\n")
            file.write( "          ,.arst_b_i        (arst_b_i)\n")
            file.write(f"          ,.sw_wd_i         ({r}_wdata_sw)\n")
            file.write(f"          ,.sw_rd_o         ({r+'_rdata_sw' if reg['sw2hw_re'] else ''})\n")
            file.write(f"          ,.sw_we_i         ({r}_we)\n")
            file.write(f"          ,.sw_re_i         ({r}_re)\n")
            file.write(f"          ,.sw_rbusy_o      ({r}_rbusy)\n")
            file.write(f"          ,.sw_wbusy_o      ({r}_wbusy)\n")

            hw_re = f"hw2sw_{r}_{reg['hw2sw_name_re']}_i" if reg['hw2sw_re']   else "1'b1"
            hw_we = f"hw2sw_{r}_{reg['hw2sw_name_we']}_i" if reg['hw2sw_we']   else "1'b0"
            sw_re = f"sw2hw_{r}_{reg['sw2hw_name_re']}_o" if reg['sw2hw_re']   else ""
            sw_we = f"sw2hw_{r}_{reg['sw2hw_name_we']}_o" if reg['sw2hw_we']   else ""
            hw_wd = f"{r}_wdata_hw"                       if reg['hw2sw_data'] else f"{{{rw}{{1'b0}}}}"
            hw_rd = f"{r}_rdata_hw"                       if reg['sw2hw_data'] else ""

            if reg['hwtype'] in ['reg','ext']:
                file.write(f"          ,.hw_wd_i         ({hw_wd})\n")
                file.write(f"          ,.hw_rd_o         ({hw_rd})\n")
                file.write(f"          ,.hw_we_i         ({hw_we})\n")
                file.write(f"          ,.hw_sw_re_o      ({sw_re})\n")
                file.write(f"          ,.hw_sw_we_o      ({sw_we})\n")

            if reg['hwtype'] in ['fifo']:
                file.write(f"          ,.hw_tx_valid_i   ({hw_we})\n")
                file.write(f"          ,.hw_tx_ready_o   ({sw_re})\n")
                file.write(f"          ,.hw_tx_data_i    ({hw_wd})\n")
                if reg['hw2sw_data']:
                    file.write(f"          ,.hw_tx_empty_o   (sw2hw_{r}_hw2sw_empty_o)\n")
                    file.write(f"          ,.hw_tx_full_o    (sw2hw_{r}_hw2sw_full_o)\n")
                else:
                    file.write( "          ,.hw_tx_empty_o   ()\n")
                    file.write( "          ,.hw_tx_full_o    ()\n")
                file.write(f"          ,.hw_rx_valid_o   ({sw_we})\n")
                file.write(f"          ,.hw_rx_ready_i   ({hw_re})\n")
                file.write(f"          ,.hw_rx_data_o    ({hw_rd})\n")
                if reg['sw2hw_data']:
                    file.write(f"          ,.hw_rx_empty_o   (sw2hw_{r}_sw2hw_empty_o)\n")
                    file.write(f"          ,.hw_rx_full_o    (sw2hw_{r}_sw2hw_full_o)\n")
                else:
                    file.write( "          ,.hw_rx_empty_o   ()\n")
                    file.write( "          ,.hw_rx_full_o    ()\n")
            file.write( "          );\n")
            file.write(f"      end // gen_{r}\n")

            # Disabled register : no access, hardware outputs at their reset value
            file.write( "    else\n")
            file.write(f"      begin : gen_{r}_b\n")
            file.write(f"        assign {r}_rcs   = 1'b0;\n")
            file.write(f"        assign {r}_rbusy = 1'b0;\n")
            file.write(f"        assign {r}_rdata = {{{dw}{{1'b0}}}};\n")
            file.write(f"        assign {r}_wcs   = 1'b0;\n")
            file.write(f"        assign {r}_wbusy = 1'b0;\n")
            fields = {field['name'] : field for field in reg['fields']}
            for direction, width, name, preg, item in csr_ports:
                if preg is not reg or direction != "output":
                    continue
                if item in fields:
                    file.write(f"        assign {name} = {verilog_field_init(fields[item])};\n")
                elif item in ["sw2hw_empty", "hw2sw_empty"]:
                    file.write(f"        assign {name} = 1'b1;\n")
                else:
                    file.write(f"        assign {name} = 1'b0;\n")
            file.write(f"      end // gen_{r}_b\n")
            file.write( "  endgenerate\n")
            file.write( "\n")

        #------------------------------------
        # Busy and read data
        #------------------------------------
        file.write( "  assign sig_wbusy =\n")
        for reg in csr['registers']:
            file.write(f"    {reg['name']}_wcs ? {reg['name']}_wbusy :\n")
        file.write( "    1'b0; // Bad Address, no busy\n")
        file.write( "\n")
        file.write( "  assign sig_rbusy =\n")
        for reg in csr['registers']:
            file.write(f"    {reg['name']}_rcs ? {reg['name']}_rbusy :\n")
        file.write( "    1'b0; // Bad Address, no busy\n")
        file.write( "\n")
        file.write( "  assign sig_rdata =\n")
        for reg in csr['registers']:
            file.write(f"    {reg['name']}_rcs ? {reg['name']}_rdata :\n")
        file.write( "    {DATA_WIDTH{1'b0}}; // Bad Address, return 0\n")
        file.write( "\n")
        file.write( "endmodule\n")
        file.write( "// verilator lint_on PINCONNECTEMPTY\n")
        file.write( "// verilator lint_on DECLFILENAME\n")
