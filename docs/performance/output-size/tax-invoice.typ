#set document(title: "Tax invoice HF-2026-0417 — Harbour & Finch Pty Ltd", date: datetime(year: 2026, month: 9, day: 14))
#set text(font: "Roc PDF Sans", size: 11pt, lang: "en", region: "AU")
#set par(leading: 3pt, spacing: 10pt)
#let navy = rgb(24, 52, 84)
#let brass = rgb(196, 150, 64)
#show heading: set text(size: 15pt, fill: navy, weight: "regular")
#show strong: set text(fill: navy)
#let logo = box(width: 132pt, height: 44pt, {
  place(rect(width: 44pt, height: 44pt, fill: navy))
  place(curve(fill: brass, stroke: none, curve.move((8pt, 32pt)), curve.cubic((16pt, 10pt), (30pt, 6pt), (38pt, 8pt)), curve.cubic((30pt, 14pt), (22pt, 24pt), (8pt, 32pt)), curve.close()))
  place(dx: 54pt, dy: 8pt, rect(width: 78pt, height: 8pt, fill: navy))
  place(dx: 54pt, dy: 22pt, rect(width: 60pt, height: 6pt, fill: navy))
  place(dx: 54pt, dy: 34pt, rect(width: 40pt, height: 4pt, fill: brass))
})
#set page(paper: "a4", margin: (top: 48pt + 56pt, bottom: 48pt + 28pt, x: 56pt),
  header: context { if counter(page).get().first() == 1 { logo } else [Harbour & Finch Pty Ltd — Tax invoice HF-2026-0417 (continued)] },
  footer: context [ABN 00 123 456 789 · Tax invoice HF-2026-0417 #h(1fr) Page #counter(page).display() of #counter(page).final().first()])

#strong[Harbour & Finch Pty Ltd]

Level 3, 18 Wharf Street \
Hobart TAS 7000 \
ABN 00 123 456 789 \
accounts\@harbourfinch.example · (03) 5550 0142

#title[Tax invoice]

#table(columns: (auto, 1fr), stroke: none, inset: (x: 4pt, y: 1.5pt),
  ..(("Invoice number", "HF-2026-0417"), ("Issue date", "14 September 2026"), ("Due date", "14 October 2026"), ("Customer reference", "PO 88213")).map(((k, v)) => (table.cell(k), v)).flatten())

= Bill to
Northstar Cooperative Ltd \
Attn: Accounts Payable \
42 Kestrel Parade \
Fremantle WA 6160

= Items
#let products = (
  ("HF-DSK-140", [Standing desk frame, twin motor, 1400 mm], "4", "689.00", "2,756.00"),
  ("HF-TOP-OAK", [Tasmanian oak desktop, 1400 × 700 mm, oiled], "4", "412.50", "1,650.00"),
  ("HF-CHR-ERG", [Ergonomic task chair, mesh back, adjustable lumbar support], "6", "529.00", "3,174.00"),
  ("HF-CAF-ELG", [#text(lang: "fr")[Cafetière « Élégance »], 1 L, for the staff kitchen], "2", "64.95", "129.90"),
  ("HF-LMP-LED", [LED task lamp, 4000 K, clamp mount], "6", "118.00", "708.00"),
  ("HF-CBL-TRY", [Under-desk cable tray, powder-coated steel], "8", "36.40", "291.20"),
  ("HF-INS-HRS", [Installation labour (hours)], "12", "95.00", "1,140.00"),
  ("HF-DEL-MET", [Metropolitan delivery, Hobart], "1", "180.00", "180.00"),
)
#figure(kind: table, caption: [Items supplied under purchase order PO 88213],
table(columns: (auto, 1fr, 36pt, 72pt, 80pt), align: (start, start, end, end, end), stroke: none, inset: (x: 4pt, y: 1.5pt),
  table.header[Code][Description][Qty][Unit price (AUD)][Amount (AUD)],
  ..for site in ("2", "3", "4", "5") { for p in products { (table.cell[#p.at(0)/L#site], [#p.at(1) (Level #site)], p.at(2), p.at(3), p.at(4)) } },
  table.footer(repeat: false,
    table.cell(colspan: 4, align: end)[Subtotal (excl. GST)], [40,116.40],
    table.cell(colspan: 4, align: end)[GST (10%)], [4,011.64],
    table.cell(colspan: 4, align: end)[Total due (AUD)], strong[44,128.04]),
))

= Payment
Please pay by 14 October 2026. Bank transfer: BSB 000-000, account 1234 5678, reference HF-2026-0417.

You can also #link("https://pay.harbourfinch.example/invoices/HF-2026-0417")[pay invoice HF-2026-0417 online] (pay.harbourfinch.example/invoices/HF-2026-0417).
