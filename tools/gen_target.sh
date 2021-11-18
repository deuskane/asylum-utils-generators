#!/bin/bash

#-----------------------------------------------------------------------------
# Title      : Gen_Target script
# Project    : OpenBlaze8
#-----------------------------------------------------------------------------
# File       : gen_target.sh
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: 
#-----------------------------------------------------------------------------
# Copyright (c) 2021
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2021-10-26  1.0      mrosiere Created
# 2021-11-03  1.1      mrosiere Use generator
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# gen_target_add_target
#-----------------------------------------------------------------------------
# Argument 1 : ROM file (VHDL file)
# Argument 2 : test name
# Argument 3 : Target name
#-----------------------------------------------------------------------------
# Append 3 files with argument information
# -> update core file (filesets section and targets section)
# -> update Makfile 
#-----------------------------------------------------------------------------
function gen_target_add_target()
{
    file_name=${1}
    file_type=${2}
    target_name=${3}

    cat <<EOT >> /tmp/test_core_generate.txt
  gen_${target_name}:
    generator : pbcc_gen
    parameters:
      file: ${file_name}
      type: ${file_type}

EOT

	cat <<EOT >> /tmp/test_core_targets.txt
  sim_${target_name}:
    << : *sim
    description     : Simulation tof the test ${file_name}
    filesets_append :
      - files_sim
      - pbcc_dep
    generate : [gen_${target_name}]

EOT

	cat <<EOT >> /tmp/test_make.txt
TARGETS += sim_${target_name}
EOT
}

#-----------------------------------------------------------------------------
# gen_target_main
#-----------------------------------------------------------------------------
# Argument 1 : Core File
# Argument 2 : Directory with asm (pblazeide) source code
# Argument 3 : Directory with c               source code
#-----------------------------------------------------------------------------
# Generate all tools and ROM
#-----------------------------------------------------------------------------
function gen_target_main()
{
    # Directory
    dir_ip=`/bin/pwd`
    dir_test_asm=${2}
    dir_test_c=${3}

    # File
    file_core=${1}
    file_make=${dir_ip}/mk/targets.mk
    
    mkdir -p ${dir_ip}/mk
    	
    rm -f /tmp/test_core_filesets.txt
    rm -f /tmp/test_core_generate.txt
    rm -f /tmp/test_core_targets.txt
    rm -f /tmp/test_make.txt

    touch /tmp/test_core_filesets.txt
    touch /tmp/test_core_generate.txt
    touch /tmp/test_core_targets.txt
    touch /tmp/test_make.txt

    dir_ip=${dir_ip}/
    for f in `find ${dir_test_asm}/*.psm`; do

	file_name=${f/${dir_ip}/}
	test_name=`basename ${f/.psm/}`
	target_name=asm_${test_name}
	
	gen_target_add_target ${file_name} "pblazeide" ${target_name}
	
    done

    for f in `find ${dir_test_c}/*.c`; do

	file_name=${f/${dir_ip}/}
	test_name=`basename ${f/.c/}`
	target_name=c_${test_name}

	gen_target_add_target ${file_name} "c" ${target_name}
	
    done

    # Edit Core File
    sed -i '/<FILESETS_BEGIN>/,/<FILESETS_END>/{/<FILESETS_BEGIN>/!{/<FILESETS_END>/!d}}' ${file_core}
    sed -i '/<GENERATE_BEGIN>/,/<GENERATE_END>/{/<GENERATE_BEGIN>/!{/<GENERATE_END>/!d}}' ${file_core}
    sed -i '/<TARGETS_BEGIN>/,/<TARGETS_END>/{/<TARGETS_BEGIN>/!{/<TARGETS_END>/!d}}'     ${file_core}

    sed -i '/<FILESETS_BEGIN>/r /tmp/test_core_filesets.txt'                              ${file_core}
    sed -i '/<GENERATE_BEGIN>/r /tmp/test_core_generate.txt'                              ${file_core}
    sed -i '/<TARGETS_BEGIN>/r  /tmp/test_core_targets.txt'                               ${file_core}

    # Edit Targets
    cp /tmp/test_make.txt ${file_make}

    # Generate Makefile
    rm -f Makefile
    cat <<EOT >> ${dir_ip}/Makefile
#-----------------------------------------------------------------------------
# Auto-generate file
#-----------------------------------------------------------------------------

#=============================================================================
# Variables
#=============================================================================
SHELL      = /bin/bash
FILE_CORE  = ${file_core}
CORE      ?= \$(shell grep name \$(FILE_CORE) | head -n1| cut -d' ' -f3)
include mk/targets.mk

#=============================================================================
# Rules
#=============================================================================

help    :
	@echo "=========| Variables"
	@echo "CORE     : \$(CORE)"
	@echo ""
	@echo "=========| Rules"
	@echo "help     : Print this message"
	@echo "run      : run all targets"
	@echo "run_%    : run one target"
	@echo "clean    : delete build directory"
	@echo ""
	@echo "=========| Targets"
	@for target in \$(TARGETS); do echo \$\${target}; done

.PHONY  : list

run	: \$(addprefix run_,\$(TARGETS))

.PHONY	: run

run_%	:
	@echo "[\$*]"
	fusesoc run --build-root build-\$* --run --target \$* \$(CORE)

.PHONY	: run_%


clean	:
	rm -fr build build-*

.PHONY	: clean
EOT

}

gen_target_main $*
