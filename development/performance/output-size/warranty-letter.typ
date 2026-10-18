#set document(title: "Letter to Northstar Cooperative about the warranty extension, 21 September 2026", date: datetime(year: 2026, month: 9, day: 21))
#set text(font: "Roc PDF Sans", size: 11pt, lang: "en", region: "AU")
#set par(leading: 3pt, spacing: 10pt)
#let navy = rgb(24, 52, 84)
#let brass = rgb(196, 150, 64)
#show heading: set text(size: 15pt, fill: navy, weight: "regular")
#show strong: set text(fill: navy)
#let logo = box(width: 140pt, height: 48pt, {
  place(dx: 92pt, rect(width: 48pt, height: 48pt, fill: navy))
  place(curve(fill: brass, stroke: none, curve.move((100pt, 36pt)), curve.cubic((108pt, 12pt), (124pt, 6pt), (132pt, 8pt)), curve.cubic((124pt, 16pt), (114pt, 26pt), (100pt, 36pt)), curve.close()))
  place(dy: 8pt, rect(width: 82pt, height: 8pt, fill: navy))
  place(dx: 22pt, dy: 22pt, rect(width: 60pt, height: 6pt, fill: navy))
  place(dx: 42pt, dy: 34pt, rect(width: 40pt, height: 4pt, fill: brass))
})
#set page(paper: "a4", margin: (top: 48pt + 60pt, bottom: 48pt + 28pt, x: 72pt),
  header: context { if counter(page).get().first() == 1 { align(end, logo) } else [Northstar Cooperative Ltd · 21 September 2026 #h(1fr) Page #counter(page).display() of #counter(page).final().first()] },
  footer: context { if counter(page).get().first() == 1 { align(center)[harbourfinch.example] } })

#strong[Harbour & Finch Pty Ltd]

Level 3, 18 Wharf Street, Hobart TAS 7000 \
(03) 5550 0142 · hello\@harbourfinch.example · ABN 00 123 456 789

21 September 2026

Ms Priya Raman \
Operations Manager \
Northstar Cooperative Ltd \
42 Kestrel Parade \
Fremantle WA 6160

#v(12pt)
Dear Ms Raman,

Subject: #strong[Extended warranty for your Level 2–5 fit-out]

Thank you for choosing Harbour & Finch for the Level 2 to 5 fit-out at 42 Kestrel Parade. Your facilities team told us in August that the new workstations have settled in well, and that the standing desks in particular have changed how the operations floor works through a long day. We are writing to confirm an extension of the warranty that covers the furniture and fittings we supplied under purchase order PO 88213, and to explain what the extension means for your team in practice, including how to lodge a claim.

Our standard warranty covers every item for two years from delivery. From today, we are extending that cover by a further three years for all four levels, so that frames, motors, desktops, chairs, lamps, and cable trays remain covered until 30 September 2031. The extension is provided at no charge. It reflects the volume of the order, the care your team has taken in following our assembly guidance, and the confidence we have in the materials and components we selected for this fit-out.

The desktops were milled from Tasmanian oak supplied by our long-standing partner in France, the joinery workshop of our oak supplier #text(lang: "fr")[Atelier Beaulieu] in Lyon. Each board was kiln-dried to a moisture content between nine and eleven percent before it was oiled, which is why we are comfortable covering the desktops against warping and delamination for the full extended term. If a desktop does develop a fault, we will replace the top with one from the same batch wherever stock allows, so that finishes remain consistent across a level.

The motors in the standing desk frames are sealed units rated for twenty thousand cycles. Under ordinary office use, which we estimate at six adjustments a day, that rating represents more than twelve years of service. We have nevertheless included the motors and control boxes in the extension, together with the height presets and the anti-collision sensors. If a frame stops responding, please do not open the control box: the seal is part of the safety rating, and our technicians will replace the whole unit on site.

The task chairs carry their manufacturer's own ten-year warranty on the gas lift and base, which continues unchanged. Our extension adds cover for the mechanisms, armrests, and upholstery seams, which the manufacturer covers for only three years. Mesh backs are covered against tearing that arises from ordinary use, though not against cuts or burns. Where a chair needs repair, we will lend your team a replacement chair of the same model for the duration of the repair, so that nobody is left without a seat.

To make the extension simple to use, our installers will visit each level in November to inspect every desk frame and record its serial number against your asset register. The inspection takes about an hour per level and can be scheduled outside business hours if that suits your team better. After the visit, we will send your facilities manager a schedule of serial numbers and a short guide to lodging claims, so that anyone on your team can report a fault quickly and accurately.

+ Frames, motors, and control boxes are covered until 30 September 2031.
+ Desktops are covered against warping and delamination for the same term.
+ Chair mechanisms, armrests, and upholstery seams are covered for the same term.
+ Replacement parts are dispatched within ten business days of an accepted claim.

The enclosed schedule lists every covered item by product code. Please keep this letter and the schedule with your asset register, so that your team can quote them when lodging a claim by telephone or email.

If you have any questions about the extension, or would like the November inspection scheduled at a particular time, please call me directly on (03) 5550 0142. We look forward to supporting Northstar Cooperative for many years to come.

#block(breakable: false)[
Yours sincerely,
#v(36pt)
Tom Finch

Director, Harbour & Finch Pty Ltd
]

Enclosure: Schedule 1, covered items

#pagebreak()
= Schedule 1. Covered items
#figure(kind: table, caption: [Items covered by the extended warranty],
table(columns: (auto, 1fr, 96pt), align: start, stroke: none, inset: (x: 4pt, y: 1.5pt),
  table.header[Code][Description][Warranty until],
  table.cell[HF-DSK-140], [Standing desk frame, twin motor, 1400 mm], [30 Sep 2031],
  table.cell[HF-TOP-OAK], [Tasmanian oak desktop, 1400 × 700 mm, oiled], [30 Sep 2031],
  table.cell[HF-CHR-ERG], [Ergonomic task chair, mesh back, adjustable lumbar support], [30 Sep 2031],
  table.cell[HF-CAF-ELG], [#text(lang: "fr")[Cafetière « Élégance »], 1 L, for the staff kitchen], [30 Sep 2031],
  table.cell[HF-LMP-LED], [LED task lamp, 4000 K, clamp mount], [30 Sep 2031],
  table.cell[HF-CBL-TRY], [Under-desk cable tray, powder-coated steel], [30 Sep 2031],
  table.cell[HF-INS-HRS], [Installation labour (workmanship)], [30 Sep 2031],
  table.cell[HF-DEL-MET], [Metropolitan delivery, Hobart (transit damage)], [30 Sep 2031],
))
