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
# 2021-11-19  1.2      mrosiere Add options
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
    description     : Simulation of the test ${file_name}
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
# build_toolchain_usage
#-----------------------------------------------------------------------------
# Display usage message
#-----------------------------------------------------------------------------
function gen_target_usage()
{
    echo "$0 usage:"
    grep " .)\ ##" $0

    echo ""
    echo "Update core file and create Makefile"
    echo "ASM files have the psm extension. The \"pblazeide\" asm files and \"kcpsm3\" asm files must be in separate directory"
    echo "C   files have the c   extension."
    echo "All sources files must be single file".
}

#-----------------------------------------------------------------------------
# gen_target_main
#-----------------------------------------------------------------------------
# Generate all tools and ROM
#-----------------------------------------------------------------------------
function gen_target_main()
{
    # Chek argument
    echo "Check arguments"
    while getopts ":p:k:c:f:h" arg; do
	case $arg in
	    f) ## Core File (mandatory)
		file_core=${OPTARG}
		if test ! -f "${file_core}";
		then
		    echo "Invalid file core : ${file_core}";
		    gen_target_usage
		    exit -1;
		fi
		;;
	    p) ## ASM pblazeide source directory
		dir_asm_pblazeide=${OPTARG}

		if test ! -d "${dir_asm_pblazeide}";
		then
		    echo "Invalid directory : ${dir_asm_pblazeide}";
		    gen_target_usage
		    exit -1;
		fi

		;;
	    k) ## ASM kcpsm3 source directory
		dir_asm_kcpsm3=${OPTARG}

		if test ! -d "${dir_asm_kcpsm3}";
		then
		    echo "Invalid directory : ${dir_asm_kcpsm3}";
		    gen_target_usage
		    exit -1;
		fi

		;;
	    c) ## C source directory
		dir_c=${OPTARG}


		if test ! -d "${dir_c}";
		then
		    echo "Invalid directory : ${dir_c}";
		    gen_target_usage
		    exit -1;
		fi

		;;
	    h | *) ## Display help
		echo "${OPTARG}"
		gen_target_usage
		exit 0
		;;
	esac
    done

    # Check Arguments
    if test -z "${file_core}";
    then
	echo "File Core must be define";
	gen_target_usage
	exit -1;
    fi
    
    # Directory
    dir_ip=`dirname ${file_core}`

    # File
    file_make=${dir_ip}/mk/targets.mk

    # Create tmp file
    rm -f /tmp/test_core_filesets.txt
    rm -f /tmp/test_core_generate.txt
    rm -f /tmp/test_core_targets.txt
    rm -f /tmp/test_make.txt

    touch /tmp/test_core_filesets.txt
    touch /tmp/test_core_generate.txt
    touch /tmp/test_core_targets.txt
    touch /tmp/test_make.txt

    # Scan source file
    dir_ip=${dir_ip}/

    echo "Scan source directory"
    if test -n "${dir_asm_pblazeide}";
    then
	echo " * ASM (pblazeide)"
	for f in `find ${dir_asm_pblazeide}/*.psm`; do
	    echo "   * ${f}" 

	    file_name=${f/${dir_ip}/}
	    test_name=`basename ${f/.psm/}`
	    target_name=asm_${test_name}

	    gen_target_add_target ${file_name} "pblazeide" ${target_name}
	    
	done
    fi
    
    if test -n "${dir_asm_kcpsm3}";
    then
	echo " * ASM (kcpsm3)"
	for f in `find ${dir_asm_kcpsm3}/*.psm`; do
	    echo "   * ${f}" 

	    file_name=${f/${dir_ip}/}
	    test_name=`basename ${f/.psm/}`
	    target_name=asm_${test_name}
	    
	    gen_target_add_target ${file_name} "kcpsm3" ${target_name}
	    
	done
    fi
    
    if test -n "${dir_c}";
    then
	echo " * C"
	for f in `find ${dir_c}/*.c`; do
	    echo "   * ${f}" 

	    file_name=${f/${dir_ip}/}
	    test_name=`basename ${f/.c/}`
	    target_name=c_${test_name}

	    gen_target_add_target ${file_name} "c" ${target_name}
	    
	done
    fi

    # Edit Core File
    echo "Edit Core File"
    
    sed -i '/<FILESETS_BEGIN>/,/<FILESETS_END>/{/<FILESETS_BEGIN>/!{/<FILESETS_END>/!d}}' ${file_core}
    sed -i '/<GENERATE_BEGIN>/,/<GENERATE_END>/{/<GENERATE_BEGIN>/!{/<GENERATE_END>/!d}}' ${file_core}
    sed -i '/<TARGETS_BEGIN>/,/<TARGETS_END>/{/<TARGETS_BEGIN>/!{/<TARGETS_END>/!d}}'     ${file_core}

    sed -i '/<FILESETS_BEGIN>/r /tmp/test_core_filesets.txt'                              ${file_core}
    sed -i '/<GENERATE_BEGIN>/r /tmp/test_core_generate.txt'                              ${file_core}
    sed -i '/<TARGETS_BEGIN>/r  /tmp/test_core_targets.txt'                               ${file_core}

    # Generate Makefile
    echo "Generate Makefile"
    mkdir -p ${dir_ip}/mk
    	
    cp /tmp/test_make.txt ${file_make}

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

    echo "Done"

}

gen_target_main $*
