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

## Generate the contents

```sh
roc run main.roc generated
```

This variant writes `operations-handbook.pdf` with a generated contents
covering two pages. Compare it with the authored default. The first chapter
moves from page 2 to page 3, and its printed page label and both links follow.
The two “Recovery checks” headings have different destinations. The second
entry uses the override “Recovery checks after settlement resumes”. The
command appendix retains the restarted label `A-1`.

The checked output and preview are
[operations-handbook-generated.pdf](operations-handbook-generated.pdf) and
[preview-generated.png](preview-generated.png).

## A page label that moves its own target

From this directory, run:

```sh
roc run main.roc flow-short
roc run main.roc flow-long
```

Both commands write `operations-handbook.pdf`. The compact recovery note
has a linked page label near the end of the first line. With `A-` as the
prefix, the label stays on that line and prints `A-1`. With
`RECOVERY-CHECKS-`, the label wraps, the heading moves to physical page 2,
and the link prints `RECOVERY-CHECKS-2`. Change the prefix passed to
`flow_note!` in `main.roc` to try another value.

[Short-label PDF](operations-handbook-flow-short.pdf) ·
[Long-label PDF](operations-handbook-flow-long.pdf) ·
[Long-label preview](preview-flow-long.png)
