#-----------------------------------------------------------------------------
# Title      : rvcc Generator
# Project    : Asylum
#-----------------------------------------------------------------------------
# File       : rvcc.py
# Author     : Gemini Code Assist
#-----------------------------------------------------------------------------
# Description: 
#-----------------------------------------------------------------------------
# Copyright (c) 2024
#-----------------------------------------------------------------------------

import os
import sys
from   fusesoc.capi2.generator import Generator
import subprocess
from   fusesoc.utils           import Launcher
from   glob                    import glob
from   pathlib                 import Path
import shutil
from   jinja2                  import Environment, FileSystemLoader
import logging

class AlignedFormatter(logging.Formatter):
    def format(self, record):
        record.levelname = f"[{record.levelname:<8}]"
        return super().format(record)

class rvcc(Generator):

    def update_paths(self, options, files_root):
        updated_options = []
        for option in options:
            if option.startswith('-I'):
                path = option[2:]
                if not path.startswith('/'):
                    updated_options.append(f'-I{files_root}/{path}')
                else:
                    updated_options.append(option)
            else:
                updated_options.append(option)
        return updated_options

    def run(self):
        handler   = logging.StreamHandler()
        formatter = AlignedFormatter('%(levelname)s %(message)s')
        handler.setFormatter(formatter)
        
        logger    = logging.getLogger()
        logger.setLevel(logging.INFO)
        logger.handlers = [handler]
        
        logger.info("-------------------------------------------")
        logger.info("Start Generator rvcc")
        logger.info("-------------------------------------------")

        #-------------------------------------------------
        # Get parameters
        #-------------------------------------------------
        input_file_path = Path(self.files_root) / self.config.get("file")
        file_type   = self.config.get("type")
        cflags      = self.config.get("cflags", "")
        logical_name= self.config.get("logical_name", None)

        cflags_list = self.update_paths(cflags.split(), self.files_root)
        
        if not input_file_path.exists():
            logger.error(f"Input file not found: {input_file_path}")
            raise FileNotFoundError(f"Input file not found: {input_file_path}")

        if not file_type in ["c", "s", "elf", "hex"]:
            logger.error(f"Unknown file type: {file_type}. Possible options are 'c', 's', 'elf' or 'hex'")
            raise RuntimeError("Unknown file type")

        # Determine the base name for output files (e.g., .o, .elf, .hex, .vhd)
        output_base_name = input_file_path.stem

        # Paths for generated files in the current working directory
        output_elf_file     = Path(f"{output_base_name}.elf")
        output_hex_file     = Path(f"{output_base_name}.hex")
        output_vhd_file     = Path(f"{output_base_name}.vhd")
        output_vhd_pkg_file = Path(f"{output_base_name}_pkg.vhd")
        
        # Paths for template files
        template_dir = Path(__file__).parent / "templates"
        start_s_template = template_dir / "start.S"
        link_ld_template = template_dir / "link.ld"

        # Copy start.S and link.ld to the current working directory
        # These files are always needed for C/S compilation
        try:
            shutil.copy(start_s_template, Path.cwd() / "start.S")
            shutil.copy(link_ld_template, Path.cwd() / "link.ld")
            logger.info(f"Copied {start_s_template.name} and {link_ld_template.name} to current directory.")
        except FileNotFoundError as e:
            logger.error(f"Missing template file: {e}")
            raise RuntimeError(f"Missing template file: {e}")
            
        rom_entity  = self.config.get("entity", "WardRV_ROM")
        rom_model   = self.config.get("model", "generic")

        if (not rom_model in ["generic", "xilinx"]):
            logger.error(f"Unknown rom model: {rom_model}. Possible options are 'generic' or 'xilinx'")
            raise RuntimeError

        #-------------------------------------------------
        # Environment setup
        #-------------------------------------------------
        riscv_prefix = os.environ.get("RISCV_PREFIX", "riscv32-unknown-elf-")

        if "HEX2VHD_HOME" in os.environ:
            hex2vhd_home = Path(os.environ["HEX2VHD_HOME"]).resolve()
        else:
            hex2vhd_home = Path(__file__).parent.parent / "gen_rom"

        hex2vhd_tool = hex2vhd_home.joinpath("gen_rom.py")

        if not hex2vhd_tool.exists():
            logger.error(f"hex2vhd tool not found at {hex2vhd_tool}. Check HEX2VHD_HOME.")
            raise FileNotFoundError(f"hex2vhd tool not found at {hex2vhd_tool}.")

        rom_model_vhd = hex2vhd_home.joinpath("ROM", rom_model, "ROM_form.vhd")

        if not rom_model_vhd.exists():
            logger.error(f"ROM template not found at {rom_model_vhd}.")
            raise FileNotFoundError(f"ROM template not found at {rom_model_vhd}.")

        rom_pkg_vhd = hex2vhd_home.joinpath("ROM", "pkg", "ROM_pkg.vhd")

        #-------------------------------------------------
        # Call Jinja2
        #-------------------------------------------------
        config = {
            "riscv_prefix"        : riscv_prefix,
            "hex2vhd_tool"        : hex2vhd_tool,
            "input_file_path"     : input_file_path, # Absolute path to original input file
            "output_base_name"    : output_base_name, # Base name for generated files
            "output_elf_file"     : output_elf_file, # Name of the final ELF file
            "output_hex_file"     : output_hex_file, # Name of the final HEX file
            "output_vhd_file"     : output_vhd_file, # Name of the final VHD file
            "output_vhd_pkg_file" : output_vhd_pkg_file, # Name of the final VHD package file
            "file_type"           : file_type,
            "rom_entity"          : rom_entity,
            "rom_model_vhd"       : rom_model_vhd,
            "rom_pkg_vhd"         : rom_pkg_vhd,
            "cflags"              : " ".join(cflags_list),
            "start_s_file"        : "start.S", # Name of the copied start.S
            "link_ld_file"        : "link.ld"  # Name of the copied link.ld
        }
        
        env              = Environment(loader=FileSystemLoader(template_dir))
        template         = env.get_template('Makefile.j2')
        
        makefile_content = template.render(config)
        
        with open('Makefile', 'w') as f:
            f.write(makefile_content)
        logger.info(f"Makefile generated at {Path.cwd() / 'Makefile'}")
            
        try:
            Launcher("make").run()
            logger.info(f"ROM file generated: {output_vhd_file}")
        except Exception as e:
            logger.error(str(e))
            raise RuntimeError(f"Makefile execution failed: {e}")

        
        #-------------------------------------------------
        # Add outfile in source files
        #-------------------------------------------------
        outfiles = []
        if logical_name is None:
            outfiles.append({str(output_vhd_file)     : {'file_type' : 'vhdlSource'}})
            outfiles.append({str(output_vhd_pkg_file) : {'file_type' : 'vhdlSource'}})
        else:
            outfiles.append({str(output_vhd_file)     : {'file_type' : 'vhdlSource', 'logical_name' : logical_name}})
            outfiles.append({str(output_vhd_pkg_file) : {'file_type' : 'vhdlSource', 'logical_name' : logical_name}})

        if outfiles:
            self.add_files(outfiles)
        else:
            logger.error("output files not found.")
            raise RuntimeError
            
        logger.info("-------------------------------------------")
        logger.info("End Generator rvcc")
        logger.info("-------------------------------------------")

if __name__ == '__main__':
    g = rvcc()
    g.run()
    g.write()