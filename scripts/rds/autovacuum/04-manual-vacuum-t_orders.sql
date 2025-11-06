-- ============================================================================
-- 手動 VACUUM 腳本：t_orders 表
-- ============================================================================
-- 用途：立即對 t_orders 執行完整的 VACUUM 操作
-- 使用時機：
--   1. 緊急情況下 dead tuples 過多（>10%）
--   2. 定期維護（建議凌晨 2-4 點執行）
--   3. 重大更新/刪除操作後
--
-- 執行時間：預計 1-2 小時（取決於表大小）
-- 注意：VACUUM 期間表仍可正常讀寫，但會消耗大量 I/O
-- ============================================================================

\echo '============================================================================'
\echo '手動 VACUUM 腳本 - t_orders'
\echo '============================================================================'
\echo ''

\echo '執行前檢查...'
\echo ''

\echo '============================================================================'
\echo '1. 當前表狀態'
\echo '============================================================================'

SELECT
    schemaname,
    relname AS table_name,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup, 0), 2) AS dead_pct,
    pg_size_pretty(pg_total_relation_size('public.t_orders')) AS total_size,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
    AND relname = 't_orders';

\echo ''
\echo '============================================================================'
\echo '2. 檢查是否有其他 VACUUM 正在運行'
\echo '============================================================================'

SELECT
    pid,
    query_start,
    ROUND(EXTRACT(EPOCH FROM (NOW() - query_start))/60, 2) AS running_minutes,
    query
FROM pg_stat_activity
WHERE query LIKE '%VACUUM%'
    AND query NOT LIKE '%pg_stat_activity%'
    AND pid != pg_backend_pid();

\echo ''
\echo '如果有其他 VACUUM 正在運行，建議等待其完成'
\echo ''

\echo '============================================================================'
\echo '3. 當前系統負載'
\echo '============================================================================'

SELECT
    COUNT(*) AS active_connections,
    COUNT(*) FILTER (WHERE state = 'active') AS active_queries,
    COUNT(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting_queries
FROM pg_stat_activity
WHERE datname = current_database()
    AND pid != pg_backend_pid();

\echo ''
\prompt '確認要執行 VACUUM 嗎？(輸入 YES 繼續)' confirmation

\if :'confirmation' = 'YES'

    \echo ''
    \echo '============================================================================'
    \echo '開始執行 VACUUM...'
    \echo '============================================================================'
    \echo ''
    \echo '選項說明：'
    \echo '  VERBOSE  - 顯示詳細進度信息'
    \echo '  ANALYZE  - 同時更新統計信息'
    \echo ''
    \echo '預計執行時間：1-2 小時'
    \echo '請勿中斷此操作'
    \echo ''

    \timing on

    -- 執行 VACUUM
    VACUUM (VERBOSE, ANALYZE) public.t_orders;

    \timing off

    \echo ''
    \echo '✅ VACUUM 完成！'
    \echo ''

    \echo '============================================================================'
    \echo '執行後檢查'
    \echo '============================================================================'

    SELECT
        schemaname,
        relname AS table_name,
        n_live_tup AS live_tuples,
        n_dead_tup AS dead_tuples,
        ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup, 0), 2) AS dead_pct,
        pg_size_pretty(pg_total_relation_size('public.t_orders')) AS total_size,
        last_vacuum,
        vacuum_count
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
        AND relname = 't_orders';

    \echo ''
    \echo '============================================================================'
    \echo '預期結果'
    \echo '============================================================================'
    \echo ''
    \echo '  ✅ dead_tuples 應該接近 0'
    \echo '  ✅ dead_pct 應該 < 1%'
    \echo '  ✅ last_vacuum 應該是當前時間'
    \echo '  ✅ vacuum_count 應該增加 1'
    \echo ''
    \echo '如果表大小減少，說明成功回收了空間'
    \echo ''

\else
    \echo ''
    \echo '❌ 操作已取消'
    \echo ''
\endif

\echo '============================================================================'
\echo '完成！'
\echo '============================================================================'
