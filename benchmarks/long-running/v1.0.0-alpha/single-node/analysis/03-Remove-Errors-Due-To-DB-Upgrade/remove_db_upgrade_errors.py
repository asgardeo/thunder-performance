"""Drop primary failures caused by the RDS minor version upgrade.

RDS events for wso2thunderdbinstance6232 on 2026-08-01:
  08:43:26.558  downtime started
  08:43:28.829  DB instance shutdown
  08:43:51.703  engine version upgrade started
  08:43:59.221  DB instance restarted
  08:44:22.960  engine version upgrade finished
  08:44:36.603  minor version upgrade complete (17.6.R2 -> 17.9.R2)
Everything from downtime start to upgrade complete is treated as DB downtime.
"""
import csv
import os
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "02-Extract-Primary-Errors", "primary_errors.csv")
OUT = os.path.join(HERE, "primary_errors_excl_db_upgrade.csv")

ms = lambda s: int(datetime.fromisoformat(s).timestamp() * 1000)
START = ms("2026-08-01T08:43:26.558+00:00")
END = ms("2026-08-01T08:44:36.603+00:00")

rows = list(csv.DictReader(open(SRC)))
kept = [r for r in rows if not START <= int(r["epoch_ms"]) <= END]

with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(kept)

print("%d primary -> %d kept (%d dropped as DB downtime)"
      % (len(rows), len(kept), len(rows) - len(kept)))
