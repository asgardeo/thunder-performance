"""Derive the busy window of each long-run-sampler.sh iteration.

long-run-sampler.sh is a sleep-after-work loop:

    while :; do sample_once; sleep $SAMPLE_INTERVAL_SECONDS; done

and the CSV timestamp is stamped at the *top* of sample_once. So consecutive
timestamps are INTERVAL apart plus however long the sample took, which makes
the busy window recoverable from the timestamps alone:

    busy = [ t[i] , t[i+1] - INTERVAL ]

The final row has no successor, so its window is left blank.
"""
import csv
import os
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "01-Source-Data", "long-run-metrics.csv")
OUT = os.path.join(HERE, "sampling_periods.csv")

INTERVAL = 300  # SAMPLE_INTERVAL_SECONDS default

starts = [datetime.strptime(r["timestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(
          tzinfo=timezone.utc) for r in csv.DictReader(open(SRC))]
starts.sort()

fmt = lambda d: d.strftime("%Y-%m-%dT%H:%M:%SZ")

rows = []
for i, s in enumerate(starts):
    if i + 1 == len(starts):
        rows.append([fmt(s), "", ""])
        continue
    dur = (starts[i + 1] - s).total_seconds() - INTERVAL
    rows.append([fmt(s), fmt(s + timedelta(seconds=dur)), "%.0f" % dur])

with open(OUT, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["start_utc", "end_utc", "duration_s"])
    w.writerows(rows)

d = sorted(float(r[2]) for r in rows if r[2] != "")
busy = sum(d)
span = (starts[-1] - starts[0]).total_seconds()
print("%d samples | duration_s: min %.0f med %.0f p90 %.0f max %.0f | negative: %d"
      % (len(rows), d[0], d[len(d) // 2], d[int(len(d) * .9)], d[-1],
         sum(1 for x in d if x < 0)))
print("busy %.0fs of %.0fs elapsed = %.1f%% duty cycle"
      % (busy, span, 100 * busy / span))
