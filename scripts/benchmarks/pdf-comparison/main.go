package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/go-pdf/fpdf"
)

func check(err error) {
	if err != nil {
		panic(err)
	}
}

func main() {
	start := time.Now()
	fontBytes, err := os.ReadFile("font.ttf")
	check(err)
	pdf := fpdf.NewCustom(&fpdf.InitType{UnitStr: "pt", Size: fpdf.SizeType{Wd: 595, Ht: 842}})
	pdf.AddUTF8FontFromBytes("Trial", "", fontBytes)
	check(pdf.Error())
	fontReady := time.Now()
	// This library lays out and records drawing commands as methods are called.
	pdf.SetMargins(50, 50, 50)
	pdf.SetCellMargin(0)
	pdf.SetAutoPageBreak(true, 74)
	pdf.SetTitle(title, true)
	pdf.SetAuthor("Harbour Services", true)
	pdf.SetFooterFunc(func() {
		pdf.SetXY(50, 780)
		pdf.SetFont("Trial", "", 9)
		pdf.CellFormat(495, 12, footerText, "", 0, "L", false, 0, "")
	})
	pdf.AddPage()
	pdf.SetFont("Trial", "", 18)
	pdf.MultiCell(495, 22, title, "", "L", false)
	pdf.Ln(10)
	pdf.SetFont("Trial", "", 11)
	for _, paragraph := range paragraphs {
		pdf.MultiCell(495, 15, paragraph, "", "L", false)
		pdf.Ln(10)
	}
	pdf.MultiCell(495, 15, "Completed requests by team", "", "L", false)
	pdf.Ln(10)
	widths := []float64{240, 120, 135}
	allRows := append([][]string{headers}, rows...)
	for _, row := range allRows {
		y := pdf.GetY()
		x := 50.0
		for col, text := range row {
			pdf.SetXY(x+5, y+5)
			align := "L"
			if col > 0 {
				align = "R"
			}
			pdf.CellFormat(widths[col]-10, 15, text, "", 0, align, false, 0, "")
			x += widths[col]
		}
		pdf.SetXY(50, y+25)
	}
	pdf.Ln(10)
	pdf.MultiCell(495, 15, revision, "", "L", false)
	check(pdf.Error())
	painted := time.Now()
	var buffer bytes.Buffer
	check(pdf.Output(&buffer))
	emitted := time.Now()
	check(os.WriteFile("report.pdf", buffer.Bytes(), 0644))
	written := time.Now()
	metrics := map[string]int64{
		"schema":              1,
		"font_setup_ns":       fontReady.Sub(start).Nanoseconds(),
		"authoring_layout_ns": painted.Sub(fontReady).Nanoseconds(),
		"emit_ns":             emitted.Sub(painted).Nanoseconds(),
		"write_ns":            written.Sub(emitted).Nanoseconds(),
		"application_ns":      written.Sub(start).Nanoseconds(),
		"pdf_bytes":           int64(buffer.Len()),
	}
	encoded, err := json.Marshal(metrics)
	check(err)
	fmt.Printf("PDF_BENCH %s\n", encoded)
}
