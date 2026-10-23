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
