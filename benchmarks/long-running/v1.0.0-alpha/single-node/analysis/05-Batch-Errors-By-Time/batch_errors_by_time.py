"""Group the remaining errors into incidents by idle gap.

Consecutive inter-error gaps are either under 30s or over 2min -- nothing in
between -- so a 60s idle threshold splits incidents unambiguously.
"""
import csv
import os
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "03-Remove-Errors-Due-To-DB-Upgrade",
                   "primary_errors_excl_db_upgrade.csv")
OUT = os.path.join(HERE, "error_events.csv")

GAP_MS = 60000

rows = sorted(csv.DictReader(open(SRC)), key=lambda r: int(r["epoch_ms"]))

events = []
for r in rows:
    t = int(r["epoch_ms"])
    if events and t - events[-1][-1] <= GAP_MS:
        events[-1].append(t)
    else:
        events.append([t])

utc = lambda ms: datetime.fromtimestamp(ms / 1000, timezone.utc).strftime(
    "%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

with open(OUT, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["start_utc", "end_utc", "span_s", "errors", "gap_from_prev_min"])
    for i, e in enumerate(events):
        gap = "" if i == 0 else "%.1f" % ((e[0] - events[i - 1][-1]) / 60000)
        w.writerow([utc(e[0]), utc(e[-1]), "%.1f" % ((e[-1] - e[0]) / 1000),
                    len(e), gap])

print("%d errors -> %d events (largest %d errors, longest span %.1fs)"
      % (len(rows), len(events), max(len(e) for e in events),
         max(e[-1] - e[0] for e in events) / 1000))
