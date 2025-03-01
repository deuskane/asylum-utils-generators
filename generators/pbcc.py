#-----------------------------------------------------------------------------
# Title      : pbcc Generator
# Project    : Asylum
#-----------------------------------------------------------------------------
# File       : pbcc.py
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: 
#-----------------------------------------------------------------------------
# Copyright (c) 2021
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2021-11-03  1.0      mrosiere Created
#-----------------------------------------------------------------------------

import os

import sys
from fusesoc.capi2.generator import Generator
import subprocess
from fusesoc.utils           import Launcher
from glob                    import glob
from pathlib                 import Path

class pbcc(Generator):
    def run(self):

        print("[INFO   ]-------------------------------------------")
        print("[INFO   ] Start Generator pbcc")
        print("[INFO   ]-------------------------------------------")
        print("[DEBUG  ] Work Directory    : {0}".format(os.getcwd()))

        #-------------------------------------------------
        # Get parameters
        #-------------------------------------------------
        file_in     = os.path.join(self.files_root,self.config.get("file"))
        file_vhd    = Path(file_in).stem + ".vhd"
        file_type   = self.config.get("type")
        cflags      = self.config.get("cflags")

        if cflags is None:
            cflags = ""
        
        if (not file_type in ["c","kcpsm3","pblazeide"]):
            raise RuntimeError("[ERROR  ] Unknown file type: {0}. Possible options are \"c\", \"kcpsm3\" or \"pblazeide\"".format(file_type))

        if (file_type in ["c"]):
            file_c      = file_in
            file_psm    = Path(file_in).stem + ".psm"
        else:
            file_c      = ""
            file_psm    = file_in
            
        rom_entity  = self.config.get("entity","OpenBlaze8_ROM")

        rom_model   = self.config.get("model","generic")

        if (not rom_model in ["generic","xilinx"]):
            raise RuntimeError("[ERROR  ] Unknown rom model: {0}. Possible options are \"generic\" (default), or \"xilinx\"".format(rom_model))

        
        #-------------------------------------------------
        # Summary of parameters
        #-------------------------------------------------
        print("[DEBUG  ] File C            : {0}".format(file_c    ))
        print("[DEBUG  ] File PSM          : {0}".format(file_psm  ))
        print("[DEBUG  ] File VHD          : {0}".format(file_vhd  ))
        print("[DEBUG  ] File Type         : {0}".format(file_type ))
        print("[DEBUG  ] ROM entity        : {0}".format(rom_entity))
        print("[DEBUG  ] ROM model         : {0}".format(rom_model ))
        print("[DEBUG  ] CFLAGS            : {0}".format(cflags    ))
        
        #-------------------------------------------------
        # Convert C to PSM (in kcpsm3 dialect)
        #-------------------------------------------------
        if (file_c) :
            if "PBCC_HOME" in os.environ:
                pbcc_home = os.environ["PBCC_HOME"]
            else:
                raise RuntimeError("[ERROR  ] PBCC_HOME environment variable is undefined")

            include_path = os.path.join(pbcc_home, "share", "sdcc", "include")
            
            print("[INFO   ] Translate C to PSM");
            print("[DEBUG  ] PBCC_HOME         : {0}".format(pbcc_home))
            args =  cflags.split() + ["-I" + include_path, "-V", "-S", "--dialect=kcpsm3", file_c]

            print(f"{args}")
            try:
                Launcher(pbcc_home + "/bin/sdcc", args).run()
            except subprocess.CalledProcessError as e:
                raise RuntimeError("[ERROR  ] " + str(e))

            file_type = "kcpsm3"

        #-------------------------------------------------
        # Convert PSM to ROM
        #-------------------------------------------------
        if "PICOASM_HOME" in os.environ:
            picoasm_home = os.environ["PICOASM_HOME"]
        else:
            raise RuntimeError("[ERROR  ] PICOASM_HOME environment variable is undefined")
            
        print("[INFO   ] Translate PSM to VHD");
        print("[DEBUG  ] PICOASM_HOME      : {0}".format(picoasm_home))
        args = ["-t" + picoasm_home + "/share/picoasm/"+rom_model+"/ROM_form.vhd","-v", "-m"+rom_entity, "-d.","-i"+file_psm,"-a"+file_type]
        try:
            Launcher(picoasm_home + "/bin/picoasm", args).run()
        except subprocess.CalledProcessError as e:
            raise RuntimeError("[ERROR  ] " + str(e))

        #-------------------------------------------------
        # Add outfile in source files
        #-------------------------------------------------
        outfiles = []
        outfiles.append({file_vhd : {'file_type' : 'vhdlSource'}})

        if outfiles:
            self.add_files(outfiles)
        else:
            raise RuntimeError("[ERROR  ] output files not found.")
        print("[INFO   ]-------------------------------------------")
        print("[INFO   ] End Generator pbcc")
        print("[INFO   ]-------------------------------------------")

if __name__ == '__main__':
    g = pbcc()
    g.run()
    g.write()
