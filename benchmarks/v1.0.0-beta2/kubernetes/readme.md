Version: v1.0.0-beta2

Deployment Pattern: kubernetes (Azure AKS)

Thunder Image: ghcr.io/thunder-id/thunderid:1.0.0-beta2

Database Type: Postgres (config, runtime transient, runtime persistent and entity stores) with In-Memory caching

Test Date: 2026-08-13

Concurrency: 10000

Test Duration: 15m per scenario (first 5m discarded as warm-up, 10m measurement window)

Performance Repo: https://github.com/asgardeo/thunder-performance

Checkout Ref (code under test): main (ff7cb7e)

Pipeline Build: 1500


## Summary

| Scenario Name | Heap Size | Concurrent Users | Label | # Samples | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Client Credentials Grant Type | N/A | 10000 | 1 Get access token | 11264345 | 0.00 | 17007.43 | 15.54 | 56.00 |

The Authorization Code Grant Type and User Authentication with Credentials scenarios also ran at
this concurrency in the same suite. Their error rates were too high for the results to be reported
as a benchmark, so they are excluded here.


## Environment

- Node Pool: F32s_v2 x 5
- Thunder Pods: 4 vCore + 2Gi, min-pods: 15, max-pods: 32
- Nginx Pods: 2 vCore requests / 4 vCore limits + 4Gi, min-pods: 7, max-pods: 10
- VM Spec (JMeter client): F64s_v2, Heap Size: 4g
- Database: Postgres
- Caching: In-Memory
- DB Specs:
  - Config: D8s_v3
  - Runtime (transient and persistent): D8s_v3
  - User: D8s_v3
- Think-time delays: disabled

## Test Runs

### 1. Client Credentials Grant Type — 10000 Concurrent Users

Total Samples: 11264345

Total Throughput (Requests/sec): 17007.43

Data: [client-credentials-10000conc.csv](client-credentials-10000conc.csv)

| Scenario Name | Concurrent Users | Label | # Samples | Error Count | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Client Credentials Grant Type | 10000 | 1 Get access token | 11264345 | 0 | 0.00 | 17007.43 | 15.54 | 56.00 |

**This run was load generator bound, not server bound.** The JMeter client load average was
69.59 on a 64 vCore F64s_v2, so the client was CPU saturated. During steady state JMeter reported
all 10000 threads active at an average response time of 13ms while sustaining only about 16500
requests/sec, which is roughly 1.65 iterations per thread per second. If the server were the
constraint, 10000 threads against a 13ms response would drive far more. The figure is therefore a
lower bound on what Thunder can serve. The v0.40.0 Postgres run at this concurrency has the same
problem (client load average 119.78 on a 72 vCore F72s_v2), so the two are not a clean comparison
of server capacity.

The 842 errors JMeter recorded for this scenario all occurred during thread ramp-up, inside the
warm-up window, so they fall outside the measured results above.
