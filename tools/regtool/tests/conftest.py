"""
pytest configuration of the regtool unit tests (loaded automatically by pytest).

- adds tools/regtool to the python path (import csr_model, gen_vhdl, ...)
- fixtures shared by the test files
- option --update-golden : rewrite the reference files of test_golden.py
"""

import copy
import os
import shutil
import sys

import pytest

REGTOOL_DIR  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXAMPLES_DIR = os.path.join(REGTOOL_DIR, "examples")
HDL_DIR      = os.path.join(REGTOOL_DIR, "hdl")

sys.path.insert(0, REGTOOL_DIR)

import csr_model  # noqa: E402

#--------------------------------------------
def pytest_addoption(parser):
    parser.addoption("--update-golden", action="store_true", default=False,
                     help="Rewrite the reference files of test_golden.py instead of comparing")

#--------------------------------------------
def field(name="f", bits="7:0", **kwargs):
    """Field of an hjson description"""
    f = {"name": name, "bits": bits}
    f.update(kwargs)
    return f

#--------------------------------------------
def reg(name="r", fields=None, **kwargs):
    """Register of an hjson description (one 8-bit field by default)"""
    r = {"name": name, "fields": fields if fields is not None else [field()]}
    r.update(kwargs)
    return r

#--------------------------------------------
def desc(registers, **kwargs):
    """hjson description (module 'test', 32 bits by default)"""
    d = {"name": "test", "registers": registers}
    d.update(kwargs)
    return d

#--------------------------------------------
@pytest.fixture
def make_csr():
    """Return a function building a checked csr from an hjson description"""
    def _make(description):
        csr = csr_model.check_csr(copy.deepcopy(description))
        csr['logical_name'] = 'asylum'
        return csr
    return _make

#--------------------------------------------
@pytest.fixture
def example_csr(make_csr):
    """Return a function building the checked csr of tools/regtool/examples/<name>.hjson"""
    def _example(name):
        csr = csr_model.parse_hjson(os.path.join(EXAMPLES_DIR, name + ".hjson"))
        csr['logical_name'] = 'asylum'
        return csr
    return _example

#--------------------------------------------
@pytest.fixture
def generate(tmp_path):
    """Return a function calling a generator in a temporary file, returning the text"""
    def _generate(function, csr, filename="out"):
        path = tmp_path / filename
        function(csr, str(path))
        return path.read_text()
    return _generate

#--------------------------------------------
def tool(name):
    """Skip the test if the tool is not in the PATH"""
    path = shutil.which(name)
    if path is None:
        pytest.skip(f"{name} not found in the PATH")
    return path
