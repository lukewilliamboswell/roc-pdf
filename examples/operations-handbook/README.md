# Payments platform on-call handbook

Run `roc run main.roc` in this directory to write
[operations-handbook.pdf](operations-handbook.pdf). The first page contains
a linked contents list with a wrapped chapter entry and an indented rollback
entry with decorative dotted leaders. The main procedures and appendices
are separate `Pdf.part` blocks. Chapter scopes use a quiet opening and
their own continuation running label.

The app resolves the first appendix destination before setting the authored
`A-` page label range. All page fields reserve their width in both passes.
The command reference begins at `A-1`, the label printed in the footer,
the contents, the rollback paragraph, and the escalation table.

In the rollback procedure, step 3 owns its lead paragraph, a command
source block, a recovery-check table, and one native `Pdf.callout`.
The app reports that the callout starts on page 4 and ends on page 5.
Its panel and padding repeat while the step number appears once. The
[business report](../business-report/README.md) also shows a measured,
unsplittable custom block.
