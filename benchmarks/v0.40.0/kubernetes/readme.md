Version: v0.40.0

Deployment Pattern: kubernetes (Azure AKS)

Thunder Image: ghcr.io/thunder-id/thunderid:0.40.0

Database Type: Varies per test — Client Credentials used Postgres (DB) with In-Memory caching; Authorization Code runs used Redis (DB) with Redis caching (see each run)

Performance Repo: https://github.com/asgardeo/thunder-performance


## Summary

| Scenario Name | Heap Size | Concurrent Users | Label | # Samples | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Client Credentials Grant Type | N/A | 10000 | 1 Get access token | 25800943 | 0.00 | 34316.43 | 111.29 | 667.00 |
| Authorization Code Grant Type | N/A | 1000 | 1 Send request to authorize endpoint | 1447178 | 0.00 | 2009.85 | 108.00 | 239.00 |
| Authorization Code Grant Type | N/A | 1000 | 2 Start Authentication Flow | 1447133 | 0.00 | 2009.83 | 101.64 | 223.00 |
| Authorization Code Grant Type | N/A | 1000 | 3 Perform authentication | 1447262 | 0.00 | 2010.00 | 106.41 | 227.00 |
| Authorization Code Grant Type | N/A | 1000 | 4 Obtain authorization code | 1447347 | 0.00 | 2010.12 | 102.59 | 228.00 |
| Authorization Code Grant Type | N/A | 1000 | 5 Obtain access token | 1447263 | 0.00 | 2010.11 | 72.78 | 162.00 |
| Authorization Code Grant Type | N/A | 10000 | 1 Send request to authorize endpoint | 4954570 | 0.00 | 6860.09 | 422.03 | 3679.00 |
| Authorization Code Grant Type | N/A | 10000 | 2 Start Authentication Flow | 4954596 | 0.00 | 6870.77 | 166.11 | 1391.00 |
| Authorization Code Grant Type | N/A | 10000 | 3 Perform authentication | 4954516 | 0.00 | 6861.87 | 361.00 | 2879.00 |
| Authorization Code Grant Type | N/A | 10000 | 4 Obtain authorization code | 4954500 | 0.00 | 6882.11 | 16.63 | 30.00 |
| Authorization Code Grant Type | N/A | 10000 | 5 Obtain access token | 4954463 | 0.00 | 6860.02 | 371.89 | 3183.00 |
| Authorization Code Grant Type | N/A | 10000 | 1 Send request to authorize endpoint | 5096688 | 0.00 | 7061.05 | 417.63 | 1991.00 |
| Authorization Code Grant Type | N/A | 10000 | 2 Start Authentication Flow | 5096908 | 0.00 | 7070.08 | 165.56 | 771.00 |
| Authorization Code Grant Type | N/A | 10000 | 3 Perform authentication | 5096962 | 0.00 | 7063.03 | 324.41 | 1511.00 |
| Authorization Code Grant Type | N/A | 10000 | 4 Obtain authorization code | 5096814 | 0.00 | 7079.51 | 17.67 | 32.00 |
| Authorization Code Grant Type | N/A | 10000 | 5 Obtain access token | 5096809 | 0.00 | 7061.24 | 370.91 | 1759.00 |

## Test Runs

### 1. Client Credentials Grant Type — 10000 Concurrent Users

Test Duration: 15m

Total Samples: 25800943

Total Throughput (Requests/sec): 34316.43

Data: [client-credentials-10000conc.csv](client-credentials-10000conc.csv)

Run: https://dev.azure.com/WSO2-Thunder/thunder-performance/_build/results?buildId=1144&view=results

**K8s Spec**

- Nodes: 5 nodes (F32s_v2)
- Thunder Pods: 4 vCore + 2Gi, min-pods: 15, max-pods: 32, running: 32
- Heap Size: 4g
- Database: Postgres (legacy DB)
- Caching: In-Memory

| Scenario Name | Concurrent Users | Label | # Samples | Error Count | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Client Credentials Grant Type | 10000 | 1 Get access token | 25800943 | 43 | 0.00 | 34316.43 | 111.29 | 667.00 |

### 2. Authorization Code Grant Type — 1000 Concurrent Users (Redis DB & Cache)

Test Duration: 15m

Total Samples: 7236183

Total Throughput (Requests/sec): 10049.91

Data: [authorization-code-1000conc.csv](authorization-code-1000conc.csv)

**K8s Spec**

- Node Pool: F16s_v2 x 5
- Thunder Pods: 4 vCore + 2Gi, min-pods: 3, max-pods: 6
- In-Cluster Redis Pods:
  - Redis-master: 8 vCore + 16Gi
  - Redis-replica: 1 vCore + 2Gi, min-pods: 4, max-pods: 6
- Nginx Pods: 1 vCore + 1Gi, min-pods: 5, max-pods: 8
- VM Spec: F16s_v2, Heap Size: 4g
- Database: Redis
- Caching: Redis
- DB Specs:
  - Config: D8s_v3
  - User: D8s_v3
  - Runtime: Redis

| Scenario Name | Concurrent Users | Label | # Samples | Error Count | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Authorization Code Grant Type | 1000 | 1 Send request to authorize endpoint | 1447178 | 0 | 0.00 | 2009.85 | 108.00 | 239.00 |
| Authorization Code Grant Type | 1000 | 2 Start Authentication Flow | 1447133 | 0 | 0.00 | 2009.83 | 101.64 | 223.00 |
| Authorization Code Grant Type | 1000 | 3 Perform authentication | 1447262 | 0 | 0.00 | 2010.00 | 106.41 | 227.00 |
| Authorization Code Grant Type | 1000 | 4 Obtain authorization code | 1447347 | 0 | 0.00 | 2010.12 | 102.59 | 228.00 |
| Authorization Code Grant Type | 1000 | 5 Obtain access token | 1447263 | 1 | 0.00 | 2010.11 | 72.78 | 162.00 |

### 3. Authorization Code Grant Type — 10000 Concurrent Users, 50M Users (Redis DB & Cache)

Test Duration: 15m

Total Samples: ~24769000

Total Throughput (Requests/sec): 34334.86

Data: [authorization-code-10000conc-50M.csv](authorization-code-10000conc-50M.csv)

**K8s Spec**

- Node Pool: F64s_v2 x 4, in-use: F64s_v2 x 3
- Thunder Pods: 4 vCore + 2Gi, min-pods: 15, max-pods: 32, running-pods: 24
- In-Cluster Redis Pods:
  - Redis-master: 16 vCore + 32Gi
  - Redis-replica: 6 vCore + 8Gi, min-pods: 5, max-pods: 10, running-pods: 5
- Nginx Pods: 4 vCore + 4Gi, min-pods: 7, max-pods: 10, running-pods: 7
- VM Spec: F72s_v2, Heap Size: 32g
- Database: Redis
- Caching: Redis
- DB Specs:
  - Config: D8s_v3
  - User: D8s_v3 (50M)
  - Runtime: Redis

| Scenario Name | Concurrent Users | Label | # Samples | Error Count | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Authorization Code Grant Type | 10000 | 1 Send request to authorize endpoint | 4954570 | 0 | 0.00 | 6860.09 | 422.03 | 3679.00 |
| Authorization Code Grant Type | 10000 | 2 Start Authentication Flow | 4954596 | 0 | 0.00 | 6870.77 | 166.11 | 1391.00 |
| Authorization Code Grant Type | 10000 | 3 Perform authentication | 4954516 | 65 | 0.00 | 6861.87 | 361.00 | 2879.00 |
| Authorization Code Grant Type | 10000 | 4 Obtain authorization code | 4954500 | 0 | 0.00 | 6882.11 | 16.63 | 30.00 |
| Authorization Code Grant Type | 10000 | 5 Obtain access token | 4954463 | 65 | 0.00 | 6860.02 | 371.89 | 3183.00 |

### 4. Authorization Code Grant Type — 10000 Concurrent Users, 50M Users (Redis DB & Cache, larger User DB)

Test Duration: 15m

Total Samples: 25484181

Total Throughput (Requests/sec): 35334.91

Data: [authorization-code-10000conc-50M-d16s-userdb.csv](authorization-code-10000conc-50M-d16s-userdb.csv)

**K8s Spec**

- Node Pool: F64s_v2 x 4, in-use: F64s_v2 x 3
- Thunder Pods: 4 vCore + 2Gi, min-pods: 25, max-pods: 32, running-pods: 25
- In-Cluster Redis Pods:
  - Redis-master: 16 vCore + 32Gi
  - Redis-replica: 6 vCore + 8Gi, min-pods: 5, max-pods: 10, running-pods: 5
- Nginx Pods: 4 vCore + 4Gi, min-pods: 7, max-pods: 10, running-pods: 7
- VM Spec: F72s_v2, Heap Size: 32g
- Database: Redis
- Caching: Redis
- DB Specs:
  - Config: D8s_v3
  - User: D16s_v3 (50M)
  - Runtime: Redis

| Scenario Name | Concurrent Users | Label | # Samples | Error Count | Error % | Throughput (Requests/sec) | Average Response Time (ms) | 95th Percentile of Response Time (ms) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Authorization Code Grant Type | 10000 | 1 Send request to authorize endpoint | 5096688 | 0 | 0.00 | 7061.05 | 417.63 | 1991.00 |
| Authorization Code Grant Type | 10000 | 2 Start Authentication Flow | 5096908 | 0 | 0.00 | 7070.08 | 165.56 | 771.00 |
| Authorization Code Grant Type | 10000 | 3 Perform authentication | 5096962 | 0 | 0.00 | 7063.03 | 324.41 | 1511.00 |
| Authorization Code Grant Type | 10000 | 4 Obtain authorization code | 5096814 | 0 | 0.00 | 7079.51 | 17.67 | 32.00 |
| Authorization Code Grant Type | 10000 | 5 Obtain access token | 5096809 | 0 | 0.00 | 7061.24 | 370.91 | 1759.00 |
</content>
</invoke>
