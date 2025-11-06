-- ============================================================================
-- Autovacuum 診斷腳本：t_orders 表分析
-- ============================================================================
-- 用途：分析 t_orders 表的當前狀態和 autovacuum 歷史
-- 執行方式：psql -h <host> -U postgres -d postgres -f 01-diagnose-t_orders.sql
-- ============================================================================

\echo '============================================================================'
\echo '1. t_orders 表大小分析'
\echo '============================================================================'

SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) AS indexes_size,
    pg_total_relation_size(schemaname||'.'||tablename) AS total_bytes
FROM pg_tables
WHERE schemaname = 'public'
    AND tablename = 't_orders';

\echo ''
\echo '============================================================================'
\echo '2. t_orders Dead Tuples 分析'
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
    END AS dead_tuple_percent,
    last_vacuum,
    last_autovacuum,
    autovacuum_count,
    CASE
        WHEN last_autovacuum IS NOT NULL THEN
            EXTRACT(EPOCH FROM (NOW() - last_autovacuum))/3600
        ELSE NULL
    END AS hours_since_last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
    AND relname = 't_orders';

\echo ''
\echo '============================================================================'
\echo '3. t_orders 當前 Autovacuum 配置'
\echo '============================================================================'

SELECT
    c.relname AS table_name,
    COALESCE(t.reloptions::text, '使用全局默認值') AS table_specific_settings
FROM pg_class c
LEFT JOIN pg_tables t ON c.relname = t.tablename
WHERE c.relname = 't_orders'
    AND c.relkind = 'r';

\echo ''
\echo '============================================================================'
\echo '4. 全局 Autovacuum 參數（從 pg_settings）'
\echo '============================================================================'

SELECT
    name,
    setting,
    unit,
    short_desc
FROM pg_settings
WHERE name LIKE 'autovacuum%'
ORDER BY name;

\echo ''
\echo '============================================================================'
\echo '5. t_orders 表活動統計'
\echo '============================================================================'

SELECT
    schemaname,
    relname AS table_name,
    seq_scan AS sequential_scans,
    seq_tup_read AS rows_read_by_seq_scans,
    idx_scan AS index_scans,
    idx_tup_fetch AS rows_fetched_by_index,
    n_tup_ins AS rows_inserted,
    n_tup_upd AS rows_updated,
    n_tup_del AS rows_deleted,
    n_tup_hot_upd AS hot_updates
FROM pg_stat_user_tables
WHERE schemaname = 'public'
    AND relname = 't_orders';

\echo ''
\echo '============================================================================'
\echo '6. 檢查是否有正在運行的 Autovacuum'
\echo '============================================================================'

SELECT
    pid,
    usename,
    datname,
    state,
    query_start,
    EXTRACT(EPOCH FROM (NOW() - query_start))/60 AS running_minutes,
    query
FROM pg_stat_activity
WHERE query LIKE '%autovacuum%'
    AND query NOT LIKE '%pg_stat_activity%'
    AND pid != pg_backend_pid();

\echo ''
\echo '============================================================================'
\echo '7. t_orders 索引列表'
\echo '============================================================================'

SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(schemaname||'.'||indexname)) AS index_size
FROM pg_indexes
WHERE schemaname = 'public'
    AND tablename = 't_orders'
ORDER BY pg_relation_size(schemaname||'.'||indexname) DESC;

\echo ''
\echo '============================================================================'
\echo '診斷完成！'
\echo '============================================================================'
