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

class regtool(Generator):
    def run(self):

        print( "[INFO   ]-------------------------------------------")
        print( "[INFO   ] Start Generator regtool")
        print( "[INFO   ]-------------------------------------------")
        print(f"[DEBUG  ] Work Directory     : {os.getcwd()}")

        #-------------------------------------------------
        # Get parameters
        #-------------------------------------------------
        dir_script    = Path(__file__).resolve().parent.parent
        dir_work      = os.getcwd()
        dir_root      = self.files_root

        file_in       = os.path.join(dir_root,self.config.get("file"))

        name          = self.config.get("name")
        script        = os.path.join(dir_script,"tools","regtool","regtool.py")

        file_csr      = os.path.join(dir_script,"tools","regtool","hdl","csr_reg.vhd")
        file_vhdl_pkg = os.path.join(dir_work,name+'_csr_pkg.vhd')
        file_vhdl_csr = os.path.join(dir_work,name+'_csr.vhd')    
        file_h        = os.path.join(dir_work,name+'_csr.h')    
        copy          = self.config.get("copy",None)

        if copy != None:
            dir_copy = os.path.join(dir_root,copy)

            if not os.path.isdir(dir_copy):
                raise RuntimeError(f"[ERROR  ] Invalid directory \"{dir_copy}\"")
        else:
            dir_copy = None
            
        #-------------------------------------------------
        # Summary of parameters
        #-------------------------------------------------
        print(f"[DEBUG  ] Name               : {name}")
        print(f"[DEBUG  ] dir_script         : {dir_script}")
        print(f"[DEBUG  ] dir_work           : {dir_work}")  
        print(f"[DEBUG  ] dir_root           : {dir_root}")  
        print(f"[DEBUG  ] dir_copy           : {dir_copy}")
        print(f"[DEBUG  ] Script             : {script}")
        print(f"[DEBUG  ] File In            : {file_in}")
        print(f"[DEBUG  ] file_csr           : {file_csr}")
        print(f"[DEBUG  ] file_vhdl_pkg      : {file_vhdl_pkg}")
        print(f"[DEBUG  ] file_vhdl_csr      : {file_vhdl_csr}")
        print(f"[DEBUG  ] file_h             : {file_h}")
        print(f"[DEBUG  ] Copy               : {copy}")

        args =  [script,file_in,"--vhdl_package" ,file_vhdl_pkg,"--vhdl_module",file_vhdl_csr,"--c_header",file_h]

        try:
            Launcher("python3", args).run()
        except subprocess.CalledProcessError as e:
            raise RuntimeError("[ERROR  ] " + str(e))

        #-------------------------------------------------
        # Add outfile in source files
        #-------------------------------------------------
        outfiles = []
        outfiles.append({file_csr      : {'file_type' : 'vhdlSource'}})
        outfiles.append({file_vhdl_pkg : {'file_type' : 'vhdlSource'}})
        outfiles.append({file_vhdl_csr : {'file_type' : 'vhdlSource'}})

        if outfiles:
            self.add_files(outfiles)
        else:
            raise RuntimeError("[ERROR  ] output files not found.")

        if copy != None:
            print(f"[INFO   ] Copy generated files in {dir_copy}")
#           shutil.copy(file_csr     , dir_copy)
            shutil.copy(file_vhdl_pkg, dir_copy)
            shutil.copy(file_vhdl_csr, dir_copy)
            shutil.copy(file_h       , dir_copy)
        
        print("[INFO   ]-------------------------------------------")
        print("[INFO   ] End Generator regtool")
        print("[INFO   ]-------------------------------------------")

if __name__ == '__main__':
    g = regtool()
    g.run()
    g.write()
