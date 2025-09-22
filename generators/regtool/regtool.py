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

class regtool(Generator):
    def run(self):

        print( "[INFO   ]-------------------------------------------")
        print( "[INFO   ] Start Generator regtool")
        print( "[INFO   ]-------------------------------------------")
        print(f"[DEBUG  ] Work Directory     : {os.getcwd()}")

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
                raise RuntimeError(f"[ERROR  ] Invalid directory \"{dir_copy}\"")
        else:
            dir_copy = dir_work
            
        #-------------------------------------------------
        # Summary of parameters
        #-------------------------------------------------
        print(f"[DEBUG  ] Name               : {name}")
        print(f"[DEBUG  ] dir_script         : {dir_script}")
        print(f"[DEBUG  ] dir_work           : {dir_work}")  
        print(f"[DEBUG  ] dir_root           : {dir_root}")  
        print(f"[DEBUG  ] dir_copy           : {dir_copy}")
        print(f"[DEBUG  ] dir_hdl            : {dir_hdl}")
        print(f"[DEBUG  ] Script             : {script}")
        print(f"[DEBUG  ] File In            : {file_in}")
        print(f"[DEBUG  ] file_vhdl_pkg      : {file_vhdl_pkg}")
        print(f"[DEBUG  ] file_vhdl_csr      : {file_vhdl_csr}")
        print(f"[DEBUG  ] file_h             : {file_h}")
        print(f"[DEBUG  ] file_md            : {file_md}")
        print(f"[DEBUG  ] Copy               : {copy}")
        print(f"[DEBUG  ] logical_name       : {logical_name}")
        
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
        except subprocess.CalledProcessError as e:
            raise RuntimeError("[ERROR  ] " + str(e))

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
            raise RuntimeError("[ERROR  ] output files not found.")

        if copy != None:
            print(f"[INFO   ] Copy generated files in {dir_copy}")
            shutil.copy(file_vhdl_pkg, dir_copy)
            shutil.copy(file_vhdl_csr, dir_copy)
            shutil.copy(file_h       , dir_copy)
            shutil.copy(file_md      , dir_copy)
        
        print("[INFO   ]-------------------------------------------")
        print("[INFO   ] End Generator regtool")
        print("[INFO   ]-------------------------------------------")

if __name__ == '__main__':
    g = regtool()
    g.run()
    g.write()
