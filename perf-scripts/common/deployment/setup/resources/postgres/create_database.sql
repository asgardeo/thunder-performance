-- Copyright (c) 2025, WSO2 LLC. (https://www.wso2.com).
--
-- WSO2 LLC. licenses this file to you under the Apache License,
-- Version 2.0 (the "License"); you may not use this file except
-- in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing,
-- software distributed under the License is distributed on an
-- "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
-- KIND, either express or implied. See the License for the
-- specific language governing permissions and limitations
-- under the License.

create database "configdb";
create database "runtime_transient";
create database "entitydb";
create database "runtime_persistent";

\c configdb
\i /home/ubuntu/thunder/dbscripts/configdb/postgres.sql
\c runtime_transient
\i /home/ubuntu/thunder/dbscripts/runtime_transient/postgres.sql
\i /home/ubuntu/thunder/dbscripts/runtime_transient/postgres-cleanup.sql
\c entitydb
\i /home/ubuntu/thunder/dbscripts/entitydb/postgres.sql
\c runtime_persistent
\i /home/ubuntu/thunder/dbscripts/runtime_persistent/postgres.sql
\i /home/ubuntu/thunder/dbscripts/runtime_persistent/postgres-cleanup.sql

-- ----------------------------------------------------------------------------
-- TEMPORARY: replicate Thunder's SSO-session cleanup on the perf side.
-- The v1.0.0-alpha pack's shipped cleanup_expired_runtime_persistent_data() purges only
-- REVOKED_TOKEN; the SSO_SESSION purge was added to Thunder AFTER the alpha was cut
-- (commit b583fb0f0, 2026-07-22). This procedure copies that shipped logic
-- (backend/dbscripts/runtime_persistent/postgres-cleanup.sql) so long-running tests on the
-- alpha keep SSO_SESSION* bounded. The delete logic is byte-identical to the shipped
-- version; the only addition is the inter-batch pause described below.
-- REMOVE this procedure (and the perf_cleanup_expired_sso_sessions call in
-- db-cleanup-loop.sh) once the harness moves to a Thunder release whose shipped proc
-- already purges SSO sessions.
-- ----------------------------------------------------------------------------
-- Drop the older single-argument signature first. CREATE OR REPLACE keys on the argument
-- list, so adding p_batch_pause_seconds ADDS an overload rather than replacing — and
-- db-cleanup-loop.sh's zero-argument "CALL perf_cleanup_expired_sso_sessions();" would then
-- fail as ambiguous. That failure is non-fatal in the loop (logged as WARN), so it would
-- silently stop purging SSO sessions for the rest of the run.
DROP PROCEDURE IF EXISTS perf_cleanup_expired_sso_sessions(INT);

-- p_batch_pause_seconds throttles the loop: each batch churns up to p_batch_size dead
-- tuples across three tables, and at long-run volumes (~3.6M sessions per 6h cycle) an
-- unthrottled loop outruns autovacuum, so dead tuples accumulate faster than they are
-- reclaimed. Pausing between batches spreads the same work over a wider window and lets
-- autovacuum keep pace. Cycles cannot overlap regardless of how long this takes —
-- db-cleanup-loop.sh sleeps AFTER a cycle completes, not on a fixed schedule.
CREATE OR REPLACE PROCEDURE perf_cleanup_expired_sso_sessions(
    p_batch_size          INT              DEFAULT 1000,
    p_batch_pause_seconds DOUBLE PRECISION DEFAULT 1
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_now     TIMESTAMP := NOW() AT TIME ZONE 'UTC';
    v_deleted INT;
BEGIN
    IF p_batch_size IS NULL OR p_batch_size <= 0 THEN
        p_batch_size := 1000;
    END IF;

    IF p_batch_pause_seconds IS NULL OR p_batch_pause_seconds < 0 THEN
        p_batch_pause_seconds := 1;
    END IF;

    LOOP
        WITH victims AS (
            SELECT SESSION_ID, DEPLOYMENT_ID
            FROM "SSO_SESSION"
            WHERE ABSOLUTE_EXPIRES_AT <= v_now
            ORDER BY ABSOLUTE_EXPIRES_AT
            LIMIT p_batch_size
        ),
        del_ctx AS (
            DELETE FROM "SSO_SESSION_CONTEXT" c
            USING victims v
            WHERE c.SESSION_ID = v.SESSION_ID AND c.DEPLOYMENT_ID = v.DEPLOYMENT_ID
        ),
        del_part AS (
            DELETE FROM "SSO_SESSION_PARTICIPANT" p
            USING victims v
            WHERE p.SESSION_ID = v.SESSION_ID AND p.DEPLOYMENT_ID = v.DEPLOYMENT_ID
        ),
        del_sess AS (
            DELETE FROM "SSO_SESSION" s
            USING victims v
            WHERE s.SESSION_ID = v.SESSION_ID AND s.DEPLOYMENT_ID = v.DEPLOYMENT_ID
            RETURNING 1
        )
        SELECT COUNT(*) INTO v_deleted FROM del_sess;
        COMMIT;
        EXIT WHEN v_deleted = 0;
        -- Yield after a productive batch (never after the terminating empty one) so
        -- autovacuum gets a window on the three SSO tables before the next batch.
        PERFORM pg_sleep(p_batch_pause_seconds);
    END LOOP;
END;
$$;

