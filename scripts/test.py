#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROC = os.environ.get("ROC", "roc")


def run(*args: str) -> None:
    command = [ROC, *args]
    print("+", " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def main() -> None:
    run("version")

    for source in sorted((ROOT / "package").glob("*.roc")):
        run("fmt", "--check", source.relative_to(ROOT).as_posix())

    run("check", "package/main.roc")
    run("test", "package/main.roc")


if __name__ == "__main__":
    main()
