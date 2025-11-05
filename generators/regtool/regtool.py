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
        # Align le levelname à 8 caractères (DEBUG, INFO, WARNING, etc.)
        record.levelname = f"[{record.levelname:<8}]"  # left-align to 8 chars
        return super().format(record)

class regtool(Generator):
    def run(self):

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

        files_hdl     = ["csr_pkg.vhd","csr_reg.vhd","csr_ext.vhd","csr_fifo.vhd"]
        dir_hdl       = os.path.join(dir_script,"tools","regtool","hdl",)

        file_vhdl_pkg = os.path.join(dir_work,name+'_csr_pkg.vhd')
        file_vhdl_csr = os.path.join(dir_work,name+'_csr.vhd')    
        file_h        = os.path.join(dir_work,name+'_csr.h')    
        file_md       = os.path.join(dir_work,name+'_csr.md')    
        copy          = self.config.get("copy",None)
        logical_name  = self.config.get("logical_name",None)

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
        
        args =  [script,file_in,"--vhdl_package" ,file_vhdl_pkg,"--vhdl_module",file_vhdl_csr,"--c_header",file_h,"--doc_markdown",file_md]
        
        if (logical_name == None):
            libname = "work"
            args.extend(["--logical_name",'work'])
        else:
            libname = logical_name
            args.extend(["--logical_name",logical_name])

        # Configuration du projet
        config = {
            "python"       : "python3",
            "regtool"      : script,
            "libname"      : libname,
            "file_in"      : file_in,
            "file_vhdl_pkg": file_vhdl_pkg,
            "file_vhdl_csr": file_vhdl_csr,
            "file_md"      : file_md,
            "file_h"       : file_h,
            "dir_script"   : dir_script
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

        if (logical_name == None):
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

        if copy != None:
            logger.info(f"Copy generated files in {dir_copy}")
            shutil.copy(file_vhdl_pkg, dir_copy)
            shutil.copy(file_vhdl_csr, dir_copy)
            shutil.copy(file_h       , dir_copy)
            shutil.copy(file_md      , dir_copy)
        
        logger.info("-------------------------------------------")
        logger.info("End Generator regtool")
        logger.info("-------------------------------------------")

if __name__ == '__main__':
    g = regtool()
    g.run()
    g.write()
