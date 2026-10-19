"""Generate the trial report. Run from its prepared workspace directory."""
# Start before library imports so import cost is visible inside the application.
import time

_entered = time.perf_counter_ns()
import io
import json

from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, Table, TableStyle

import workload

_imported = time.perf_counter_ns()
pdfmetrics.registerFont(TTFont("Trial", "font.ttf"))
_font_ready = time.perf_counter_ns()
buffer = io.BytesIO()
document = BaseDocTemplate(
    buffer, pagesize=(595, 842), leftMargin=50, rightMargin=50,
    topMargin=50, bottomMargin=74, title=workload.TITLE, author="Harbour Services",
    initialFontName="Trial", initialFontSize=11, initialLeading=15,
)
body = ParagraphStyle("Body", fontName="Trial", fontSize=11, leading=15, spaceAfter=10)
title = ParagraphStyle("Title", parent=body, fontSize=18, leading=22)
story = [Paragraph(workload.TITLE, title)]
story += [Paragraph(text, body) for text in workload.PARAGRAPHS]
story += [Paragraph("Completed requests by team", body)]
table = Table([workload.HEADERS] + workload.ROWS, colWidths=[240, 120, 135], hAlign="LEFT")
table.setStyle(TableStyle([
    ("FONTNAME", (0, 0), (-1, -1), "Trial"),
    ("FONTSIZE", (0, 0), (-1, -1), 11),
    ("LEADING", (0, 0), (-1, -1), 15),
    ("LEFTPADDING", (0, 0), (-1, -1), 5),
    ("RIGHTPADDING", (0, 0), (-1, -1), 5),
    ("TOPPADDING", (0, 0), (-1, -1), 5),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
]))
story += [table, Spacer(1, 10), Paragraph(workload.REVISION, body)]
_authored = time.perf_counter_ns()


def footer(canvas, _document):
    canvas.saveState()
    canvas.setFont("Trial", 9)
    canvas.drawString(50, 50, workload.FOOTER)
    canvas.restoreState()


# Platypus performs layout and serialization together; do not invent a split.
document.addPageTemplates(PageTemplate(
    id="report", onPage=footer,
    frames=[Frame(50, 74, 495, 718, leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)],
))
document.build(story)
payload = buffer.getvalue()
_generated = time.perf_counter_ns()
with open("report.pdf", "wb") as output:
    output.write(payload)
_written = time.perf_counter_ns()
print("PDF_BENCH " + json.dumps({
    "schema": 1,
    "imports_ns": _imported - _entered,
    "font_setup_ns": _font_ready - _imported,
    "authoring_ns": _authored - _font_ready,
    "generate_ns": _generated - _authored,
    "write_ns": _written - _generated,
    "application_ns": _written - _entered,
    "pdf_bytes": len(payload),
}))
