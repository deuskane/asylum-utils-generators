"""
Unit tests of the command line (regtool.py)
"""

import os
import sys

import jsonschema
import pytest

import regtool
from conftest import EXAMPLES_DIR

#--------------------------------------------
def run(monkeypatch, tmp_path, *args):
    """Run regtool.main() in tmp_path with the arguments"""
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(sys, "argv", ["regtool.py", *args])
    regtool.main()

#--------------------------------------------
def test_default_outputs(monkeypatch, tmp_path):
    """Without output option : <name>_csr* files and the dumps in the current directory"""
    run(monkeypatch, tmp_path, os.path.join(EXAMPLES_DIR, "example2.hjson"))

    assert sorted(os.listdir(tmp_path)) == sorted([
        "example2_csr_pkg.vhd", "example2_csr.vhd", "example2_csr.h", "example2_csr.md",
        "example2_dump1.hjson", "example2_dump2.hjson", "example2_dump3.hjson"])

#--------------------------------------------
def test_output_paths(monkeypatch, tmp_path):
    out = tmp_path / "out"
    out.mkdir()
    run(monkeypatch, tmp_path, os.path.join(EXAMPLES_DIR, "example2.hjson"),
        "--vhdl_package", str(out / "p.vhd"), "--vhdl_module" , str(out / "m.vhd"),
        "--c_header"    , str(out / "h.h")  , "--doc_markdown", str(out / "d.md"))

    assert sorted(os.listdir(out)) == ["d.md", "h.h", "m.vhd", "p.vhd"]

#--------------------------------------------
@pytest.mark.parametrize("logical_name", ["work", "mylib"])
def test_logical_name(monkeypatch, tmp_path, logical_name):
    args = [os.path.join(EXAMPLES_DIR, "example2.hjson")]
    if logical_name != "work":
        args += ["--logical_name", logical_name]
    run(monkeypatch, tmp_path, *args)

    assert f"use     {logical_name}.example2_csr_pkg.ALL;" in (tmp_path / "example2_csr.vhd").read_text()

#--------------------------------------------
def test_invalid_hjson(monkeypatch, tmp_path):
    hjson_file = tmp_path / "bad.hjson"
    hjson_file.write_text('{ name: "bad", registers: [ { name: "r" } ] }')

    with pytest.raises(jsonschema.exceptions.ValidationError):
        run(monkeypatch, tmp_path, str(hjson_file))
