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
from   fusesoc.capi2.generator import Generator
import subprocess
from   fusesoc.utils           import Launcher
from   glob                    import glob
from   pathlib                 import Path
from   jinja2                  import Environment, FileSystemLoader

import logging

class AlignedFormatter(logging.Formatter):
    def format(self, record):
        # Align le levelname à 8 caractères (DEBUG, INFO, WARNING, etc.)
        record.levelname = f"[{record.levelname:<8}]"  # left-align to 8 chars
        return super().format(record)

class pbcc(Generator):

    def update_paths(self,options, files_root):
        updated_options = []
        for option in options:
            #print(option)
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

        # Configuration du logger
        handler   = logging.StreamHandler()
        formatter = AlignedFormatter('%(levelname)s %(message)s')
        handler.setFormatter(formatter)
        
        logger    = logging.getLogger()
        logger.setLevel(logging.INFO)
        logger.handlers = [handler]
        
        logger.info("-------------------------------------------")
        logger.info("Start Generator pbcc")
        logger.info("-------------------------------------------")
        logger.debug("Work Directory    : {0}".format(os.getcwd()))

        #-------------------------------------------------
        # Get parameters
        #-------------------------------------------------
        file_in     = os.path.join(self.files_root,self.config.get("file"))
        file_vhd    = Path(file_in).stem + ".vhd"
        file_type   = self.config.get("type")
        cflags      = self.config.get("cflags")
        logical_name= self.config.get("logical_name",None)

        if cflags is None:
            cflags = ""

        cflags = self.update_paths(cflags.split(),self.files_root)
        
        if (not file_type in ["c","kcpsm3","pblazeide"]):
            logger.error("Unknown file type: {0}. Possible options are \"c\", \"kcpsm3\" or \"pblazeide\"".format(file_type))
            raise RuntimeError

        if (file_type in ["c"]):
            file_c      = file_in
            file_psm    = Path(file_in).stem + ".psm"
        else:
            file_c      = ""
            file_psm    = file_in
            
        rom_entity  = self.config.get("entity","OpenBlaze8_ROM")

        rom_model   = self.config.get("model","generic")

        if (not rom_model in ["generic","xilinx"]):
            logger.error("Unknown rom model: {0}. Possible options are \"generic\" (default), or \"xilinx\"".format(rom_model))
            raise RuntimeError

        
        #-------------------------------------------------
        # Summary of parameters
        #-------------------------------------------------
        logger.debug("File C            : {0}".format(file_c    ))
        logger.debug("File PSM          : {0}".format(file_psm  ))
        logger.debug("File VHD          : {0}".format(file_vhd  ))
        logger.debug("File Type         : {0}".format(file_type ))
        logger.debug("ROM entity        : {0}".format(rom_entity))
        logger.debug("ROM model         : {0}".format(rom_model ))
        logger.debug("CFLAGS            : {0}".format(cflags    ))
        
        #-------------------------------------------------
        # Convert C to PSM (in kcpsm3 dialect)
        #-------------------------------------------------
        pbcc_home    = ""
        include_path = "";
        
        if (file_c) :
            if "PBCC_HOME" in os.environ:
                pbcc_home = os.environ["PBCC_HOME"]
            else:
                logger.error("PBCC_HOME environment variable is undefined")
                raise RuntimeError

            include_path = os.path.join(pbcc_home, "share", "sdcc", "include")
            
            logger.info("Translate C to PSM");
            logger.debug("PBCC_HOME         : {0}".format(pbcc_home))

            file_type = "kcpsm3"

        #-------------------------------------------------
        # Convert PSM to ROM
        #-------------------------------------------------
        if "PICOASM_HOME" in os.environ:
            picoasm_home = os.environ["PICOASM_HOME"]
        else:
            logger.error("PICOASM_HOME environment variable is undefined")
            raise RuntimeError
            
        logger.info ("Translate PSM to VHD");
        logger.debug("PICOASM_HOME      : {0}".format(picoasm_home))

        #-------------------------------------------------
        # Call Jinja2
        #-------------------------------------------------
        # Configuration du projet
        config = {
            "pbcc_home"     : pbcc_home    ,
            "pbcc"          : os.path.join(pbcc_home,"bin","sdcc") ,
            "pbcc_incdir"   : include_path  ,
            "picoasm_home"  : picoasm_home ,
            "picoasm"       : os.path.join(picoasm_home,"bin","picoasm") ,
            "file_c"        : file_c       ,
            "file_psm"      : file_psm     ,
            "file_vhd"      : file_vhd     ,
            "file_type"     : file_type    ,
            "file_rom"      : os.path.join(picoasm_home,"share","picoasm",rom_model,"ROM_form.vhd") ,
            "rom_entity"    : rom_entity   ,
            "rom_model"     : rom_model    ,
            "cflags"        : cflags       ,
            "file_in"       : file_in      
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
            outfiles.append({file_vhd : {'file_type' : 'vhdlSource'}})
        else:
            outfiles.append({file_vhd : {'file_type' : 'vhdlSource', 'logical_name' : logical_name}})

        if outfiles:
            self.add_files(outfiles)
        else:
            logger.error("output files not found.")
            raise RuntimeError
        logger.info("-------------------------------------------")
        logger.info("End Generator pbcc")
        logger.info("-------------------------------------------")

if __name__ == '__main__':
    g = pbcc()
    g.run()
    g.write()
