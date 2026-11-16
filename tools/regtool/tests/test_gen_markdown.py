"""
Unit tests of the Markdown documentation generator (gen_markdown.py)
"""

from conftest import field, reg, desc
from gen_markdown import generate_doc_markdown

#--------------------------------------------
def test_title(make_csr, generate):
    text = generate(generate_doc_markdown, make_csr(desc([reg()], desc="My module")))
    assert text.startswith("# test\nMy module\n")

#--------------------------------------------
def test_address_table(make_csr, generate):
    """Sorted by address, registers sharing an address on the same row"""
    csr  = make_csr(desc([reg("data"  , address="x4"),
                          reg("cmd"   , address="0", swaccess="wo"),
                          reg("status", address="0", swaccess="ro")]))
    text = generate(generate_doc_markdown, csr)
    assert "|0x0|cmd, status|\n|0x4|data|\n" in text

#--------------------------------------------
def test_sections(make_csr, generate):
    csr  = make_csr(desc([reg("ctrl", address="x8", desc="Control",
                              fields=[field("en", "0", desc="Enable"), field("div", "15:8")])]))
    text = generate(generate_doc_markdown, csr)
    assert "## 0x8 ctrl\nControl\n" in text
    assert "### [0:0] en\nEnable\n" in text
    assert "### [15:8] div\n"       in text

#--------------------------------------------
def test_wait_state(make_csr, generate):
    """One line for the wait states, only for a register with wait states"""
    csr  = make_csr(desc([reg("r0", desc="Wait", rd_wait_state=2, wr_wait_state="NB_WAIT"),
                          reg("r1", desc="Zero", rd_wait_state=0),
                          reg("r2", desc="Write", wr_wait_state="1"),
                          reg("r3", desc="None")],
                         parameters=[{"name": "NB_WAIT", "type": "natural"}]))
    text = generate(generate_doc_markdown, csr)
    assert "## 0x0 r0\nWait\n\nWait states: read 2, write NB_WAIT\n\n### [7:0] f\n" in text
    assert "## 0x4 r1\nZero\n\n### [7:0] f\n"                                in text
    assert "## 0x8 r2\nWrite\n\nWait states: read 0, write 1\n\n### [7:0] f\n" in text
    assert text.count("Wait states") == 2
