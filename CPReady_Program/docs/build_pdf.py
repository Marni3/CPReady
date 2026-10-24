import os
import subprocess
import time
import re
from pathlib import Path

DOCS_DIR = Path(__file__).parent.resolve()
MD_PATH = DOCS_DIR / "CALIBRATION_AND_TUNING_GUIDE.md"
HTML_PATH = DOCS_DIR / "calibration_guide.html"
PDF_PATH = DOCS_DIR / "CPReady_Calibration_and_Tuning_Guide.pdf"
EDGE_EXE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

def markdown_to_html(md_text: str) -> str:
    # Basic markdown parser to produce clean, styled semantic HTML
    lines = md_text.splitlines()
    html_lines = []
    in_code_block = False
    in_table = False
    in_list = False
    code_lang = ""

    for line in lines:
        stripped = line.strip()

        # Code block toggle
        if stripped.startswith("```"):
            if in_code_block:
                html_lines.append("</pre></div>")
                in_code_block = False
            else:
                code_lang = stripped[3:].strip()
                html_lines.append(f'<div class="code-block"><div class="code-header">{code_lang or "code"}</div><pre><code>')
                in_code_block = True
            continue

        if in_code_block:
            # Escape HTML characters in code
            escaped = (line.replace("&", "&amp;")
                           .replace("<", "&lt;")
                           .replace(">", "&gt;"))
            html_lines.append(escaped)
            continue

        # Close list if not in list
        if in_list and not (stripped.startswith("- ") or stripped.startswith("* ") or re.match(r"^\d+\.\s+", stripped)):
            html_lines.append("</ul>")
            in_list = False

        # Close table if not in table
        if in_table and not ("|" in stripped and stripped.startswith("|")):
            html_lines.append("</tbody></table></div>")
            in_table = False

        if not stripped:
            continue

        # Horizontal rule
        if stripped in ("---", "***", "___"):
            html_lines.append("<hr/>")
            continue

        # Headers
        if stripped.startswith("# "):
            html_lines.append(f'<h1 class="doc-title">{stripped[2:]}</h1>')
            continue
        if stripped.startswith("## "):
            html_lines.append(f'<h2 class="section-title">{stripped[3:]}</h2>')
            continue
        if stripped.startswith("### "):
            html_lines.append(f'<h3 class="subsection-title">{stripped[4:]}</h3>')
            continue
        if stripped.startswith("#### "):
            html_lines.append(f'<h4 class="sub-subsection-title">{stripped[5:]}</h4>')
            continue

        # Tables
        if "|" in stripped and stripped.startswith("|") and stripped.endswith("|"):
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            # Check if separator row
            if all(re.match(r"^:?-+:?$", c) for c in cells):
                continue
            if not in_table:
                in_table = True
                html_lines.append('<div class="table-container"><table><thead><tr>')
                for c in cells:
                    html_lines.append(f'<th>{inline_formatting(c)}</th>')
                html_lines.append('</tr></thead><tbody>')
            else:
                html_lines.append('<tr>')
                for c in cells:
                    html_lines.append(f'<td>{inline_formatting(c)}</td>')
                html_lines.append('</tr>')
            continue

        # Blockquotes / Practical Rules of Thumb
        if stripped.startswith("> "):
            content = stripped[2:].strip()
            html_lines.append(f'<div class="callout-rule"><div class="callout-icon">💡</div><div class="callout-content">{inline_formatting(content)}</div></div>')
            continue

        # Lists
        if stripped.startswith("- ") or stripped.startswith("* "):
            if not in_list:
                html_lines.append("<ul>")
                in_list = True
            item_text = stripped[2:]
            # Check for checkbox
            if item_text.startswith("[ ] "):
                item_text = f'<input type="checkbox" disabled/> {item_text[4:]}'
            elif item_text.startswith("[x] "):
                item_text = f'<input type="checkbox" checked disabled/> {item_text[4:]}'
            html_lines.append(f'<li>{inline_formatting(item_text)}</li>')
            continue

        if re.match(r"^\d+\.\s+", stripped):
            if not in_list:
                html_lines.append("<ol>")
                in_list = True
            match = re.match(r"^\d+\.\s+(.*)$", stripped)
            html_lines.append(f'<li>{inline_formatting(match.group(1))}</li>')
            continue

        # Regular paragraph
        html_lines.append(f'<p>{inline_formatting(stripped)}</p>')

    if in_list:
        html_lines.append("</ul>")
    if in_table:
        html_lines.append("</tbody></table></div>")
    if in_code_block:
        html_lines.append("</pre></div>")

    return "\n".join(html_lines)

def inline_formatting(text: str) -> str:
    # Math inline expressions
    text = re.sub(r"\$\$(.*?)\$\$", r'<div class="math-block">\1</div>', text)
    text = re.sub(r"\$(.*?)\$", r'<span class="math-inline">\1</span>', text)
    # Bold & Italic
    text = re.sub(r"\*\*\*(.*?)\*\*\*", r"<strong><em>\1</em></strong>", text)
    text = re.sub(r"\*\*(.*?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\*(.*?)\*", r"<em>\1</em>", text)
    # Inline code
    text = re.sub(r"`(.*?)`", r'<code class="inline-code">\1</code>', text)
    # Links
    text = re.sub(r"\[(.*?)\]\((.*?)\)", r'<span class="doc-link">\1</span>', text)
    return text

def generate_pdf():
    print(f"Reading markdown from: {MD_PATH}")
    with open(MD_PATH, "r", encoding="utf-8") as f:
        md_content = f.read()

    body_html = markdown_to_html(md_content)

    html_doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>CPReady Hardware Testing, Calibration & Parameter Tuning Guide</title>
<style>
  @page {{
    size: A4;
    margin: 14mm 13mm 14mm 13mm;
    @bottom-right {{
      content: "Page " counter(page);
      font-size: 8pt;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      color: #64748b;
    }}
  }}

  body {{
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 9.1pt;
    line-height: 1.42;
    color: #1e293b;
    background-color: #ffffff;
    margin: 0;
    padding: 0;
  }}

  .doc-title {{
    font-size: 16.5pt;
    font-weight: 800;
    color: #0f172a;
    border-bottom: 2.5px solid #2563eb;
    padding-bottom: 5px;
    margin-top: 0;
    margin-bottom: 6px;
    letter-spacing: -0.3px;
  }}

  .section-title {{
    font-size: 12pt;
    font-weight: 700;
    color: #1e3a8a;
    border-bottom: 1.5px solid #e2e8f0;
    padding-bottom: 3px;
    margin-top: 13px;
    margin-bottom: 5px;
    page-break-after: avoid;
  }}

  .subsection-title {{
    font-size: 10.5pt;
    font-weight: 600;
    color: #0f766e;
    margin-top: 9px;
    margin-bottom: 3px;
    page-break-after: avoid;
  }}

  .sub-subsection-title {{
    font-size: 9.5pt;
    font-weight: 600;
    color: #334155;
    margin-top: 7px;
    margin-bottom: 3px;
    page-break-after: avoid;
  }}

  p {{
    margin-top: 0;
    margin-bottom: 5px;
  }}

  strong {{
    color: #0f172a;
  }}

  ul, ol {{
    margin-top: 0;
    margin-bottom: 5px;
    padding-left: 18px;
  }}

  li {{
    margin-bottom: 2px;
  }}

  hr {{
    border: none;
    border-top: 1px solid #cbd5e1;
    margin: 10px 0;
  }}

  .inline-code {{
    background-color: #f1f5f9;
    color: #0f172a;
    font-family: Consolas, "SFMono-Regular", Menlo, monospace;
    font-size: 8.5pt;
    padding: 1.5px 4.5px;
    border-radius: 4px;
    border: 1px solid #e2e8f0;
  }}

  .code-block {{
    background-color: #0f172a;
    border-radius: 6px;
    margin: 8px 0;
    overflow: hidden;
    page-break-inside: avoid;
  }}

  .code-header {{
    background-color: #1e293b;
    color: #94a3b8;
    font-size: 7.5pt;
    font-family: Consolas, monospace;
    padding: 3px 10px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    border-bottom: 1px solid #334155;
  }}

  .code-block pre {{
    margin: 0;
    padding: 8px 12px;
    color: #f8fafc;
    font-family: Consolas, "Courier New", monospace;
    font-size: 8pt;
    line-height: 1.4;
    white-space: pre-wrap;
  }}

  .callout-rule {{
    display: flex;
    background-color: #eff6ff;
    border-left: 4px solid #3b82f6;
    border-radius: 0 6px 6px 0;
    padding: 8px 12px;
    margin: 10px 0;
    page-break-inside: avoid;
  }}

  .callout-icon {{
    font-size: 14pt;
    margin-right: 8px;
    line-height: 1.2;
  }}

  .callout-content {{
    color: #1e40af;
    font-size: 9pt;
    line-height: 1.45;
  }}

  .table-container {{
    margin: 10px 0;
    page-break-inside: avoid;
  }}

  table {{
    width: 100%;
    border-collapse: collapse;
    font-size: 8.5pt;
    background-color: #ffffff;
    box-shadow: 0 1px 2px rgba(0,0,0,0.05);
  }}

  th {{
    background-color: #f8fafc;
    color: #0f172a;
    font-weight: 600;
    text-align: left;
    padding: 6px 8px;
    border-bottom: 2px solid #cbd5e1;
    border-top: 1px solid #e2e8f0;
  }}

  td {{
    padding: 5px 8px;
    border-bottom: 1px solid #e2e8f0;
    vertical-align: top;
  }}

  tr:nth-child(even) td {{
    background-color: #f8fafc;
  }}

  .math-block {{
    background-color: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 4px;
    text-align: center;
    padding: 4px;
    font-style: italic;
    font-family: Georgia, serif;
    margin: 6px 0;
    color: #1e3a8a;
  }}

  .math-inline {{
    font-family: Georgia, serif;
    font-style: italic;
    color: #1e3a8a;
  }}

  .doc-link {{
    color: #2563eb;
    font-weight: 500;
  }}
</style>
</head>
<body>
{body_html}
</body>
</html>
"""

    with open(HTML_PATH, "w", encoding="utf-8") as f:
        f.write(html_doc)
    print(f"HTML written to: {HTML_PATH}")

    # Launch Edge headless print-to-pdf
    print(f"Generating PDF using Edge headless at: {EDGE_EXE}")
    args = [
        EDGE_EXE,
        "--headless",
        "--disable-gpu",
        "--run-all-compositor-stages-before-draw",
        f"--print-to-pdf={str(PDF_PATH)}",
        str(HTML_PATH)
    ]
    res = subprocess.run(args, capture_output=True, text=True)
    time.sleep(1.5)

    if PDF_PATH.exists():
        size_kb = PDF_PATH.stat().st_size / 1024
        print(f"[SUCCESS] PDF generated successfully!")
        print(f"Path: {PDF_PATH}")
        print(f"File Size: {size_kb:.1f} KB")

        try:
            import pypdf
            reader = pypdf.PdfReader(str(PDF_PATH))
            print(f"Total Page Count: {len(reader.pages)} pages")
        except Exception as e:
            print(f"Could not read with pypdf: {e}")
    else:
        print(f"[ERROR] PDF generation failed!")
        print("Stdout:", res.stdout)
        print("Stderr:", res.stderr)

if __name__ == "__main__":
    generate_pdf()
