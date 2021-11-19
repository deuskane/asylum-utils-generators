#!/bin/bash

#-----------------------------------------------------------------------------
# Title      : Build script
# Project    : OpenBlaze8
#-----------------------------------------------------------------------------
# File       : build_toolchain.sh
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

#-----------------------------------------------------------------------------
# build_toolchain_sdcc
#-----------------------------------------------------------------------------
# Argument 1 : SDCC source  directory
# Argument 2 : SDCC install directory
#-----------------------------------------------------------------------------
# Build SDCC tool
#-----------------------------------------------------------------------------
function build_toolchain_sdcc()
{
    local dir_src=$1
    local dir_install=$2
    local dir_build=${dir_src}/build.sdcc

    mkdir -p ${dir_build}
    cd       ${dir_build}

    chmod +x ${dir_src}/configure
    chmod +x ${dir_src}/sim/ucsim/mkecho

    echo "[SDCC] Configure"
    ${dir_src}/configure \
	--prefix=${dir_install} \
	--disable-{pic14,pic16,hc08,stm8,ds390,ds400,z80,mcs51,s08,z180,r2k,r3ka,gbz80,tlcs90}-port \
	--disable-sdbinutils  \
	--disable-device-lib  \
	--disable-ucsim       \
	--disable-sdcdb       \
	--disable-packihx

    echo "[SDCC] Build"
    make -j

    echo "[SDCC] Install"
    make -j install

    cd -
}

#-----------------------------------------------------------------------------
# build_toolchain_picoasm
#-----------------------------------------------------------------------------
# Argument 1 : PICOASM Source directory
# Argument 2 : PICOASM install directory
#-----------------------------------------------------------------------------
# Build PICOASM tool
#-----------------------------------------------------------------------------
function build_toolchain_picoasm()
{
    local dir_src=$1
    local dir_install=$2

    echo "[PICOASM] Build"
    make -C ${dir_src} -j

    echo "[PICOASM] Install"
    mkdir -p   ${dir_install}/bin
    mkdir -p   ${dir_install}/share/picoasm/xilinx
    mkdir -p   ${dir_install}/share/picoasm/generic

    cp ${dir_src}/picoasm ${dir_install}/bin

    cp ${dir_src}/ROM_form.v      ${dir_install}/share/picoasm/xilinx
    cp ${dir_src}/ROM_form.vhd    ${dir_install}/share/picoasm/xilinx
    cp ${dir_src}/../ROM_form.vhd ${dir_install}/share/picoasm/generic

}

#-----------------------------------------------------------------------------
# build_toolchain_usage
#-----------------------------------------------------------------------------
# Display usage message
#-----------------------------------------------------------------------------
function build_toolchain_usage()
{
    echo "$0 usage:"
    grep " .)\ ##" $0
}
 
#-----------------------------------------------------------------------------
# build_toolchain_main
#-----------------------------------------------------------------------------
# Generate all tools and ROM
#-----------------------------------------------------------------------------
function build_toolchain_main()
{
    # Directory
    dir_tools=`/bin/pwd`
    dir_picoasm=${dir_tools}/picoasm
    dir_sdcc=${dir_tools}/pbccv2-src-20110901/sdcc3
    dir_install=${dir_tools}/install
    
    BUILD_TOOLCHAIN_SDCC=false
    BUILD_TOOLCHAIN_PICOASM=false

    while getopts ":hspi:" arg; do
	case $arg in
	    s) ## Build SDCC
		BUILD_TOOLCHAIN_SDCC=true
		;;
	    p) ## Build PicoASM
		BUILD_TOOLCHAIN_PICOASM=true
		;;
	    i) ## Install directory
		dir_install=${OPTARG}
		;;
	    h | *) ## Display help
		build_toolchain_usage
		exit 0
		;;
	esac
    done

    # SDCC Compilation
    if ${BUILD_TOOLCHAIN_SDCC};
    then
	build_toolchain_sdcc    ${dir_sdcc} ${dir_install}
    fi

    # Picoasm Compilation
    if ${BUILD_TOOLCHAIN_PICOASM};
    then
	build_toolchain_picoasm ${dir_picoasm} ${dir_install}
    fi

}

build_toolchain_main $*
