"""
Golden tests : the files generated from tools/regtool/examples/<example>.hjson
must be equal to the reference files committed in tools/regtool/examples.

After an intended change of a generator, update the references with
    python3 -m pytest tools/regtool --update-golden
and review the difference with git diff.
"""

import os

import pytest

import csr_model
from conftest import EXAMPLES_DIR
from gen_vhdl     import generate_vhdl_package, generate_vhdl_module
from gen_c        import generate_c_header
from gen_markdown import generate_doc_markdown

EXAMPLES = ["example1", "example2", "example3"]

OUTPUTS  = {
    "_csr_pkg.vhd" : generate_vhdl_package,
    "_csr.vhd"     : generate_vhdl_module,
    "_csr.h"       : generate_c_header,
    "_csr.md"      : generate_doc_markdown,
}

#--------------------------------------------
@pytest.mark.parametrize("suffix", OUTPUTS.keys())
@pytest.mark.parametrize("example", EXAMPLES)
def test_golden(request, monkeypatch, tmp_path, example, suffix):
    update = request.config.getoption("--update-golden")
    golden = os.path.join(EXAMPLES_DIR, example + suffix)

    # Dumps in the examples directory when updating, else in tmp_path
    monkeypatch.chdir(EXAMPLES_DIR if update else tmp_path)
    csr = csr_model.parse_hjson(os.path.join(EXAMPLES_DIR, example + ".hjson"), dump=update)
    csr['logical_name'] = 'asylum'

    output = tmp_path / (example + suffix)
    OUTPUTS[suffix](csr, str(output))

    if update:
        with open(golden, 'w') as f:
            f.write(output.read_text())
    else:
        with open(golden) as f:
            assert output.read_text() == f.read(), f"{golden} is outdated (see the docstring of {__file__})"
