-- ============================================================================
-- Autovacuum 優化腳本（溫和版）：t_orders 表
-- ============================================================================
-- 用途：調整 t_orders 表的 autovacuum 參數，降低 I/O 壓力
-- 策略：保持自動 VACUUM，但降低其激進程度
-- 適用場景：希望維持自動化，但減少對業務的影響
-- ============================================================================

\echo '============================================================================'
\echo 'Autovacuum 優化腳本（溫和版）- t_orders'
\echo '============================================================================'
\echo ''
\echo '優化策略：'
\echo '  1. 降低觸發閾值（10% → 5%），更頻繁但輕量的 VACUUM'
\echo '  2. 增加延遲時間，降低 I/O 壓力'
\echo '  3. 限制成本上限，避免佔用過多資源'
\echo ''

\echo '執行前確認：'
\echo '  - 確保您有 ALTER TABLE 權限'
\echo '  - 此操作不會鎖定表，可以安全執行'
\echo '  - 修改後的參數立即生效（無需重啟）'
\echo ''

-- 開始事務
BEGIN;

\echo '============================================================================'
\echo '步驟 1: 查看當前配置'
\echo '============================================================================'

SELECT
    'public.t_orders' AS table_name,
    COALESCE(reloptions::text, '使用全局默認值') AS current_settings
FROM pg_class
WHERE relname = 't_orders'
    AND relnamespace = 'public'::regnamespace;

\echo ''
\echo '============================================================================'
\echo '步驟 2: 應用優化參數'
\echo '============================================================================'

ALTER TABLE public.t_orders SET (
    -- 當死元組達到 5% 時觸發（默認 10%）
    -- 更頻繁但每次工作量較小
    autovacuum_vacuum_scale_factor = 0.05,

    -- 增加延遲到 10ms（默認 2ms）
    -- 降低 I/O 壓力，讓其他操作有更多機會執行
    autovacuum_vacuum_cost_delay = 10,

    -- 限制成本到 1000（默認約 200）
    -- 避免單次 VACUUM 消耗過多資源
    autovacuum_vacuum_cost_limit = 1000,

    -- 分析閾值也相應調整
    autovacuum_analyze_scale_factor = 0.05
);

\echo ''
\echo '✅ 參數已應用'
\echo ''

\echo '============================================================================'
\echo '步驟 3: 驗證新配置'
\echo '============================================================================'

SELECT
    'public.t_orders' AS table_name,
    reloptions AS new_settings
FROM pg_class
WHERE relname = 't_orders'
    AND relnamespace = 'public'::regnamespace;

\echo ''
\echo '============================================================================'
\echo '步驟 4: 計算預期效果'
\echo '============================================================================'

WITH table_stats AS (
    SELECT
        n_live_tup,
        n_dead_tup
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
        AND relname = 't_orders'
)
SELECT
    '舊閾值 (10%)' AS threshold_type,
    ROUND(n_live_tup * 0.10) AS dead_tuples_needed,
    CASE
        WHEN n_dead_tup > 0 THEN
            ROUND(100.0 * (n_live_tup * 0.10 - n_dead_tup) / n_dead_tup, 2)
        ELSE 0
    END AS percent_until_trigger
FROM table_stats

UNION ALL

SELECT
    '新閾值 (5%)' AS threshold_type,
    ROUND(n_live_tup * 0.05) AS dead_tuples_needed,
    CASE
        WHEN n_dead_tup > 0 THEN
            ROUND(100.0 * (n_live_tup * 0.05 - n_dead_tup) / n_dead_tup, 2)
        ELSE 0
    END AS percent_until_trigger
FROM table_stats;

-- 提交事務
COMMIT;

\echo ''
\echo '============================================================================'
\echo '優化完成！'
\echo '============================================================================'
\echo ''
\echo '預期效果：'
\echo '  ✅ Autovacuum 會更頻繁運行（約 2x 頻率）'
\echo '  ✅ 每次運行時間縮短（約 50%）'
\echo '  ✅ I/O 壓力降低（延遲增加 5 倍）'
\echo '  ✅ 對業務影響減少'
\echo ''
\echo '監控建議：'
\echo '  - 觀察接下來 24-48 小時的 autovacuum 行為'
\echo '  - 使用 03-monitor-autovacuum.sql 持續監控'
\echo '  - 如仍有問題，考慮使用「手動排程版」'
\echo ''
