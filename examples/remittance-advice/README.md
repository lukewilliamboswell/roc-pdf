# Remittance advice

Make a PDF for a preprinted payment form with exact field positions and
an explicit reading order. Run the example with the pinned Roc toolchain.

```sh
roc run examples/remittance-advice/main.roc
```

The program writes `remittance-advice.pdf` in the working directory. It places
the same kind of remittance on a US Letter sheet and an A4 sheet. The amounts
and invoice references differ between sheets. [Generated PDF](remittance-advice.pdf)

In `Remittance.roc`, the calls to `.place` establish reading order.
`.with_paint_order` uses zero-based indexes into each sheet’s placement
sequence. The introductory instruction precedes the payment amount in the
structure tree, even though the amount paints first. The colored background
and rule are page artifacts. The payment information is authored as
searchable text in the placement frames.

Frames use page coordinates in points with the origin at the lower left.
Choose each frame’s size for its content. The example uses the default
PDF/A-4 and PDF/UA-2 profile.
