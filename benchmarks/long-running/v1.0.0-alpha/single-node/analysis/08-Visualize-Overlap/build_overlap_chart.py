"""Build a zoomable HTML timeline of error events vs autovacuum vs sampler windows.

Reads the three interval sets produced by steps 05-07, the RDS metric samples and
the JMeter latency-drift buckets, and writes a single self-contained overlap.html
(no external assets).
"""
import csv
import json
import os
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(HERE, "overlap.html")

TPL = os.path.join(HERE, "template.html")


def ts(s):
    s = s.replace("Z", "+0000")
    fmt = "%Y-%m-%dT%H:%M:%S.%f%z" if "." in s else "%Y-%m-%dT%H:%M:%S%z"
    return datetime.strptime(s, fmt).timestamp()


def load(path):
    with open(os.path.join(ROOT, path)) as f:
        return list(csv.DictReader(f))


events = [(ts(r["start_utc"]), ts(r["end_utc"]), int(r["errors"]))
          for r in load("05-Batch-Errors-By-Time/error_events.csv")]
vacuums = [(ts(r["start_utc"]), ts(r["end_utc"]), r["table"].split(".")[-1],
            r["kind"] + (" (aggressive)" if r["aggressive"] == "True" else ""))
           for r in load("06-Identify-Autovacuum-Periods/autovacuum_periods.csv")]
samples = [(ts(r["start_utc"]), ts(r["end_utc"]), float(r["duration_s"]))
           for r in load("07-Identify-Sampling-Periods/sampling_periods.csv")
           if r["end_utc"]]

events.sort(), vacuums.sort(), samples.sort()

# --- RDS metrics -----------------------------------------------------------
# NB: the column is named timestamp_utc but the values carry a +05:30 offset.
# fromisoformat honours it; treating them as UTC would shift everything 5.5h.
METRICS = [
    ("total_iops",      "Total IOPS",       "ops/s", 0, 1),
    ("ReadIOPS",        "Read IOPS",        "ops/s", 0, 1),
    ("WriteIOPS",       "Write IOPS",       "ops/s", 0, 1),
    ("DiskQueueDepth",  "Disk queue depth", "",      2, 1),
    ("ReadLatency",     "Read latency",     "ms",    2, 1000),
    ("WriteLatency",    "Write latency",    "ms",    2, 1000),
    ("ReadThroughput",  "Read throughput",  "MB/s",  1, 1e-6),
    ("WriteThroughput", "Write throughput", "MB/s",  1, 1e-6),
]

iops = load("01-Source-Data/rds-iops.csv")
itimes = [datetime.fromisoformat(r["timestamp_utc"]).timestamp() for r in iops]

# --- JMeter latency buckets -------------------------------------------------
# bucket_start_epoch is a plain UTC epoch, so no timezone guesswork here.
lat = load("01-Source-Data/latency-drift.csv")
BUCKET = 300
ltimes = [int(r["bucket_start_epoch"]) for r in lat]

LSERIES = [
    ("p50",   "p50_ms",     lambda r: float(r["p50_ms"])),
    ("p95",   "p95_ms",     lambda r: float(r["p95_ms"])),
    ("p99",   "p99_ms",     lambda r: float(r["p99_ms"])),
    ("mean",  "mean_ms",    lambda r: float(r["mean_ms"])),
    ("count", "count",      lambda r: int(r["count"])),
    ("err",   "error_rate", lambda r: round(100 * float(r["error_rate"]), 4)),
]
lseries = {k: [fn(r) for r in lat] for k, _, fn in LSERIES}

# --- overlap flags per error event -----------------------------------------
def hits(e, intervals):
    return [i for i in intervals if i[0] <= e[1] and e[0] <= i[1]]


vac_lo = min(v[0] for v in vacuums)          # DB logs only cover from here on
vac_hi = max(v[1] for v in vacuums)

flagged = []
for s, e, n in events:
    v, p = hits((s, e), vacuums), hits((s, e), samples)
    flagged.append({"s": s, "e": e, "n": n, "vac": bool(v), "smp": bool(p),
                    "covered": s >= vac_lo,
                    "vt": ", ".join(sorted({x[2] for x in v}))})

# --- headline numbers -------------------------------------------------------
def coverage(intervals, lo, hi):
    return sum(min(b, hi) - max(a, lo) for a, b, *_ in intervals
               if b > lo and a < hi)


span_lo, span_hi = min(e[0] for e in events), max(e[1] for e in events)
in_cov = [f for f in flagged if f["covered"]]

# Base rates are measured over each source's OWN span, not over the error span.
# A run with one short event would otherwise divide by a couple of seconds.
smp_lo, smp_hi = min(s[0] for s in samples), max(s[1] for s in samples)

def median(xs):
    s = sorted(xs)
    n = len(s)
    if not n:
        return 0.0
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2


# p95 drift: least-squares slope in ms/hour over the whole run, with R².
def slope_r2(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    den = sum((a - mx) ** 2 for a in xs)
    if den == 0:
        return 0.0, 0.0
    m = sum((a - mx) * (b - my) for a, b in zip(xs, ys)) / den
    c = my - m * mx
    ss_res = sum((b - (m * a + c)) ** 2 for a, b in zip(xs, ys))
    ss_tot = sum((b - my) ** 2 for b in ys)
    return m, (1 - ss_res / ss_tot if ss_tot else 0.0)


lat_slope, lat_r2 = slope_r2([(t - ltimes[0]) / 3600 for t in ltimes],
                             lseries["p95"])

# Does an error event land in a latency bucket that is worse than a typical one?
err_buckets = set()
for s, e, _ in events:
    for i, t in enumerate(ltimes):
        if t <= e and s <= t + BUCKET:
            err_buckets.add(i)
p99_err = median([lseries["p99"][i] for i in sorted(err_buckets)])
p99_all = median([v for i, v in enumerate(lseries["p99"]) if i not in err_buckets])

stats = {
    "lat_buckets": len(lat),
    "lat_slope": lat_slope,
    "lat_r2": lat_r2,
    "lat_p99_max": max(lseries["p99"]),
    "lat_p99_err": p99_err,
    "lat_p99_base": p99_all,
    "lat_err_buckets": len(err_buckets),
    "events": len(events),
    "errors": sum(e[2] for e in events),
    "smp_events": sum(1 for f in flagged if f["smp"]),
    "smp_duty": 100 * coverage(samples, smp_lo, smp_hi) / (smp_hi - smp_lo),
    "vac_events": sum(1 for f in in_cov if f["vac"]),
    "vac_total": len(in_cov),
    "vac_errors": sum(f["n"] for f in in_cov if f["vac"]),
    "vac_errtotal": sum(f["n"] for f in in_cov),
    "vac_duty": 100 * coverage(vacuums, vac_lo, vac_hi) / (vac_hi - vac_lo),
    "neither": sum(1 for f in in_cov if not f["vac"] and not f["smp"]),
}

t0 = min(span_lo, vac_lo, min(s[0] for s in samples), min(itimes), min(ltimes))
t1 = max(span_hi, vac_hi, max(s[1] for s in samples), max(itimes),
         max(ltimes) + BUCKET)

series, mmeta = {}, []
for key, label, unit, dp, mul in METRICS:
    vals = []
    for r in iops:
        v = r.get(key, "")
        vals.append(round(float(v) * mul, dp) if v not in ("", None) else None)
    series[key] = vals
    got = [v for v in vals if v is not None]
    mmeta.append({"key": key, "label": label, "unit": unit,
                  "max": max(got) if got else 0})

# One panel, one y-axis: a view is either the three percentiles (same unit, so
# one scale is honest) or a single series. Never two scales on one plot.
LVIEWS = [
    ("pct",   "Latency percentiles", "ms",         1, ["p50", "p95", "p99"]),
    ("p99",   "p99 latency",         "ms",         1, ["p99"]),
    ("p95",   "p95 latency",         "ms",         1, ["p95"]),
    ("p50",   "p50 latency",         "ms",         1, ["p50"]),
    ("mean",  "Mean latency",        "ms",         1, ["mean"]),
    ("count", "Throughput",          "req/bucket", 0, ["count"]),
    ("err",   "Error rate",          "%",          0, ["err"]),
]
LABEL = {"p50": "p50", "p95": "p95", "p99": "p99", "mean": "mean",
         "count": "requests", "err": "error rate"}
COLOR = {"p50": "--lat-1", "p95": "--lat-2", "p99": "--lat-3",
         "mean": "--lat-2", "count": "--text-secondary", "err": "--errors"}

lviews = [{"key": k, "label": lbl, "unit": u, "log": log,
           "max": max(max(lseries[s]) for s in keys),
           "series": [{"key": s, "label": LABEL[s], "color": COLOR[s]}
                      for s in keys]}
          for k, lbl, u, log, keys in LVIEWS]

payload = {
    "t0": t0, "t1": t1, "vacLo": vac_lo, "vacHi": vac_hi, "stats": stats,
    # [offset_from_t0, duration, ...extra] — keeps the embedded JSON small
    "events": [[round(f["s"] - t0, 3), round(f["e"] - f["s"], 3), f["n"],
                int(f["vac"]), int(f["smp"]), f["vt"]] for f in flagged],
    "vacuums": [[round(a - t0, 3), round(b - a, 3), tbl, kind]
                for a, b, tbl, kind in vacuums],
    "samples": [[round(a - t0, 3), round(b - a, 3)] for a, b, _ in samples],
    # DiskQueueDepth leads: it separates error minutes from the baseline by 16.6x,
    # where total_iops only manages 1.7x.
    "iops": {"t": [round(t - t0) for t in itimes], "series": series,
             "meta": mmeta, "default": "DiskQueueDepth"},
    "lat": {"t": [round(t - t0) for t in ltimes], "series": lseries,
            "views": lviews, "default": "pct", "bucket": BUCKET},
}

with open(TPL) as f:
    html = f.read()
html = html.replace("__PAYLOAD__", json.dumps(payload, separators=(",", ":")))
with open(OUT, "w") as f:
    f.write(html)

print("wrote %s (%.0f KB)" % (os.path.basename(OUT), os.path.getsize(OUT) / 1024))
print("  %d error events / %d errors | %d vacuums | %d sampler windows"
      % (stats["events"], stats["errors"], len(vacuums), len(samples)))
print("  sampler overlap %d/%d events (duty cycle %.1f%%)"
      % (stats["smp_events"], stats["events"], stats["smp_duty"]))
print("  vacuum overlap %d/%d events, %d/%d errors (duty cycle %.1f%%)"
      % (stats["vac_events"], stats["vac_total"], stats["vac_errors"],
         stats["vac_errtotal"], stats["vac_duty"]))
print("  %d RDS metric samples, %s UTC -> %s UTC (%d metrics)"
      % (len(itimes), datetime.utcfromtimestamp(min(itimes)),
         datetime.utcfromtimestamp(max(itimes)), len(METRICS)))
print("  %d latency buckets (%ds), %s UTC -> %s UTC"
      % (len(lat), BUCKET, datetime.utcfromtimestamp(min(ltimes)),
         datetime.utcfromtimestamp(max(ltimes) + BUCKET)))
print("  p95 drift %+.4f ms/h (R2 %.3f) | p99 peak %.0f ms"
      % (lat_slope, lat_r2, stats["lat_p99_max"]))
print("  p99 median %.0f ms in the %d buckets holding an error event, %.0f ms elsewhere"
      % (p99_err, len(err_buckets), p99_all))
