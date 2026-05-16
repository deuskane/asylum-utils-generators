#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# Title      : ROM Generator
# Project    : Asylum
#-----------------------------------------------------------------------------
# File       : gen_rom.py
# Description: Generates a VHDL ROM from a HEX file using a template.
#-----------------------------------------------------------------------------

import sys
import argparse
import datetime
import logging
import re
from pathlib import Path

class AlignedFormatter(logging.Formatter):
    """
    Custom formatter to align log levels for better readability.
    """
    def format(self, record):
        record.levelname = f"[{record.levelname:<8}]"
        return super().format(record)

def setup_logger():
    handler = logging.StreamHandler()
    formatter = AlignedFormatter('%(levelname)s %(message)s')
    handler.setFormatter(formatter)
    logger = logging.getLogger("gen_rom")
    logger.setLevel(logging.INFO)
    logger.handlers = [handler]
    logger.propagate = False
    return logger

logger = setup_logger()

def generate_rom(hex_file: str, output_file: str, template_file: str, output_name: str, data_width: int = 32, addr_width: int = 10):
    """
    Reads a HEX file and populates a VHDL template.
    
    Args:
        hex_file: Path to the input .hex file.
        output_file: Path to the output VHDL file.
        template_file: Path to the VHDL template file.
        output_name: Name of the output VHDL entity and file.
        data_width: Bit width of each ROM word.
        addr_width: Number of address bits (determines ROM depth).
    """
    logger.info(f"Generating ROM '{output_name}' from '{hex_file}'")
    # 1. Load HEX data
    try:
        with open(hex_file, 'r') as f:
            hex_lines = [line.strip() for line in f if line.strip()]

        num_entries = 2**addr_width
        if len(hex_lines) > num_entries:
            logger.error(f"The hex file ({len(hex_lines)} lines) is too large for the ROM size ({num_entries} words).")
            return
    except Exception as e:
        logger.error(f"Error reading hex file: {e}")
        return

    # 2. Load template
    try:
        with open(template_file, 'r') as f:
            content = f.read()
            # Keep only what is between {begin template} and {end template} if present
            if "{begin template}" in content and "{end template}" in content:
                content = content.split("{begin template}")[1].split("{end template}")[0]
            elif "{begin template}" in content:
                content = content.split("{begin template}")[1]
    except Exception as e:
        logger.error(f"Error reading template: {e}")
        return

    # 3. Prepare replacements
    timestamp = datetime.datetime.now().strftime("%d %b %Y %H:%M:%S")
    
    # Replace name and timestamp
    content = content.replace("{name}", output_name)
    content = content.replace("{timestamp}", timestamp)
    content = content.replace("{addr_width}", str(addr_width))
    content = content.replace("{data_width}", str(data_width))
#
#    # Replace INITX entries
#    # The template uses lowercase hexadecimal addresses
#    num_entries = 2**addr_width
#    for i in range(num_entries):
#        tag = f"{{INITX_{i:03x}}}"
#        # If a value exists in hex, use it, otherwise use 0
#        default_val = "0" * (data_width // 4)
#        val = hex_lines[i] if i < len(hex_lines) else default_val
#        
#        # Note: The template often expects binary or hex depending on usage.
#        # Here we inject the raw value from the hex file.
#        content = content.replace(tag, val)
#
    # Handle CASE_BODY tag: {CASE_BODY-X-Y}
    # X: number of spaces for indentation, Y: variable name to assign
    case_pattern = r"\{CASE_BODY-(\d+)-(\w+)\}"
    matches = re.findall(case_pattern, content)
    
    for indent_size, var_name in matches:
        tag = f"{{CASE_BODY-{indent_size}-{var_name}}}"
        indent = " " * int(indent_size)
        case_lines = []
        for i, val in enumerate(hex_lines):
            case_lines.append(f"{indent}when {i} => {var_name} <= x\"{val}\";")
        
        replacement = "\n".join(case_lines)
        content = content.replace(tag, replacement)

    # Handle ROM_BODY tag: {ROM_BODY-X}
    rom_pattern = r"\{ROM_BODY-(\d+)\}"
    rom_matches = re.findall(rom_pattern, content)

    for indent_size in rom_matches:
        tag = f"{{ROM_BODY-{indent_size}}}"
        indent = " " * int(indent_size)
        rom_lines = []
        for i, val in enumerate(hex_lines):
            rom_lines.append(f"{indent}{i} => x\"{val}\",")
        
        replacement = "\n".join(rom_lines)
        content = content.replace(tag, replacement)

    # 4. Write result
    with open(output_file, 'w') as f:
        f.write(content)

    logger.info(f"Successfully generated: {output_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate VHDL ROM from HEX file.")
    parser.add_argument("hex_file", help="Input HEX file")
    parser.add_argument("template", help="VHDL template file")
    parser.add_argument("entity", help="Output entity name")
    parser.add_argument("output_file", help="Output VHDL file")
    parser.add_argument("--data-width", type=int, default=32, help="Data width in bits (default: 32)")
    parser.add_argument("--addr-width", type=int, default=10, help="Address width in bits (default: 10)")

    args = parser.parse_args()

    generate_rom(args.hex_file, args.output_file, args.template, args.entity, args.data_width, args.addr_width)
