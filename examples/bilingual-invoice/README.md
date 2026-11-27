# Bilingual invoice

Run `roc main.roc` here to write `bilingual-invoice.pdf`.

The invoice registers the packaged Inter Regular and the included IBM Plex
Sans Hebrew. It supplies them in that order to the font policy and enables
`Theme.international_text: HebrewLatin`. Author in logical reading order and
use `Pdf.in_language` to identify meaningful language changes. The address and
service cell include Hebrew language spans, and the payment instructions
include a French span.

The address wraps after `נועה לוי רחוב הרצל 24 תל אביב`. The next line contains
`(PO-1042) ישראל` in logical source order. The logical text of the service cell
is `ייעוץ בטיחות SKU-42 ILS 1,250.00`. The layout positions the purchase-order ID,
SKU and amount left to right within their right-to-left surroundings.
