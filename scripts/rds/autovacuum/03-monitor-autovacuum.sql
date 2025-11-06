-- ============================================================================
-- Autovacuum 監控腳本
-- ============================================================================
-- 用途：持續監控 autovacuum 活動和表健康狀態
-- 使用方式：psql -h <host> -U postgres -d postgres -f 03-monitor-autovacuum.sql
-- 建議：加入定時監控（每小時執行一次）
-- ============================================================================

\echo '============================================================================'
\echo 'Autovacuum 監控報告'
\echo '生成時間: ' `date '+%Y-%m-%d %H:%M:%S'`
\echo '============================================================================'

\echo ''
\echo '============================================================================'
\echo '1. 正在運行的 Autovacuum 進程'
\echo '============================================================================'

SELECT
    pid,
    usename,
    datname AS database,
    state,
    query_start,
    ROUND(EXTRACT(EPOCH FROM (NOW() - query_start))/60, 2) AS running_minutes,
    LEFT(query, 80) AS query_preview
FROM pg_stat_activity
WHERE query LIKE '%autovacuum%'
    AND query NOT LIKE '%pg_stat_activity%'
    AND pid != pg_backend_pid()
ORDER BY query_start;

\echo ''
\echo '如果無結果 = 當前無 autovacuum 運行'
\echo ''

\echo '============================================================================'
\echo '2. Top 10 需要 Autovacuum 的表（按 Dead Tuples 排序）'
\echo '============================================================================'

SELECT
    schemaname,
    relname AS table_name,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    CASE
        WHEN n_live_tup > 0 THEN
            ROUND(100.0 * n_dead_tup / n_live_tup, 2)
        ELSE 0
    END AS dead_pct,
    CASE
        WHEN n_dead_tup > n_live_tup * 0.1 THEN '🔴 需要 VACUUM'
        WHEN n_dead_tup > n_live_tup * 0.05 THEN '🟡 關注'
        ELSE '✅ 健康'
    END AS status,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) AS total_size,
    last_autovacuum,
    CASE
        WHEN last_autovacuum IS NOT NULL THEN
            ROUND(EXTRACT(EPOCH FROM (NOW() - last_autovacuum))/3600, 1)
        ELSE NULL
    END AS hours_since_last_vacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC
LIMIT 10;

\echo ''
\echo '============================================================================'
\echo '3. t_orders 詳細狀態'
\echo '============================================================================'

SELECT
    schemaname,
    relname AS table_name,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup, 0), 2) AS dead_pct,
    n_tup_ins AS inserts,
    n_tup_upd AS updates,
    n_tup_del AS deletes,
    last_vacuum,
    last_autovacuum,
    vacuum_count AS manual_vacuum_count,
    autovacuum_count,
    pg_size_pretty(pg_total_relation_size('public.t_orders')) AS total_size
FROM pg_stat_user_tables
WHERE schemaname = 'public'
    AND relname = 't_orders';

\echo ''
\echo '============================================================================'
\echo '4. t_orders Autovacuum 配置'
\echo '============================================================================'

SELECT
    c.relname AS table_name,
    CASE
        WHEN c.reloptions IS NULL THEN '使用全局默認值'
        ELSE array_to_string(c.reloptions, ', ')
    END AS autovacuum_settings
FROM pg_class c
WHERE c.relname = 't_orders'
    AND c.relnamespace = 'public'::regnamespace;

\echo ''
\echo '============================================================================'
\echo '5. 近期 Autovacuum 歷史（Top 10 表）'
\echo '============================================================================'

SELECT
    schemaname,
    relname AS table_name,
    last_autovacuum,
    autovacuum_count AS total_autovacuum_count,
    CASE
        WHEN last_autovacuum IS NOT NULL THEN
            ROUND(EXTRACT(EPOCH FROM (NOW() - last_autovacuum))/3600, 1)
        ELSE NULL
    END AS hours_since_last,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) AS table_size
FROM pg_stat_user_tables
WHERE last_autovacuum IS NOT NULL
ORDER BY last_autovacuum DESC
LIMIT 10;

\echo ''
\echo '============================================================================'
\echo '6. 系統級 Autovacuum 統計'
\echo '============================================================================'

WITH stats AS (
    SELECT
        COUNT(*) AS total_tables,
        COUNT(*) FILTER (WHERE last_autovacuum IS NOT NULL) AS tables_ever_vacuumed,
        COUNT(*) FILTER (WHERE n_dead_tup > n_live_tup * 0.1) AS tables_need_vacuum,
        SUM(autovacuum_count) AS total_autovacuum_runs,
        SUM(n_dead_tup) AS total_dead_tuples
    FROM pg_stat_user_tables
)
SELECT
    total_tables,
    tables_ever_vacuumed,
    tables_need_vacuum,
    total_autovacuum_runs,
    total_dead_tuples
FROM stats;

\echo ''
\echo '============================================================================'
\echo '7. 全局 Autovacuum 配置摘要'
\echo '============================================================================'

SELECT
    name,
    setting,
    unit,
    context
FROM pg_settings
WHERE name IN (
    'autovacuum',
    'autovacuum_max_workers',
    'autovacuum_naptime',
    'autovacuum_vacuum_cost_delay',
    'autovacuum_vacuum_cost_limit',
    'autovacuum_vacuum_scale_factor',
    'autovacuum_vacuum_threshold'
)
ORDER BY name;

\echo ''
\echo '============================================================================'
\echo '8. 建議操作'
\echo '============================================================================'

WITH recommendations AS (
    SELECT
        schemaname,
        relname,
        n_live_tup,
        n_dead_tup,
        ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup, 0), 2) AS dead_pct,
        pg_total_relation_size(schemaname||'.'||relname) AS size_bytes
    FROM pg_stat_user_tables
    WHERE n_dead_tup > 1000
)
SELECT
    schemaname,
    relname AS table_name,
    dead_pct AS dead_tuple_percent,
    pg_size_pretty(size_bytes) AS table_size,
    CASE
        WHEN dead_pct > 20 THEN '🔴 立即執行 VACUUM'
        WHEN dead_pct > 10 THEN '🟡 計劃執行 VACUUM'
        WHEN dead_pct > 5 THEN 'ℹ️  監控觀察'
        ELSE '✅ 狀態良好'
    END AS recommendation,
    'VACUUM (ANALYZE) ' || schemaname || '.' || relname || ';' AS vacuum_command
FROM recommendations
WHERE dead_pct > 5
ORDER BY dead_pct DESC
LIMIT 10;

\echo ''
\echo '============================================================================'
\echo '監控完成！'
\echo '============================================================================'
\echo ''
\echo '建議：'
\echo '  - 將此腳本加入 cron 定時執行（每小時一次）'
\echo '  - 關注 dead_pct > 10% 的表'
\echo '  - t_orders 的 dead_pct 應保持在 5% 以下'
\echo ''
