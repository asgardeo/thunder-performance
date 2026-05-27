# Seed Users

Bulk seeds test users into the Thunder user database via parallel PostgreSQL `COPY` commands.

## Files

| File | Description |
|------|-------------|
| `seed_users_fast.py` | Python seeding script |
| `seed_users_job.yaml` | Reference Kubernetes Job manifest for manual use |

## Pipeline Usage

The seeding job is integrated into `deploy-thunder.yaml`. Enable it by setting the `SEED_USERS` parameter to `true` and optionally overriding `SEED_USERS_COUNT` (default: `50000000`).

## Manual Usage

### 1. Create the ConfigMap

```bash
kubectl create configmap seed-users-script \
    --from-file=seed_users_fast.py=seed_users_fast.py
```

### 2. Apply the Job

Fill in the values in `seed_users_job.yaml` and apply:

```bash
kubectl apply -f seed_users_job.yaml
```

### 3. Follow logs

```bash
kubectl logs -f job/seed-users
```

### Expected output on completion

```
Loaded 50,000,000 users in 1834.3s (27,259 rows/sec)

Finalizing tables...
  Triggers and autovacuum re-enabled.
  Recreating 3 index(es)...
    CREATE INDEX idx_entity_category_deployment ON public."ENTITY" USING btree (deployment_id, category)...
    CREATE INDEX idx_entity_ou_deployment ON public."ENTITY" USING btree (deployment_id, ou_id)...
    CREATE INDEX idx_entity_identifier_lookup ON public."ENTITY_IDENTIFIER" USING btree (name, value)...
  All indexes recreated.
Finalize took 728.9s
```

---

## Verify Completion

### Check row count

```bash
kubectl run verify-seed --rm -it --restart=Never \
    --image=postgres:16-alpine -- \
    psql "host=<host> port=5432 dbname=userdb user=<user> password=<password> sslmode=require" \
    -c "SELECT count(*) FROM \"ENTITY\" WHERE DEPLOYMENT_ID='default-deployment' AND TYPE='customer';"
```

Expected output:

```
  count
----------
 50000000
(1 row)
```

### Check indexes

```bash
kubectl run check-indexes --rm -it --restart=Never \
    --image=postgres:16-alpine -- \
    psql "host=<host> port=5432 dbname=userdb user=<user> password=<password> sslmode=require" \
    -c "SELECT indexname FROM pg_indexes WHERE tablename IN ('ENTITY', 'ENTITY_IDENTIFIER') ORDER BY tablename, indexname;"
```

Expected output:

```
           indexname
--------------------------------
 ENTITY_pkey
 idx_entity_category_deployment
 idx_entity_ou_deployment
 ENTITY_IDENTIFIER_pkey
 idx_entity_identifier_lookup
(5 rows)
```

> If the three secondary indexes (`idx_entity_category_deployment`, `idx_entity_ou_deployment`, `idx_entity_identifier_lookup`) are missing after the script completes, refer to [Fix Missing Indexes](#fix-missing-indexes).

---

## Fix Missing Indexes

If the finalize step was interrupted and indexes were not recreated, run them manually:

```bash
kubectl run fix-indexes --rm -it --restart=Never \
    --image=postgres:16-alpine -- \
    psql "host=<host> port=5432 dbname=userdb user=<user> password=<password> sslmode=require" \
    -c "
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_entity_category_deployment
    ON public.\"ENTITY\" USING btree (deployment_id, category);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_entity_ou_deployment
    ON public.\"ENTITY\" USING btree (deployment_id, ou_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_entity_identifier_lookup
    ON public.\"ENTITY_IDENTIFIER\" USING btree (name, value);
"
```

---

## Cleanup

Once seeding is verified, delete the Job and ConfigMap:

```bash
kubectl delete job seed-users
kubectl delete configmap seed-users-script
```
