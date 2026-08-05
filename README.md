# roc-pdf

A pure [Roc](https://www.roc-lang.org/) package for generating PDF/UA-2 documents.

This project is in its initial scaffolding stage. Its public API currently contains only a
placeholder `Foo` module.

## Requirements

- Python 3
- The Roc nightly pinned in [`.roc-version`](.roc-version), available as `roc` on `PATH`

## Development

Run all checks through the Python test driver:

```sh
python3 scripts/test.py
```

Set `ROC` to use a specific compiler executable:

```sh
ROC=/path/to/roc python3 scripts/test.py
```
