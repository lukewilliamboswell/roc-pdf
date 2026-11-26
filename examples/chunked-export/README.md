# Stream a cold-chain telemetry report

Run `roc run main.roc` in this directory to write `chunked-export.pdf`.
The app seals the document with `Pdf.prepare` before opening the sink.
It calls `Pdf.next_chunk` and writes each chunk directly with
`File.with_writer!`, keeping only the running count of chunks and bytes.

```sh
roc run main.roc balanced share
roc run main.roc smallest own
roc run main.roc fastest buffered
```

Use `balanced`, `smallest`, or `fastest` to set compression at preparation.
For each compression choice, use `share` or `own` to stream, or `buffered`
to use the single-list export. The gallery check compares all three
byte-for-byte for each compression choice. See the [balanced PDF](chunked-export.pdf),
[smallest PDF](chunked-export-smallest.pdf), and [fastest PDF](chunked-export-fastest.pdf).
They share the [preview](preview.png).

Choose `ShareUnchangedResources` when the sink consumes each chunk promptly.
An unchanged resource chunk may share its source allocation. Choose
`OwnChunks` when the sink queues or retains chunks and you want bounded owned
chunk buffers.
