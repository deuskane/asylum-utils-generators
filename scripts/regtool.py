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
from fusesoc.capi2.generator import Generator
import subprocess
from fusesoc.utils           import Launcher
from glob                    import glob
from pathlib                 import Path

class regtool(Generator):
    def run(self):

        print( "[INFO   ]-------------------------------------------")
        print( "[INFO   ] Start Generator regtool")
        print( "[INFO   ]-------------------------------------------")
        print(f"[DEBUG  ] Work Directory     : {os.getcwd()}")

        #-------------------------------------------------
        # Get parameters
        #-------------------------------------------------
        name          = self.config.get("name")
        file_in       = os.path.join(self.files_root,self.config.get("file"))
        dir_script    = Path(__file__).resolve().parent.parent
        script        = os.path.join(dir_script,"tools","regtool","regtool.py")

        file_csr      = os.path.join(dir_script,"tools","regtool","hdl","csr_reg.vhd")
        file_vhdl_pkg = os.path.join(os.getcwd(),name+'_csr_pkg.vhd')
        file_vhdl_csr = os.path.join(os.getcwd(),name+'_csr.vhd')    
        file_h        = os.path.join(os.getcwd(),name+'_csr.h')    
        
        #-------------------------------------------------
        # Summary of parameters
        #-------------------------------------------------
        print(f"[DEBUG  ] File In            : {file_in}")
        print(f"[DEBUG  ] Script             : {script}")
        print(f"[DEBUG  ] Name               : {name}")
        print(f"[DEBUG  ] file_csr           : {file_csr}")
        print(f"[DEBUG  ] file_vhdl_pkg      : {file_vhdl_pkg}")
        print(f"[DEBUG  ] file_vhdl_csr      : {file_vhdl_csr}")
        print(f"[DEBUG  ] file_h             : {file_h}")

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

        print("[INFO   ]-------------------------------------------")
        print("[INFO   ] End Generator regtool")
        print("[INFO   ]-------------------------------------------")

if __name__ == '__main__':
    g = regtool()
    g.run()
    g.write()
