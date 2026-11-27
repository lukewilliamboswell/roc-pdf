# Thai and Latin payment notice

Run `roc main.roc` here to write `thai-notice.pdf`.

Enable `Theme.international_text: ThaiLatin({ revision, words })` with an
ordered policy over packaged Inter Regular and the included IBM Plex Sans
Thai Looped Regular. Supply a stable dictionary revision and the exact
words for your text. Mark Thai spans with `Pdf.in_language("th", ...)`.

The notice wraps `กรุณาชำระเงินภายในวันนี้` without adding spaces. The first
line ends after `เงิน` and the second contains `ภายในวันนี้`. The logical
paragraph keeps the original text. A dictionary lacking usable word
boundaries can produce a located width diagnostic for a narrow frame.
