"""
Simulation of the Verilog CSR with iverilog (skipped if iverilog is not in
the PATH) : sim/tbcsr.hjson generated for each Verilog interface, testbench
sim/tb_regtool.v, one test per interface and scenario (the VHDL output is
simulated by the FuseSoC targets sim_regtool_<interface>_<scenario>).
"""

import glob
import os
import subprocess

import pytest

import csr_model
from conftest import tool, HDL_DIR, REGTOOL_DIR
from gen_hdl  import generate_hdl_module

SIM_DIR   = os.path.join(REGTOOL_DIR, "sim")

SCENARIOS = ["reset", "write_read", "hw_write", "ext", "fifo_read", "fifo_write", "unmapped"]

CASES     = [(itf, test) for itf in ["mem", "apb", "axi4lite"] for test in SCENARIOS] + \
            [("axi4lite", "axi_concurrent")]

#--------------------------------------------
@pytest.mark.parametrize("interface, test", CASES)
def test_sim_verilog(tmp_path, interface, test):
    iverilog = tool("iverilog")
    vvp      = tool("vvp")

    csr = csr_model.parse_hjson(os.path.join(SIM_DIR, "tbcsr.hjson"), interface=interface)
    generate_hdl_module(csr, str(tmp_path / "tbcsr_csr.v"), "verilog")

    files = sorted(glob.glob(os.path.join(HDL_DIR, "*.v"))) + \
            [str(tmp_path / "tbcsr_csr.v"), os.path.join(SIM_DIR, "tb_regtool.v")]
    build = subprocess.run([iverilog, "-g2005", "-Wall", "-s", "tb_regtool", "-o", "tb.vvp",
                            f'-Ptb_regtool.ITF="{interface}"', f'-Ptb_regtool.TEST="{test}"', *files],
                           cwd=tmp_path, capture_output=True, text=True)
    assert build.returncode == 0, build.stdout + build.stderr

    run    = subprocess.run([vvp, "-n", "tb.vvp"], cwd=tmp_path, capture_output=True, text=True)
    output = run.stdout + run.stderr
    assert "ERROR" not in output, output
    assert f"[TESTBENCH] Test {test} OK" in output, output
