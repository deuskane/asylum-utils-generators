"""
Module regtool.py
Command line of regtool : reads the CSR description (csr_model) and calls the
generators (gen_hdl for VHDL, Verilog and SystemVerilog, gen_c, gen_markdown).
"""

import argparse
from   csr_model    import parse_hjson
from   gen_hdl      import generate_hdl_package, generate_hdl_module
from   gen_c        import generate_c_header
from   gen_markdown import generate_doc_markdown

#--------------------------------------------
#--------------------------------------------
def main():
    parser = argparse.ArgumentParser(description='Generate VHDL, Verilog, SystemVerilog and C files from HJSON input.')
    parser.add_argument('input_file'    , type=str,  help='Path to the HJSON input file')
    parser.add_argument('--vhdl_package', type=str,  help='Path to the VHDL package output file')
    parser.add_argument('--vhdl_module' , type=str,  help='Path to the VHDL module output file')
    parser.add_argument('--verilog_header', type=str,  help='Path to the Verilog header output file (only if set)')
    parser.add_argument('--verilog_module', type=str,  help='Path to the Verilog module output file (only if set)')
    parser.add_argument('--sv_package'  , type=str,  help='Path to the SystemVerilog package output file (only if set)')
    parser.add_argument('--sv_module'   , type=str,  help='Path to the SystemVerilog module output file (only if set)')
    parser.add_argument('--c_header'    , type=str,  help='Path to the C header output file')
    parser.add_argument('--doc_markdown', type=str,  help='Path to the Markdown Documentation output file')
    parser.add_argument('--logical_name', type=str,  help='Library', default='work')
    parser.add_argument('--interface'   , type=str,  help='Replace the interface of the HJSON input file')

    args         = parser.parse_args()

    csr          = parse_hjson(args.input_file, dump=True, interface=args.interface)
    csr['logical_name'] = args.logical_name


    # Define output file names if not provided
    vhdl_package = args.vhdl_package or f"{csr['name']}_csr_pkg.vhd"
    vhdl_module  = args.vhdl_module  or f"{csr['name']}_csr.vhd"
    c_header     = args.c_header     or f"{csr['name']}_csr.h"
    doc_markdown = args.doc_markdown or f"{csr['name']}_csr.md"

    generate_hdl_package  (csr, vhdl_package, 'vhdl')
    generate_hdl_module   (csr, vhdl_module , 'vhdl')
    generate_c_header     (csr, c_header)
    generate_doc_markdown (csr, doc_markdown)
    print(f"VHDL package  generated in {vhdl_package}")
    print(f"VHDL module   generated in {vhdl_module}")
    # Verilog / SystemVerilog only on request (no bridge for sbi and pbi)
    if args.verilog_header:
        generate_hdl_package(csr, args.verilog_header, 'verilog')
        print(f"Verilog header generated in {args.verilog_header}")
    if args.verilog_module:
        generate_hdl_module (csr, args.verilog_module, 'verilog')
        print(f"Verilog module generated in {args.verilog_module}")
    if args.sv_package:
        generate_hdl_package(csr, args.sv_package, 'systemverilog')
        print(f"SystemVerilog package generated in {args.sv_package}")
    if args.sv_module:
        generate_hdl_module (csr, args.sv_module , 'systemverilog')
        print(f"SystemVerilog module  generated in {args.sv_module}")
    print(f"C    header   generated in {c_header}")
    print(f"Doc  markdown generated in {doc_markdown}")

if __name__ == "__main__":
    main()
