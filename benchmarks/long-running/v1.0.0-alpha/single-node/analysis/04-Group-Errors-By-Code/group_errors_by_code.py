"""Count remaining errors by response code, with elapsed time range."""
import csv
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "03-Remove-Errors-Due-To-DB-Upgrade",
                   "primary_errors_excl_db_upgrade.csv")

elapsed = defaultdict(list)
for r in csv.DictReader(open(SRC)):
    elapsed[r["responseCode"]].append(int(r["elapsed"]))

print("%-6s %7s %10s %10s" % ("code", "count", "min_ms", "max_ms"))
for code in sorted(elapsed):
    e = elapsed[code]
    print("%-6s %7d %10d %10d" % (code, len(e), min(e), max(e)))
