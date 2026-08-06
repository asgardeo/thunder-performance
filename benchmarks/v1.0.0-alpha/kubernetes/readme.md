Version: v1.0.0-alpha

Deployment Pattern: kubernetes (Azure AKS)

Thunder Image: ghcr.io/thunder-id/thunderid:1.0.0-alpha

Database Type: Postgres (DB) with In-Memory caching

Performance Repo: https://github.com/asgardeo/thunder-performance

Test Configuration: USE_DELAYS=true, Warm-up: 2m, Test Duration: 15m per scenario

> **Note on the 10000 concurrent user run:** that run is not a valid benchmark. Error rates were
> 93-100% across every scenario. The single JMeter client VM (Standard_F8s_v2, 8 vCore) was
> saturated (load average ~100-126) and had exhausted its ephemeral ports (9963 sockets in
> TIME_WAIT at the end of the Client Credentials scenario). It is recorded here for traceability
> only, and its numbers must not be quoted as Thunder throughput. See run 2 below.


## Summary

Only the 1000 concurrent user run produced usable numbers.

| Scenario Name | Heap Size | Concurrent Users | Label | # Samples | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Client Credentials Grant Type | N/A | 1000 | 1 Get access token | 2527085 | 0.30 | 3228.94 | 308.20 | 1367.00 |
| Authorization Code Grant Type | N/A | 1000 | 1 Send request to authorize endpoint | 127987 | 0.00 | 164.11 | 20.57 | 36.00 |
| Authorization Code Grant Type | N/A | 1000 | 2 Start Authentication Flow | 127985 | 0.01 | 164.10 | 12.36 | 32.00 |
| Authorization Code Grant Type | N/A | 1000 | 3 Perform authentication | 127993 | 0.08 | 164.11 | 26.16 | 39.00 |
| Authorization Code Grant Type | N/A | 1000 | 4 Obtain authorization code | 127995 | 0.04 | 164.12 | 15.43 | 37.00 |
| Authorization Code Grant Type | N/A | 1000 | 5 Obtain access token | 127989 | 0.09 | 164.11 | 12.97 | 30.00 |
| User Authentication with Credentials | N/A | 1000 | 1 Perform user authentication | 3468259 | 0.00 | 4443.35 | 224.35 | 1151.00 |

The Authorization Code scenario carries a Gaussian think-time delay of 6000ms (range 2000ms)
between iterations because USE_DELAYS was true, so its throughput is delay-bound rather than
server-bound. The Client Credentials and User Authentication scenarios have no such timer and
run at maximum throughput.


## Test Runs

### 1. All Scenarios — 1000 Concurrent Users

Test Duration: 15m per scenario

Warm-up Time: 2m

USE_DELAYS: true

Total Samples: 6635293

Data: [results-1000conc.csv](results-1000conc.csv)

**K8s Spec**

- AKS Version: 1.34
- Node Pool: Standard_F8s_v2, count: 2, autoscale min: 2, max: 5, max-pods-per-node: 30
- Thunder Pods: requests 1 vCore + 256Mi, limits 1.5 vCore + 512Mi, replicas: 2, HPA max-pods: 10 (CPU 65%, Memory 75%)
- Nginx Ingress Pods: requests 0.5 vCore + 500Mi, limits 1 vCore + 1000Mi, min-pods: 2, max-pods: 5 (CPU 80%, Memory 80%)
- JMeter Client VM: Standard_F8s_v2, Heap Size: 4g
- Database: Postgres 17
- Caching: In-Memory
- DB Specs:
  - Config: GP_Standard_D2s_v3
  - Runtime: GP_Standard_D2s_v3
  - User: GP_Standard_D2s_v3

| Scenario Name | Concurrent Users | Label | # Samples | Error Count | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Client Credentials Grant Type | 1000 | 1 Get access token | 2527085 | 7558 | 0.30 | 3228.94 | 308.20 | 1367.00 |
| Authorization Code Grant Type | 1000 | 1 Send request to authorize endpoint | 127987 | 4 | 0.00 | 164.11 | 20.57 | 36.00 |
| Authorization Code Grant Type | 1000 | 2 Start Authentication Flow | 127985 | 8 | 0.01 | 164.10 | 12.36 | 32.00 |
| Authorization Code Grant Type | 1000 | 3 Perform authentication | 127993 | 106 | 0.08 | 164.11 | 26.16 | 39.00 |
| Authorization Code Grant Type | 1000 | 4 Obtain authorization code | 127995 | 50 | 0.04 | 164.12 | 15.43 | 37.00 |
| Authorization Code Grant Type | 1000 | 5 Obtain access token | 127989 | 109 | 0.09 | 164.11 | 12.97 | 30.00 |
| User Authentication with Credentials | 1000 | 1 Perform user authentication | 3468259 | 136 | 0.00 | 4443.35 | 224.35 | 1151.00 |

### 2. All Scenarios — 10000 Concurrent Users (INVALID — load generator saturated)

Test Duration: 15m per scenario

Warm-up Time: 2m

USE_DELAYS: true

Total Samples: 12763069

Data: [results-10000conc.csv](results-10000conc.csv)

**Why this run is not usable**

- Error rates of 93.39% (Client Credentials), 98.23-100.00% (Authorization Code steps) and 99.85%
  (User Authentication).
- JMeter client load average reached 125.91 / 91.62 / 51.33 on an 8 vCore VM.
- 9963 of 9968 client TCP sockets were in TIME_WAIT at the end of the Client Credentials scenario,
  indicating ephemeral port exhaustion on the load generator.
- The AKS side is also undersized for this level: 2 x Standard_F8s_v2 nodes with Thunder capped at
  10 pods of 1.5 vCore cannot absorb 10000 concurrent users.

To produce a valid 10000 concurrent user run, the load generator needs to be scaled out (multiple
JMeter clients or a larger VM SKU with tuned `net.ipv4.ip_local_port_range` and
`tcp_tw_reuse`), and the AKS node pool and Thunder HPA ceiling need to be raised.

**K8s Spec**

- AKS Version: 1.34
- Node Pool: Standard_F8s_v2, count: 2, autoscale min: 2, max: 5, max-pods-per-node: 30
- Thunder Pods: requests 1 vCore + 256Mi, limits 1.5 vCore + 512Mi, replicas: 2, HPA max-pods: 10 (CPU 65%, Memory 75%)
- Nginx Ingress Pods: requests 0.5 vCore + 500Mi, limits 1 vCore + 1000Mi, min-pods: 2, max-pods: 5 (CPU 80%, Memory 80%)
- JMeter Client VM: Standard_F8s_v2, Heap Size: 4g
- Database: Postgres 17
- Caching: In-Memory
- DB Specs:
  - Config: GP_Standard_D2s_v3
  - Runtime: GP_Standard_D2s_v3
  - User: GP_Standard_D2s_v3

| Scenario Name | Concurrent Users | Label | # Samples | Error Count | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Client Credentials Grant Type | 10000 | 1 Get access token | 2267130 | 2117166 | 93.39 | 2733.27 | 1982.92 | 10815.00 |
| Authorization Code Grant Type | 10000 | 1 Send request to authorize endpoint | 707047 | 704340 | 99.62 | 906.60 | 409.81 | 182.00 |
| Authorization Code Grant Type | 10000 | 2 Start Authentication Flow | 707470 | 706684 | 99.89 | 907.14 | 262.82 | 72.00 |
| Authorization Code Grant Type | 10000 | 3 Perform authentication | 701902 | 701780 | 99.98 | 900.21 | 1391.38 | 10047.00 |
| Authorization Code Grant Type | 10000 | 4 Obtain authorization code | 705076 | 692562 | 98.23 | 904.07 | 619.27 | 3039.00 |
| Authorization Code Grant Type | 10000 | 5 Obtain access token | 707342 | 707336 | 100.00 | 906.98 | 313.39 | 387.00 |
| User Authentication with Credentials | 10000 | 1 Perform user authentication | 6967102 | 6956696 | 99.85 | 8660.87 | 451.74 | 467.00 |
