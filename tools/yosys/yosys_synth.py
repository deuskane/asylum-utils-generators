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
#              - xc7  : every cell of the netlist in LUT (INV included),
#                       LUTRAM, FF, CARRY4, MUXF7/F8, BRAM (36 Kb blocks),
#                       DSP ; an unclassified cell type is an error
#              - asic : area (um2), area in kGE (NAND2 equivalents, area of
#                       the reference cell read in the liberty) and
#                       number of cells
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-20  1.0      mrosiere Created
#-----------------------------------------------------------------------------

import argparse
import json
import re

# Artix-7 cells of synth_xilinx counted in each resource, with their weight.
# Every cell of the netlist is counted: a cell type missing here is an error
# (summary_xc7), so that nothing disappears silently from the count.
XC7_RESOURCES = {
    # An INV is a LUT1
    "LUT"    : {"LUT1" : 1, "LUT2" : 1, "LUT3" : 1, "LUT4" : 1, "LUT5" : 1, "LUT6" : 1,
                "INV"  : 1},
    # LUTs used as memory or shift register
    "LUTRAM" : {"RAM32X1S" : 1, "RAM64X1S" : 1, "RAM128X1S" : 2, "RAM256X1S" : 4,
                "RAM32X1D" : 2, "RAM64X1D" : 2, "RAM128X1D" : 4,
                "RAM32M"   : 4, "RAM64M"   : 4,
                "SRL16E"   : 1, "SRLC32E"  : 1},
    "FF"     : {"FDRE" : 1, "FDSE" : 1, "FDCE" : 1, "FDPE" : 1,
                "FDRE_1" : 1, "FDSE_1" : 1, "FDCE_1" : 1, "FDPE_1" : 1},
    "CARRY4" : {"CARRY4" : 1},
    "MUXF7/F8" : {"MUXF7" : 1, "MUXF8" : 1},
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
    :raises ValueError: cell type not in XC7_RESOURCES
    """
    cells        = stat["num_cells_by_type"]
    unclassified = [cell for cell in cells if not any(cell in weights for weights in XC7_RESOURCES.values())]
    if unclassified:
        raise ValueError(f"xc7 : cell types not counted, to add to XC7_RESOURCES : {', '.join(sorted(unclassified))}")

    return {resource : sum(count * weights.get(cell, 0) for cell, count in cells.items())
            for resource, weights in XC7_RESOURCES.items()}

#--------------------------------------------
#--------------------------------------------
def cell_area(liberty, cell):
    """
    Area of a cell in a liberty file.

    :param liberty: liberty file
    :param cell: cell name (e.g. sky130_fd_sc_hd__nand2_1)
    :return: area of the cell (um2)
    :raises ValueError: cell or area not found
    """
    with open(liberty) as file:
        text = file.read()

    match = re.search(r'cell\s*\(\s*"?' + re.escape(cell) + r'"?\s*\).*?\barea\s*:\s*([0-9.]+)', text, re.S)
    if not match:
        raise ValueError(f"{liberty} : no area for the cell {cell}")

    return float(match.group(1))

#--------------------------------------------
#--------------------------------------------
def summary_asic(stat, nand2_area):
    """
    Standard cell area of a design.

    :param stat: statistics of the design (read_stat, stat -liberty)
    :param nand2_area: area of the NAND2 reference cell (um2)
    :return: dictionary with area_um2, kge (area in thousands of NAND2) and cells
    """
    area = stat.get("area", 0)

    return {"area_um2" : round(area, 2),
            "kge"      : round(area / nand2_area / 1000, 3),
            "cells"    : stat["num_cells"]}

#--------------------------------------------
#--------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Summary of the Yosys synthesis reports of yosys_synth.mk")
    parser.add_argument("toplevel", help="toplevel : reads <toplevel>_xc7.json and <toplevel>_asic.json, writes <toplevel>_syn.json")
    parser.add_argument("--liberty", required=True, help="liberty file of the asic flow")
    parser.add_argument("--nand2", required=True, help="NAND2 reference cell of the gate equivalent")
    args   = parser.parse_args()

    summary = {"xc7"  : summary_xc7 (read_stat(f"{args.toplevel}_xc7.json")),
               "asic" : summary_asic(read_stat(f"{args.toplevel}_asic.json"), cell_area(args.liberty, args.nand2))}

    with open(f"{args.toplevel}_syn.json", "w") as file:
        json.dump(summary, file, indent=2)
        file.write("\n")

    print("yosys_synth : xc7  : " + ", ".join(f"{resource} {count:g}" for resource, count in summary["xc7"].items()))
    print(f"yosys_synth : asic : {summary['asic']['area_um2']:g} um2, {summary['asic']['kge']:.3f} kGE, {summary['asic']['cells']} cells")
    print(f"yosys_synth : PASS (reports {args.toplevel}_syn.json, {args.toplevel}_xc7.log, {args.toplevel}_asic.log)")

#--------------------------------------------
#--------------------------------------------
if __name__ == "__main__":
    main()
