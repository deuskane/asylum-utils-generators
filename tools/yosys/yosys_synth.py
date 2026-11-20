#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# Title      : Summary of the Yosys synthesis reports
# Project    : Asylum
#-----------------------------------------------------------------------------
# File       : yosys_synth.py
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Called by yosys_synth.mk (syn_* targets) in the fusesoc
#              work_root. Reads the stat -json reports of the two flows,
#              <toplevel>_xc7.json and <toplevel>_asic.json, writes the
#              summary <toplevel>_syn.json and prints it:
#              - xc7  : LUT, LUTRAM, FF, BRAM (36 Kb blocks), DSP
#              - asic : area (um2) and number of cells
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-20  1.0      mrosiere Created
#-----------------------------------------------------------------------------

import argparse
import json

# Artix-7 cells of synth_xilinx counted in each resource, with their weight.
# The other cells are not counted (CARRY4, MUXF7, MUXF8, and the INV that
# synth_xilinx leaves on the flip-flop control pins: Vivado absorbs them).
XC7_RESOURCES = {
    "LUT"    : {"LUT1" : 1, "LUT2" : 1, "LUT3" : 1, "LUT4" : 1, "LUT5" : 1, "LUT6" : 1},
    # LUTs used as memory or shift register
    "LUTRAM" : {"RAM32X1S" : 1, "RAM64X1S" : 1, "RAM128X1S" : 2, "RAM256X1S" : 4,
                "RAM32X1D" : 2, "RAM64X1D" : 2, "RAM128X1D" : 4,
                "RAM32M"   : 4, "RAM64M"   : 4,
                "SRL16E"   : 1, "SRLC32E"  : 1},
    "FF"     : {"FDRE" : 1, "FDSE" : 1, "FDCE" : 1, "FDPE" : 1,
                "FDRE_1" : 1, "FDSE_1" : 1, "FDCE_1" : 1, "FDPE_1" : 1},
    # 36 Kb blocks (a RAMB18E1 is half a block)
    "BRAM"   : {"RAMB36E1" : 1, "RAMB18E1" : 0.5},
    "DSP"    : {"DSP48E1" : 1},
}

#--------------------------------------------
#--------------------------------------------
def read_stat(path):
    """
    Read a report of "stat -json".

    :param path: report file
    :return: statistics of the design (num_cells, num_cells_by_type, area)
    :raises KeyError: no "design" section in the report
    """
    with open(path) as file:
        report = json.load(file)

    if "design" not in report:
        raise KeyError(f"{path} : no \"design\" section (no top module ?)")

    return report["design"]

#--------------------------------------------
#--------------------------------------------
def summary_xc7(stat):
    """
    Artix-7 resources of a design.

    :param stat: statistics of the design (read_stat)
    :return: dictionary resource : count (XC7_RESOURCES)
    """
    cells = stat["num_cells_by_type"]

    return {resource : sum(count * weights.get(cell, 0) for cell, count in cells.items())
            for resource, weights in XC7_RESOURCES.items()}

#--------------------------------------------
#--------------------------------------------
def summary_asic(stat):
    """
    Standard cell area of a design.

    :param stat: statistics of the design (read_stat, stat -liberty)
    :return: dictionary with area_um2 and cells
    """
    return {"area_um2" : round(stat.get("area", 0), 2),
            "cells"    : stat["num_cells"]}

#--------------------------------------------
#--------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Summary of the Yosys synthesis reports of yosys_synth.mk")
    parser.add_argument("toplevel", help="toplevel : reads <toplevel>_xc7.json and <toplevel>_asic.json, writes <toplevel>_syn.json")
    args   = parser.parse_args()

    summary = {"xc7"  : summary_xc7 (read_stat(f"{args.toplevel}_xc7.json")),
               "asic" : summary_asic(read_stat(f"{args.toplevel}_asic.json"))}

    with open(f"{args.toplevel}_syn.json", "w") as file:
        json.dump(summary, file, indent=2)
        file.write("\n")

    print("yosys_synth : xc7  : " + ", ".join(f"{resource} {count:g}" for resource, count in summary["xc7"].items()))
    print(f"yosys_synth : asic : {summary['asic']['area_um2']:g} um2, {summary['asic']['cells']} cells")
    print(f"yosys_synth : PASS (reports {args.toplevel}_syn.json, {args.toplevel}_xc7.log, {args.toplevel}_asic.log)")

#--------------------------------------------
#--------------------------------------------
if __name__ == "__main__":
    main()
