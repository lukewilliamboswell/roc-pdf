#set document(title: "Sprout 2.4 product brief", date: datetime(year: 2026, month: 9, day: 30))
#let forest = rgb(14, 92, 60); #let leaf = rgb(46, 158, 98); #let sage = rgb(214, 236, 222)
#let meadow = rgb(240, 247, 242); #let sun = rgb(247, 190, 72); #let clay = rgb(226, 120, 84)
#let stone = rgb(196, 204, 200); #let charcoal = rgb(33, 41, 37)
#set text(font: "Inter", size: 11pt, fill: charcoal, lang: "en", region: "US")
#set par(leading: 5pt, spacing: 9pt)
#show heading: set text(size: 17pt, fill: forest, weight: "bold")
#show title: set text(size: 40pt, fill: forest, weight: "bold")
#show raw: set text(font: "Source Code Pro", size: 0.9em, fill: rgb(120, 64, 18))
#show link: it => underline(offset: 1.6pt, stroke: 0.7pt, text(fill: forest, it))
#let sprout = box(width: 32pt, height: 32pt, {
  place(dx: 15pt, dy: 12pt, rect(width: 2pt, height: 20pt, fill: forest))
  place(curve(fill: leaf, curve.move((16pt, 18pt)), curve.cubic((10pt, 6pt), (2pt, 6pt), (1pt, 10pt)), curve.cubic((2pt, 18pt), (10pt, 20pt), (16pt, 18pt)), curve.close()))
  place(curve(fill: forest, curve.move((16pt, 14pt)), curve.cubic((20pt, 2pt), (28pt, 0pt), (31pt, 2pt)), curve.cubic((30pt, 10pt), (24pt, 16pt), (16pt, 14pt)), curve.close()))
})
#set page(paper: "us-letter", margin: (top: 40pt + 48pt, bottom: 40pt + 32pt, x: 54pt),
  header: context { if counter(page).get().first() == 1 { sprout; h(1fr); [Product brief · October 2026] } else { [Sprout 2.4 · Product brief]; v(-6pt); rect(width: 100%, height: 2pt, fill: leaf) } },
  footer: context [sprout.example · Launch brief, not for resale #h(1fr) Page #counter(page).display() of #counter(page).final().first()])
#set table(stroke: (x: none, y: 1pt + leaf), inset: 5pt)
#show table.cell.where(y: 0): set text(fill: forest)
#let card(edge, len) = box(width: 136pt, height: 38pt, {
  place(rect(width: 136pt, height: 38pt, fill: white)); place(rect(width: 4pt, height: 38pt, fill: edge))
  place(dx: 12pt, dy: 9pt, rect(width: len * 1pt, height: 5pt, fill: stone)); place(dx: 12pt, dy: 19pt, rect(width: len * 0.6pt, height: 5pt, fill: stone))
  place(dx: 119pt, dy: 21pt, circle(radius: 5pt, fill: edge))
})
#let column(name, cards) = box(width: 152pt, height: 150pt, {
  place(rect(width: 152pt, height: 150pt, fill: sage))
  place(dx: 10pt, dy: 6pt, text(size: 10pt, fill: forest, name))
  for (i, (e, l)) in cards.enumerate() { place(dx: 8pt, dy: (22 + 44 * i) * 1pt, card(e, l)) }
})
#let hero = box(width: 504pt, height: 190pt, {
  place(rect(width: 504pt, height: 190pt, fill: meadow))
  place(dx: 16pt, dy: 168pt, rect(width: 380pt, height: 8pt, fill: white)); place(dx: 16pt, dy: 168pt, rect(width: 266pt, height: 8pt, fill: leaf))
  place(dx: 400pt, dy: 166pt, box(width: 88pt, align(end, text(size: 8pt, fill: forest)[Decision log 70%])))
  place(dx: 16pt, dy: 8pt, column("Proposed", ((clay, 96), (sun, 80), (clay, 104))))
  place(dx: 176pt, dy: 8pt, column("Deciding", ((sun, 88), (sun, 110))))
  place(dx: 336pt, dy: 8pt, column("Decided", ((leaf, 100), (leaf, 76), (leaf, 92))))
})
#let ct = (95, 88, 79, 64, 56, 51, 47, 44)
#let chart = box(width: 504pt, height: 126pt, {
  let y(t) = (126 - 16 - t * 1.1) * 1pt
  for d in (0, 2, 4, 6, 8, 10) {
    place(dx: 30pt, dy: y(d * 10), rect(width: 474pt, height: if d == 0 { 1pt } else { 0.5pt }, fill: if d == 0 { charcoal } else { stone }))
    place(dx: 0pt, dy: y(d * 10) - 5pt, box(width: 24pt, align(end, text(size: 8pt, if d == 10 [10 d] else [#d]))))
  }
  let pts = ct.enumerate().map(((i, t)) => ((42 + 62 * i) * 1pt, y(t)))
  place(polygon(fill: sage, (42pt, y(0)), ..pts, (pts.last().at(0), y(0))))
  place(curve(stroke: 2pt + forest, curve.move(pts.first()), ..pts.slice(1).map(p => curve.line(p))))
  for (i, p) in pts.enumerate() {
    place(dx: p.at(0) - 4pt, dy: p.at(1) - 4pt, circle(radius: 4pt, fill: white, stroke: 1.5pt + forest))
    place(dx: p.at(0) - 20pt, dy: 114pt, box(width: 40pt, align(center, text(size: 8pt)[Week #(i + 1)])))
  }
  for x in range(30, 504, step: 14) { place(dx: x * 1pt, dy: y(50), rect(width: 8pt, height: 1pt, fill: clay)) }
  place(dx: 404pt, dy: y(50) - 14pt, box(width: 100pt, align(end, text(size: 8pt, fill: clay)[Target: 5 days])))
})
#let callout(lines) = block(width: 504pt, inset: 14pt, radius: 8pt, fill: meadow, stroke: 1.5pt + leaf, breakable: false, {
  show strong: set text(fill: forest)
  for l in lines { par(l) }
})

#title[Sprout 2.4]

Planning software for small teams that prefer *clarity over ceremony*. Version 2.4 turns every decision into a record your team can find, trust, and print.

#figure(hero, alt: "The Sprout board: three columns labelled Proposed, Deciding, and Decided holding colour-coded cards, with a progress bar along the bottom showing the decision log about two thirds complete.", caption: [The Sprout board moves each decision from proposed to decided in one visible place.])

#callout(([*54% faster decisions.* Median time to decide fell from 9.5 to 4.4 days over eight weeks.], [*3 fewer meetings a week.* Status meetings gave way to the shared decision log.], [*41 teams, 612 people.* The pilot ran from June to August 2026 across four companies.]))

= The problem <problem>
Important decisions disappear across chat threads, tickets, and meeting notes. Weeks later nobody can say _who_ decided, _why_, or whether the decision still stands, so teams meet again to decide the same thing.

= What is new in 2.4 <new>
- *Decision log.* Every card that reaches Decided is written to an append-only log with its owner, date, and rationale.
- *Typed ownership.* Owners are people, not channels; a card without an owner cannot leave Proposed.
- *Archival export.* Run `sprout export --pdf --since 2026-07-01` for a tagged, searchable record that stays readable offline.
- *Quiet notifications.* One daily digest replaces per-card pings; urgent cards still notify at once.

= Pilot results <pilot>
Median time to decide halved and crossed the five-day target (dashed) in week 6.

#figure(chart, alt: "Line chart of median days from proposal to decision over eight pilot weeks, falling steadily from 9.5 days in week 1 to 4.4 days in week 8 and crossing the five-day target in week 6. Values are listed in Table 1.", caption: [Figure 1. Median days to decide, weeks 1 to 8])

#figure(kind: table, caption: [Table 1. Median days from proposal to decision, by pilot week],
table(columns: (3fr,) + (1fr,) * 8, align: (start,) + (end,) * 8,
  table.header([Pilot week], ..range(1, 9).map(i => [#i])),
  table.cell[Median days], ..ct.map(t => [#calc.div-euclid(t, 10).#calc.rem(t, 10)])))

= Plans and pricing <plans>
Every plan includes the board, the decision log, and archival export.

#let group(l) = table.cell(colspan: 4, strong(l))
#figure(kind: table, caption: [Table 2. Plans compared],
table(columns: (5fr, 2fr, 2fr, 2fr), align: (start, center, center, center),
  table.header[Capability][Starter][Team][Business],
  group[Planning],
  [Boards and decision log], [Yes], [Yes], [Yes],
  [Typed owners and due dates], [Yes], [Yes], [Yes],
  [Dependency map], [–], [Yes], [Yes],
  group[Sharing and export],
  [Archival PDF export], [Yes], [Yes], [Yes],
  [Guest reviewers], [2], [10], [Unlimited],
  [Single sign-on and audit log], [–], [–], [Yes],
  table.footer(repeat: false, table.cell(align: end)[USD per editor, monthly], strong[Free], strong[\$12], strong[\$24])))

= What comes next <next>
+ *November.* Calendar sync, so a decision's due date appears where people plan their week.
+ *December.* Templates for hiring, vendor selection, and architecture reviews.
+ *Early 2027.* A read-only API for dashboards, starting with `GET /v1/decisions`.

= Rollout and support <rollout>
Sprout 2.4 reaches every workspace in three waves. Existing boards migrate automatically; nothing needs to be exported or re-imported.

#figure(kind: table, caption: [Table 3. Rollout waves],
table(columns: (92pt, 2fr, 3fr),
  table.header[Date][Wave][What changes],
  [6 Oct 2026], [Pilot customers], [Decision log and typed owners switch on; export stays in preview.],
  [20 Oct 2026], [Team and Business], [All 2.4 features, including archival export and quiet notifications.],
  [3 Nov 2026], [Starter], [All 2.4 features; the digest defaults to 9 a.m. local time.]))

#callout(([#quote["We stopped re-deciding things. The log settles arguments before they start."]], [Maya Lindqvist, Head of Operations, Fjordline Studio (pilot customer)]))

Start a free Starter workspace at #link("https://sprout.example/start")[sprout.example/start], compare plans in #link(<plans>)[Plans and pricing], or email #link("mailto:launch@sprout.example")[launch\@sprout.example] to book a walkthrough.
