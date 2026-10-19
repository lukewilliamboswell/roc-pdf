"""gdb script for `scripts/alloc_trace.py`: record the Roc call stack of every
`roc_alloc`/`roc_realloc` between the first and last `PROFILE` marker.

Loaded with `gdb -batch -x`; reads its options from the environment so it
needs no argument parsing inside gdb.
"""
import collections
import json
import os

import gdb

DEPTH = int(os.environ.get("ALLOC_TRACE_DEPTH", "40"))
OUT = os.environ["ALLOC_TRACE_OUT"]

stacks = collections.Counter()


def frames():
    names = []
    frame = gdb.newest_frame()
    while frame is not None and len(names) < DEPTH:
        name = frame.name() or "?"
        sal = frame.find_sal()
        where = f"{os.path.basename(sal.symtab.filename)}:{sal.line}" if sal.symtab is not None else ""
        names.append(f"{name}@{where}")
        frame = frame.older()
    return names


class AllocBreak(gdb.Breakpoint):
    def stop(self):
        names = frames()
        stacks[tuple(names)] += 1
        return False


for symbol in ("roc_alloc", "roc_realloc"):
    AllocBreak(symbol, internal=True)

gdb.execute("run")
with open(OUT, "w") as out:
    json.dump([{"count": count, "stack": list(stack)} for stack, count in stacks.items()], out)
