"""Extract autovacuum / autoanalyze periods from the RDS postgres logs.

Postgres writes the log entry when the operation *finishes*, so the line
timestamp is the end time and the start is end - elapsed:

    2026-08-03 16:11:58 UTC::@:[15322]:LOG:  automatic vacuum of table "db.public.T": index scans: 1
            ...
            system usage: CPU: user: 3.94 s, system: 1.84 s, elapsed: 69.87 s

Log coverage is partial -- AWS retains these for 3 days only.
"""
import csv
import glob
import os
import re
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "01-Source-Data", "db-logs", "postgresql.log.*")
OUT = os.path.join(HERE, "autovacuum_periods.csv")

HEADER = re.compile(
    r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) UTC.*LOG:  "
    r"automatic (aggressive )?(vacuum|analyze) of table \"([^\"]+)\"")
ELAPSED = re.compile(r"system usage:.*elapsed: ([\d.]+) s")

fmt = lambda d: d.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

rows, pending = [], None
for path in sorted(glob.glob(SRC)):
    for line in open(path, errors="replace"):
        h = HEADER.match(line)
        if h:
            end = datetime.strptime(h.group(1), "%Y-%m-%d %H:%M:%S").replace(
                tzinfo=timezone.utc)
            pending = (end, bool(h.group(2)), h.group(3), h.group(4))
            continue
        e = ELAPSED.search(line)
        if e and pending:
            end, aggressive, kind, table = pending
            secs = float(e.group(1))
            rows.append([fmt(end - timedelta(seconds=secs)), fmt(end),
                         "%.2f" % secs, table, kind, aggressive])
            pending = None

rows.sort()
with open(OUT, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["start_utc", "end_utc", "elapsed_s", "table", "kind",
                "aggressive"])
    w.writerows(rows)

print("%d autovacuum periods -> %s" % (len(rows), os.path.basename(OUT)))
