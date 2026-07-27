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
-- (commit b583fb0f0, 2026-07-22). This procedure is a faithful copy of that shipped logic
-- (backend/dbscripts/runtime_persistent/postgres-cleanup.sql) so long-running tests on the
-- alpha keep SSO_SESSION* bounded.
-- REMOVE this procedure (and the perf_cleanup_expired_sso_sessions call in
-- db-cleanup-loop.sh) once the harness moves to a Thunder release whose shipped proc
-- already purges SSO sessions.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE perf_cleanup_expired_sso_sessions(p_batch_size INT DEFAULT 1000)
LANGUAGE plpgsql
AS $$
DECLARE
    v_now     TIMESTAMP := NOW() AT TIME ZONE 'UTC';
    v_deleted INT;
BEGIN
    IF p_batch_size IS NULL OR p_batch_size <= 0 THEN
        p_batch_size := 1000;
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
    END LOOP;
END;
$$;

