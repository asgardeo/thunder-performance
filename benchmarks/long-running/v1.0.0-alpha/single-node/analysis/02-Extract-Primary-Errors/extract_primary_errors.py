"""Keep only primary failures from errors.csv.

Steps run sequentially per thread, so within one loop iteration the step index
only increases. A non-increase means a new iteration; the first error of each
iteration is primary, the rest are cascade fallout.
"""
import csv
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "01-Source-Data", "errors.csv")
OUT = os.path.join(HERE, "primary_errors.csv")

rows = list(csv.DictReader(open(SRC)))

by_thread = defaultdict(list)
for r in rows:
    by_thread[r["threadName"]].append(r)

primary = []
for thread_rows in by_thread.values():
    thread_rows.sort(key=lambda r: int(r["epoch_ms"]))
    prev_step = None
    for r in thread_rows:
        step = int(r["label"][0])
        if prev_step is None or step <= prev_step:
            primary.append(r)
        prev_step = step

primary.sort(key=lambda r: int(r["epoch_ms"]))
with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(primary)

print("%d rows -> %d primary (%d secondary dropped)"
      % (len(rows), len(primary), len(rows) - len(primary)))
