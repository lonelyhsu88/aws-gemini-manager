-- ============================================================================
-- Autovacuum 優化腳本（手動排程版）：t_orders 表
-- ============================================================================
-- 用途：禁用 t_orders 的自動 VACUUM，改為手動控制
-- 策略：在低峰時段（凌晨）手動執行 VACUUM
-- 適用場景：需要完全控制 VACUUM 執行時間，避免業務高峰期影響
-- ============================================================================

\echo '============================================================================'
\echo 'Autovacuum 優化腳本（手動排程版）- t_orders'
\echo '============================================================================'
\echo ''
\echo '⚠️  警告：此腳本將禁用 t_orders 的自動 VACUUM'
\echo ''
\echo '使用前必須確認：'
\echo '  1. 您有能力設置定時任務（cron/pg_cron）在凌晨執行 VACUUM'
\echo '  2. 您理解禁用 autovacuum 的風險（表膨脹、性能下降）'
\echo '  3. 您會定期監控表的 dead tuples'
\echo ''
\echo '如果不確定，請使用「溫和版」優化腳本'
\echo ''

\prompt '確認要繼續嗎？(輸入 YES 繼續)' confirmation

\if :'confirmation' = 'YES'

    \echo ''
    \echo '============================================================================'
    \echo '步驟 1: 禁用 t_orders 的 Autovacuum'
    \echo '============================================================================'

    BEGIN;

    ALTER TABLE public.t_orders SET (
        autovacuum_enabled = false
    );

    \echo '✅ Autovacuum 已禁用'

    COMMIT;

    \echo ''
    \echo '============================================================================'
    \echo '步驟 2: 驗證配置'
    \echo '============================================================================'

    SELECT
        'public.t_orders' AS table_name,
        reloptions AS settings
    FROM pg_class
    WHERE relname = 't_orders'
        AND relnamespace = 'public'::regnamespace;

    \echo ''
    \echo '============================================================================'
    \echo '步驟 3: 手動 VACUUM 命令（用於定時任務）'
    \echo '============================================================================'
    \echo ''
    \echo '請將以下命令加入您的定時任務（建議凌晨 2:00-4:00 執行）：'
    \echo ''
    \echo '方式 1: 使用 psql'
    \echo '-------'
    \echo 'psql -h bingo-prd.xxx.rds.amazonaws.com -U postgres -d postgres -c "VACUUM (ANALYZE, VERBOSE) public.t_orders;"'
    \echo ''
    \echo '方式 2: 使用 pg_cron（如已安裝）'
    \echo '-------'
    \echo "SELECT cron.schedule('vacuum-t_orders', '0 2 * * *', $$ VACUUM (ANALYZE, VERBOSE) public.t_orders; $$);"
    \echo ''
    \echo '方式 3: 使用外部 cron（推薦）'
    \echo '-------'
    \echo '# 編輯 crontab'
    \echo '# crontab -e'
    \echo '# 添加以下行（每天凌晨 2:00 執行）'
    \echo '0 2 * * * PGPASSWORD="your_password" psql -h bingo-prd.xxx.rds.amazonaws.com -U postgres -d postgres -c "VACUUM (ANALYZE, VERBOSE) public.t_orders;" >> /var/log/vacuum-t_orders.log 2>&1'
    \echo ''

    \echo '============================================================================'
    \echo '步驟 4: 立即執行一次完整 VACUUM（可選）'
    \echo '============================================================================'
    \echo ''
    \echo '如果您想立即清理當前累積的 dead tuples，可以執行：'
    \echo ''

    \prompt '是否立即執行 VACUUM？(輸入 YES 執行，此操作可能需要 1-2 小時)' do_vacuum

    \if :'do_vacuum' = 'YES'
        \echo ''
        \echo '開始執行 VACUUM...'
        \echo ''

        \timing on
        VACUUM (ANALYZE, VERBOSE) public.t_orders;
        \timing off

        \echo ''
        \echo '✅ VACUUM 完成'
    \else
        \echo ''
        \echo 'ℹ️  已跳過立即 VACUUM'
    \endif

    \echo ''
    \echo '============================================================================'
    \echo '優化完成！'
    \echo '============================================================================'
    \echo ''
    \echo '重要提醒：'
    \echo '  ⚠️  Autovacuum 已禁用，您必須：'
    \echo '     1. 設置定時任務定期執行 VACUUM'
    \echo '     2. 監控表的 dead tuples 百分比'
    \echo '     3. 根據業務變化調整執行頻率'
    \echo ''
    \echo '監控命令：'
    \echo '  psql -f 03-monitor-autovacuum.sql'
    \echo ''
    \echo '恢復自動 VACUUM（如需要）：'
    \echo '  ALTER TABLE public.t_orders RESET (autovacuum_enabled);'
    \echo ''

\else
    \echo ''
    \echo '❌ 操作已取消'
    \echo ''
\endif
