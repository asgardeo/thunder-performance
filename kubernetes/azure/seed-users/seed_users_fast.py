#!/usr/bin/env python3
"""
Prerequisites:
  pip install psycopg2-binary

Usage:
  # Seed 50M users (default 8 workers)
  python seed_users_fast.py \
    --dsn "host=your-host.postgres.database.azure.com dbname=userdb user=admin password=xxx sslmode=require" \
    --num-users 50000000

  # Same command resumes automatically if interrupted — no manual offset needed

  # Override worker count for a smaller DB instance
  python seed_users_fast.py --dsn "..." --num-users 50000000 --workers 4

  # Delete all seeded users
  python seed_users_fast.py --dsn "..." --delete
"""

import argparse
import io
import uuid
import time
from datetime import datetime, timezone
from multiprocessing import Pool

# ---------------------------------------------------------------------------
# Constants matching seed_users.sql
# ---------------------------------------------------------------------------
DEPLOYMENT_ID = "default-deployment"
USER_TYPE = "customer"
CUSTOMER_SCHEMA_DEF = {
    "username": {"type": "string", "required": True},
    "firstName": {"type": "string", "required": False},
    "lastName": {"type": "string", "required": False},
    "email": {"type": "string", "required": False},
    "country": {"type": "string", "required": False},
    "mobile": {"type": "string", "required": False},
    "password": {"type": "string", "required": True, "credential": True},
}
CREDENTIALS = (
    '{"password":[{"storageAlgo":"SHA256",'
    '"storageAlgoParams":{"Salt":"10d6246b27db210d462bbb0115a3a1e9"},'
    '"value":"ea93463eb1ef1351b914b527128093058877c5cf5b0c8b4c60b1e72b7d214e31"}]}'
)

# Rows per COPY command. 100K keeps memory ~50MB per worker while
# still amortising the per-COPY overhead.
COPY_BATCH = 100_000

# Pre-built constant suffix for ENTITY rows (everything after the username JSON).
# Avoids re-embedding the ~170-char CREDENTIALS string into a new Python string
# for every row.
_ENTITY_SUFFIX = f"\t{{}}\t{CREDENTIALS}\t{{}}\t".encode()


# ---------------------------------------------------------------------------
# Config DSN builder
# ---------------------------------------------------------------------------
def build_config_dsn(dsn, config_db_host=None, config_db_user=None, config_db_password=None):
    """Derive the configdb DSN from the userdb DSN, overriding host/user/password as needed."""
    import re
    config_dsn = dsn.replace("dbname=userdb", "dbname=configdb")
    if config_db_host:
        config_dsn = re.sub(r'host=\S+', f'host={config_db_host}', config_dsn)
    if config_db_user:
        config_dsn = re.sub(r'user=\S+', f'user={config_db_user}', config_dsn)
    if config_db_password:
        config_dsn = re.sub(r'password=\S+', f'password={config_db_password}', config_dsn)
    return config_dsn


# ---------------------------------------------------------------------------
# Worker
# ---------------------------------------------------------------------------
def seed_chunk(args):
    """Each worker seeds a contiguous range [chunk_start, chunk_end]."""
    import psycopg2  # imported inside worker for multiprocessing pickling

    dsn, ou_id, chunk_start, chunk_end, worker_id = args
    conn = psycopg2.connect(dsn)
    cur = conn.cursor()

    # Per-session tuning — safe, session-scoped only
    cur.execute("SET synchronous_commit = off")
    cur.execute("SET work_mem = '256MB'")

    now_bytes = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f+00").encode()
    prefix = f"\t{DEPLOYMENT_ID}\tuser\t{USER_TYPE}\tACTIVE\t{ou_id}\t".encode()
    ident_mid = f"\tusername\t".encode()
    ident_tail = f"\tattribute\t{DEPLOYMENT_ID}\t".encode()
    nl = b"\n"

    total = chunk_end - chunk_start + 1
    done = 0

    pos = chunk_start
    while pos <= chunk_end:
        batch_end = min(pos + COPY_BATCH - 1, chunk_end)

        entity_buf = io.BytesIO()
        ident_buf = io.BytesIO()

        for i in range(pos, batch_end + 1):
            uid = uuid.uuid4().bytes.hex()
            # Format as canonical UUID: 8-4-4-4-12
            uid_b = f"{uid[:8]}-{uid[8:12]}-{uid[12:16]}-{uid[16:20]}-{uid[20:]}".encode()
            username = f"testUser_{i}".encode()
            i_bytes = str(i).encode()

            # ENTITY row
            entity_buf.write(uid_b)
            entity_buf.write(prefix)
            entity_buf.write(b'{"username":"')
            entity_buf.write(username)
            entity_buf.write(b'","firstName":"Test","lastName":"User')
            entity_buf.write(i_bytes)
            entity_buf.write(b'","email":"testUser_')
            entity_buf.write(i_bytes)
            entity_buf.write(b'@test.com","country":"US","mobile":"+1000')
            entity_buf.write(str(i).zfill(7).encode())
            entity_buf.write(b'"}')
            entity_buf.write(_ENTITY_SUFFIX)
            entity_buf.write(now_bytes)
            entity_buf.write(b"\t")
            entity_buf.write(now_bytes)
            entity_buf.write(nl)

            # ENTITY_IDENTIFIER row
            ident_buf.write(uid_b)
            ident_buf.write(ident_mid)
            ident_buf.write(username)
            ident_buf.write(ident_tail)
            ident_buf.write(now_bytes)
            ident_buf.write(nl)

        # COPY ENTITY
        entity_buf.seek(0)
        cur.copy_expert(
            'COPY "ENTITY" '
            "(ID, DEPLOYMENT_ID, CATEGORY, TYPE, STATE, OU_ID, "
            "ATTRIBUTES, SYSTEM_ATTRIBUTES, CREDENTIALS, SYSTEM_CREDENTIALS, "
            "CREATED_AT, UPDATED_AT) FROM STDIN",
            entity_buf,
        )
        del entity_buf  # free before building ident COPY

        # COPY ENTITY_IDENTIFIER
        ident_buf.seek(0)
        cur.copy_expert(
            'COPY "ENTITY_IDENTIFIER" '
            "(ENTITY_ID, NAME, VALUE, SOURCE, DEPLOYMENT_ID, CREATED_AT) "
            "FROM STDIN",
            ident_buf,
        )
        del ident_buf

        conn.commit()

        done += batch_end - pos + 1
        pos = batch_end + 1
        elapsed_pct = done * 100 // total
        print(f"  [Worker {worker_id}] {done:,}/{total:,} ({elapsed_pct}%)", flush=True)

    cur.close()
    conn.close()
    return total


# ---------------------------------------------------------------------------
# Entity type setup (configdb)
# ---------------------------------------------------------------------------
def ensure_entity_type(config_dsn, ou_id):
    """Ensure the customer entity type exists in configdb with the expected schema.

    Idempotent: skips if already correct, updates if schema differs, creates if missing.
    """
    import json
    import psycopg2

    conn = psycopg2.connect(config_dsn)
    conn.autocommit = True
    cur = conn.cursor()

    expected_schema = json.dumps(CUSTOMER_SCHEMA_DEF, sort_keys=True)

    cur.execute(
        """SELECT id, schema_def FROM "ENTITY_TYPES"
           WHERE deployment_id = %s AND category = 'user' AND name = %s AND ou_id = %s""",
        (DEPLOYMENT_ID, USER_TYPE, ou_id),
    )
    row = cur.fetchone()

    if row:
        existing_schema = json.dumps(row[1], sort_keys=True)
        if existing_schema == expected_schema:
            print(f"  Entity type already up to date (id={row[0]})")
        else:
            cur.execute(
                """UPDATE "ENTITY_TYPES" SET schema_def = %s, updated_at = now()
                   WHERE id = %s""",
                (expected_schema, row[0]),
            )
            print(f"  Updated entity type schema (id={row[0]})")
    else:
        type_id = str(uuid.uuid4())
        cur.execute(
            """INSERT INTO "ENTITY_TYPES"
               (deployment_id, id, category, name, ou_id, allow_self_registration, schema_def)
               VALUES (%s, %s, 'user', %s, %s, false, %s)""",
            (DEPLOYMENT_ID, type_id, USER_TYPE, ou_id, expected_schema),
        )
        print(f"  Created entity type (id={type_id})")

    cur.close()
    conn.close()


# ---------------------------------------------------------------------------
# Index / constraint helpers
# ---------------------------------------------------------------------------
PREPARE_STMTS = [
    'ALTER TABLE "ENTITY" SET (autovacuum_enabled = false)',
    'ALTER TABLE "ENTITY_IDENTIFIER" SET (autovacuum_enabled = false)',
    'ALTER TABLE "ENTITY" DISABLE TRIGGER USER',
    'ALTER TABLE "ENTITY_IDENTIFIER" DISABLE TRIGGER USER',
]

FINALIZE_STMTS = [
    'ALTER TABLE "ENTITY" ENABLE TRIGGER USER',
    'ALTER TABLE "ENTITY_IDENTIFIER" ENABLE TRIGGER USER',
    'ALTER TABLE "ENTITY" SET (autovacuum_enabled = true)',
    'ALTER TABLE "ENTITY_IDENTIFIER" SET (autovacuum_enabled = true)',
    'ANALYZE "ENTITY"',
    'ANALYZE "ENTITY_IDENTIFIER"',
]


def get_indexes(conn, table_name):
    """Return non-constraint index definitions for a table (skips PK, unique, FK)."""
    cur = conn.cursor()
    cur.execute(
        """
        SELECT i.indexname, i.indexdef
        FROM pg_indexes i
        JOIN pg_class c ON c.relname = i.indexname
        WHERE i.tablename = %s
          AND NOT EXISTS (
            SELECT 1 FROM pg_constraint con
            WHERE con.conindid = c.oid
          )
        """,
        (table_name,),
    )
    rows = cur.fetchall()
    cur.close()
    return rows


INDEX_STORE = "/tmp/_thunder_seed_indexes.txt"


def prepare(dsn):
    """Drop secondary indexes and disable triggers/autovacuum for bulk loading.

    Idempotent: saves index definitions on first call, preserves them on subsequent calls
    if indexes are already gone (crash recovery).
    """
    import psycopg2

    conn = psycopg2.connect(dsn)
    conn.autocommit = True
    cur = conn.cursor()

    indexes = []
    for table in ("ENTITY", "ENTITY_IDENTIFIER"):
        indexes.extend(get_indexes(conn, table))

    if indexes:
        print(f"  Dropping {len(indexes)} index(es) for faster loading:")
        for name, defn in indexes:
            print(f"    DROP INDEX \"{name}\"")
            cur.execute(f'DROP INDEX IF EXISTS "{name}"')
        # Save definitions so finalize can recreate them
        with open(INDEX_STORE, "w") as f:
            for _, defn in indexes:
                f.write(defn + ";\n")
    else:
        print("  No secondary indexes to drop (already removed or none exist)")

    for stmt in PREPARE_STMTS:
        cur.execute(stmt)
    print("  Triggers and autovacuum disabled.")

    cur.close()
    conn.close()


def finalize(dsn):
    """Re-enable triggers/autovacuum and recreate any missing indexes.

    Idempotent: skips indexes that already exist, re-enabling triggers is a no-op
    if already enabled.
    """
    import psycopg2

    conn = psycopg2.connect(dsn)
    conn.autocommit = True
    cur = conn.cursor()

    for stmt in FINALIZE_STMTS:
        cur.execute(stmt)
    print("  Triggers and autovacuum re-enabled.")

    # Recreate any missing indexes from saved definitions
    try:
        with open(INDEX_STORE) as f:
            index_stmts = [l.strip().rstrip(";") for l in f if l.strip()]
    except FileNotFoundError:
        index_stmts = []

    if index_stmts:
        # Check which indexes already exist
        existing = set()
        for table in ("ENTITY", "ENTITY_IDENTIFIER"):
            for name, _ in get_indexes(conn, table):
                existing.add(name)

        missing = [s for s in index_stmts if not any(name in s for name in existing)]
        if missing:
            print(f"  Recreating {len(missing)} index(es)...")
            for stmt in missing:
                print(f"    {stmt[:120]}...")
                cur.execute(stmt)
            print("  All indexes recreated.")
        else:
            print("  All indexes already present.")
    else:
        print("  No saved index definitions — skipping index recreation.")

    cur.close()
    conn.close()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Bulk seed Thunder test users via parallel COPY"
    )
    parser.add_argument("--dsn", required=True, help="PostgreSQL connection string")
    parser.add_argument("--num-users", type=int, default=10)
    parser.add_argument("--workers", type=int, default=8, help="Parallel DB connections")
    parser.add_argument("--config-db-host", default=None,
                        help="Hostname for configdb if on a separate server (defaults to same host as --dsn)")
    parser.add_argument("--config-db-user", default=None,
                        help="Username for configdb (defaults to same user as --dsn)")
    parser.add_argument("--config-db-password", default=None,
                        help="Password for configdb (defaults to same password as --dsn)")
    parser.add_argument("--delete", action="store_true",
                        help="Delete all seeded customer users instead of creating them")
    args = parser.parse_args()

    import psycopg2

    if args.delete:
        conn = psycopg2.connect(args.dsn)
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(
            """DELETE FROM "ENTITY" WHERE DEPLOYMENT_ID = %s AND CATEGORY = 'user' AND TYPE = %s""",
            (DEPLOYMENT_ID, USER_TYPE),
        )
        print(f"Deleted {cur.rowcount:,} users (ENTITY_IDENTIFIER cleaned up via CASCADE)")
        cur.close()
        conn.close()
        return

    # Build configdb DSN early — OU_ID and entity type both live in configdb
    config_dsn = build_config_dsn(
        args.dsn,
        config_db_host=args.config_db_host,
        config_db_user=args.config_db_user,
        config_db_password=args.config_db_password,
    )

    # Look up OU_ID and find existing users from userdb
    print("Connecting to userdb to resolve OU_ID...")
    conn = psycopg2.connect(args.dsn)
    cur = conn.cursor()

    cur.execute("""SELECT ou_id FROM "ORGANIZATION_UNIT" WHERE handle = 'default'""")
    row = cur.fetchone()
    if not row:
        print("ERROR: No ORGANIZATION_UNIT found with handle='default' in userdb")
        cur.close()
        conn.close()
        return
    ou_id = str(row[0])
    print(f"Resolved OU_ID: {ou_id}")

    # Find the highest existing testUser_N in userdb to auto-resume
    cur.execute(
        r"""SELECT MAX(CAST(SUBSTRING(ATTRIBUTES->>'username' FROM 'testUser_(\d+)') AS INTEGER))
           FROM "ENTITY"
           WHERE DEPLOYMENT_ID = %s AND CATEGORY = 'user' AND TYPE = %s""",
        (DEPLOYMENT_ID, USER_TYPE),
    )
    max_existing = cur.fetchone()[0] or 0
    cur.close()
    conn.close()

    start_offset = max_existing + 1
    if start_offset > args.num_users:
        print(f"Already have {max_existing:,} users (>= {args.num_users:,} requested). Nothing to do.")
        return

    total = args.num_users - start_offset + 1
    if max_existing > 0:
        print(f"Found {max_existing:,} existing users, resuming from testUser_{start_offset}")

    print(f"Seeding {total:,} users (testUser_{start_offset}..testUser_{args.num_users})")
    print(f"Workers: {args.workers}  |  Batch size: {COPY_BATCH:,}")

    # --- Phase 0: Entity type setup (configdb) ---
    print("\nEnsuring customer entity type in configdb...")
    ensure_entity_type(config_dsn, ou_id)

    # --- Phase 1: Prepare ---
    print("\nPreparing tables for bulk load...")
    prepare(args.dsn)

    # --- Phase 2: Parallel COPY ---
    chunk_size = total // args.workers
    chunks = []
    for w in range(args.workers):
        c_start = start_offset + w * chunk_size
        c_end = (
            c_start + chunk_size - 1
            if w < args.workers - 1
            else args.num_users  # last worker picks up remainder
        )
        chunks.append((args.dsn, ou_id, c_start, c_end, w))

    print(f"\nStarting {args.workers} parallel workers...\n")
    t0 = time.time()

    with Pool(processes=args.workers) as pool:
        results = pool.map(seed_chunk, chunks)

    elapsed = time.time() - t0
    rows = sum(results)
    rate = rows / elapsed if elapsed > 0 else 0
    print(f"\nLoaded {rows:,} users in {elapsed:.1f}s ({rate:,.0f} rows/sec)")

    # --- Phase 3: Finalize ---
    print("\nFinalizing tables...")
    t1 = time.time()
    finalize(args.dsn)
    print(f"Finalize took {time.time() - t1:.1f}s")

    print("\nDone.")


if __name__ == "__main__":
    main()
