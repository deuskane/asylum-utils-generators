#-----------------------------------------------------------------------------
# Title      : Regtool
# Project    : Asylum
#-----------------------------------------------------------------------------
# File       : pbcc.py
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: 
#-----------------------------------------------------------------------------
# Copyright (c) 2025
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2025-02-20  2.0.0    mrosiere Created
#-----------------------------------------------------------------------------

import os
import fcntl
import hjson

import sys
from   fusesoc.capi2.generator import Generator
import subprocess
from   fusesoc.utils           import Launcher
from   glob                    import glob
from   pathlib                 import Path
from   jinja2                  import Environment, FileSystemLoader
import logging
from   contextlib              import contextmanager

class AlignedFormatter(logging.Formatter):
    def format(self, record):
        # Align le levelname à 8 caractères (DEBUG, INFO, WARNING, etc.)
        record.levelname = f"[{record.levelname:<8}]"  # left-align to 8 chars
        return super().format(record)

class regtool(Generator):

    @classmethod
    @contextmanager
    def process_lock(cls):
        lock_path = Path.cwd() / ".regtool.lock"
        with lock_path.open("a+") as lock_file:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def write(self):
        with self.__class__.process_lock():
            return super().write()

    def run(self):
        with self.__class__.process_lock():
            return self._run()

    def _run(self):

        # Configuration du logger
        handler   = logging.StreamHandler()
        formatter = AlignedFormatter('%(levelname)s %(message)s')
        handler.setFormatter(formatter)
        
        logger    = logging.getLogger()
        logger.setLevel(logging.INFO)
        logger.handlers = [handler]

        
        logger.info("-------------------------------------------")
        logger.info("Start Generator regtool")
        logger.info("-------------------------------------------")
        logger.debug("Work Directory     : {os.getcwd()}")

        #-------------------------------------------------
        # Get parameters
        #-------------------------------------------------
        dir_script    = Path(__file__).resolve().parent.parent.parent
        dir_work      = os.getcwd()
        dir_root      = self.files_root

        file_in       = os.path.join(dir_root,self.config.get("file"))

        name          = self.config.get("name")
        script        = os.path.join(dir_script,"tools","regtool","regtool.py")

        language      = self.config.get("language","vhdl")
        dir_hdl       = os.path.join(dir_script,"tools","regtool","hdl",)

        file_vhdl_pkg = os.path.join(dir_work,name+'_csr_pkg.vhd')
        file_vhdl_csr = os.path.join(dir_work,name+'_csr.vhd')    
        file_v_pkg    = os.path.join(dir_work,name+'_csr_pkg.vh')
        file_v_csr    = os.path.join(dir_work,name+'_csr.v')
        file_h        = os.path.join(dir_work,name+'_csr.h')    
        file_md       = os.path.join(dir_work,name+'_csr.md')    
        copy          = self.config.get("copy",None)
        logical_name  = self.config.get("logical_name",None)
        interface     = self.config.get("interface",None)

        if language == "vhdl":
            ext       = ".vhd"
            files_hdl = ["csr_pkg.vhd","csr_reg.vhd","csr_ext.vhd","csr_fifo.vhd"]
            outputs   = [(file_vhdl_pkg,"--vhdl_package"),(file_vhdl_csr,"--vhdl_module")]
        elif language == "verilog":
            ext       = ".v"
            files_hdl = ["csr_reg.v","csr_ext.v","csr_fifo.v","csr_fifo_sync.v"]
            outputs   = [(file_v_pkg,"--verilog_header"),(file_v_csr,"--verilog_module")]
        else:
            logger.error(f"Invalid language \"{language}\" (vhdl or verilog)")
            raise RuntimeError
        outputs      += [(file_md,"--doc_markdown"),(file_h,"--c_header")]

        # Bus interface : the CSR has a memory interface, the other
        # interfaces use the bridge <interface>2mem of the hdl directory
        bus           = interface
        if bus == None:
            with open(file_in, 'r') as f:
                bus   = hjson.load(f).get("interface","mem")
        if bus not in ["mem","reg"]:
            files_hdl.append(bus+"2mem"+ext)

        if copy != None:
            dir_copy = os.path.join(dir_root,copy)

            if not os.path.isdir(dir_copy):
                logger.error(f"Invalid directory \"{dir_copy}\"")
                raise RuntimeError
        else:
            dir_copy = dir_work
            
        #-------------------------------------------------
        # Summary of parameters
        #-------------------------------------------------
        logger.debug("Name               : {name}")
        logger.debug("dir_script         : {dir_script}")
        logger.debug("dir_work           : {dir_work}")  
        logger.debug("dir_root           : {dir_root}")  
        logger.debug("dir_copy           : {dir_copy}")
        logger.debug("dir_hdl            : {dir_hdl}")
        logger.debug("Script             : {script}")
        logger.debug("File In            : {file_in}")
        logger.debug("file_vhdl_pkg      : {file_vhdl_pkg}")
        logger.debug("file_vhdl_csr      : {file_vhdl_csr}")
        logger.debug("file_h             : {file_h}")
        logger.debug("file_md            : {file_md}")
        logger.debug("Copy               : {copy}")
        logger.debug("logical_name       : {logical_name}")
        logger.debug("interface          : {interface}")
        logger.debug("language           : {language}")
        
        if (logical_name == None):
            libname = "work"
        else:
            libname = logical_name

        # Configuration du projet
        config = {
            "python"       : "python3",
            "regtool"      : script,
            "libname"      : libname,
            "file_in"      : file_in,
            "outputs"      : outputs,
            "dir_script"   : dir_script,
            "copy_dir"     : dir_copy if copy is not None else None,
            "interface"    : interface,
       }
        
        # Chemin vers le dossier contenant les templates
        template_dir     = os.path.join(os.path.dirname(__file__), "templates")
        
        # Chargement du template depuis le dossier 'templates'
        env              = Environment(loader=FileSystemLoader(template_dir))
        template         = env.get_template('Makefile.j2')
        
        # Rendu du Makefile
        makefile_content = template.render(config)
        
        # Écriture dans un fichier Makefile
        with open('Makefile', 'w') as f:
            f.write(makefile_content)
            
        try:
            Launcher("make").run()
        except Exception as e:
            logger.error(str(e))
            raise RuntimeError

        #-------------------------------------------------
        # Add outfile in source files
        #-------------------------------------------------
        outfiles = []

        if language == "verilog":
            for f in files_hdl:
                outfiles.append({os.path.join(dir_hdl,f)  : {'file_type' : 'verilogSource'}})
            outfiles.append({file_v_pkg    : {'file_type' : 'verilogSource', 'is_include_file' : True}})
            outfiles.append({file_v_csr    : {'file_type' : 'verilogSource'}})
        elif (logical_name == None):
            for f in files_hdl:
                outfiles.append({os.path.join(dir_hdl,f)  : {'file_type' : 'vhdlSource'}})
            outfiles.append({file_vhdl_pkg : {'file_type' : 'vhdlSource'}})
            outfiles.append({file_vhdl_csr : {'file_type' : 'vhdlSource'}})
        else:
            for f in files_hdl:
                outfiles.append({os.path.join(dir_hdl,f)  : {'file_type' : 'vhdlSource', 'logical_name' : logical_name}})
            outfiles.append({file_vhdl_pkg : {'file_type' : 'vhdlSource', 'logical_name' : logical_name}})
            outfiles.append({file_vhdl_csr : {'file_type' : 'vhdlSource', 'logical_name' : logical_name}})

        outfiles.append({file_h : {'file_type' : 'user', 'copyto' : os.path.basename(file_h)}})
            
        if outfiles:
            self.add_files(outfiles)
        else:
            logger.error("output files not found.")
            raise RuntimeError

        logger.info("-------------------------------------------")
        logger.info("End Generator regtool")
        logger.info("-------------------------------------------")

if __name__ == '__main__':
    g = regtool()
    g.run()
    g.write()
