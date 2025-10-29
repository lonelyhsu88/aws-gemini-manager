#!/usr/bin/env python3
"""
PostgreSQL 連接和查詢分析工具
直接連接數據庫查詢活動連接、慢查詢和來源 IP
"""

import sys
import json
import argparse
from datetime import datetime

try:
    import psycopg2
    from psycopg2 import sql
except ImportError:
    print("❌ 錯誤：需要安裝 psycopg2")
    print("請執行：pip3 install psycopg2-binary")
    sys.exit(1)

def get_active_connections(cursor):
    """查詢當前活動連接和來源 IP"""

    query = """
    SELECT
        pid,
        usename,
        application_name,
        client_addr,
        client_hostname,
        backend_start,
        state,
        state_change,
        query_start,
        NOW() - query_start as query_duration,
        wait_event_type,
        wait_event,
        LEFT(query, 150) as query_preview
    FROM pg_stat_activity
    WHERE pid != pg_backend_pid()  -- 排除當前連接
        AND state != 'idle'
    ORDER BY query_start DESC
    LIMIT 50;
    """

    cursor.execute(query)
    results = cursor.fetchall()

    print("\n" + "="*100)
    print("📡 當前活動連接 (Active Connections)")
    print("="*100)

    if not results:
        print("✅ 目前沒有活動連接")
        return

    for row in results:
        pid, user, app, ip, hostname, backend_start, state, state_change, query_start, duration, wait_type, wait_event, query = row

        print(f"\n{'─'*100}")
        print(f"PID: {pid} | User: {user} | App: {app or 'N/A'}")
        print(f"來源 IP: {ip or 'localhost'} | Hostname: {hostname or 'N/A'}")
        print(f"連接時間: {backend_start}")
        print(f"狀態: {state} | 查詢開始: {query_start}")
        print(f"執行時長: {duration}")
        if wait_type:
            print(f"等待事件: {wait_type} - {wait_event}")
        print(f"查詢: {query[:200]}")

def get_connection_stats(cursor):
    """統計每個 IP 的連接數"""

    query = """
    SELECT
        COALESCE(client_addr::text, 'localhost') as client_ip,
        COUNT(*) as total_connections,
        COUNT(*) FILTER (WHERE state = 'active') as active_connections,
        COUNT(*) FILTER (WHERE state = 'idle') as idle_connections,
        COUNT(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction,
        application_name,
        usename
    FROM pg_stat_activity
    WHERE pid != pg_backend_pid()
    GROUP BY client_addr, application_name, usename
    ORDER BY total_connections DESC;
    """

    cursor.execute(query)
    results = cursor.fetchall()

    print("\n" + "="*100)
    print("📊 連接統計 (Connection Statistics by IP)")
    print("="*100)
    print(f"\n{'IP 地址':<20} {'應用':<25} {'用戶':<15} {'總數':<8} {'活動':<8} {'閒置':<8} {'事務中':<10}")
    print("─"*100)

    for row in results:
        ip, total, active, idle, idle_tx, app, user = row
        print(f"{ip:<20} {(app or 'N/A'):<25} {user:<15} {total:<8} {active:<8} {idle:<8} {idle_tx:<10}")

def get_slow_queries(cursor):
    """查詢慢查詢統計 (需要 pg_stat_statements 擴展)"""

    # 檢查是否安裝了 pg_stat_statements
    check_extension = """
    SELECT EXISTS(
        SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'
    );
    """

    cursor.execute(check_extension)
    has_extension = cursor.fetchone()[0]

    if not has_extension:
        print("\n⚠️  pg_stat_statements 擴展未啟用")
        print("無法查詢慢查詢統計")
        return

    query = """
    SELECT
        queryid,
        LEFT(query, 150) as query_text,
        calls,
        total_exec_time / 1000 as total_time_seconds,
        mean_exec_time / 1000 as mean_time_seconds,
        max_exec_time / 1000 as max_time_seconds,
        rows,
        shared_blks_hit,
        shared_blks_read,
        shared_blks_dirtied,
        temp_blks_written
    FROM pg_stat_statements
    ORDER BY total_exec_time DESC
    LIMIT 20;
    """

    cursor.execute(query)
    results = cursor.fetchall()

    print("\n" + "="*100)
    print("🐌 Top 20 慢查詢 (Slow Queries)")
    print("="*100)

    for idx, row in enumerate(results, 1):
        queryid, query_text, calls, total_time, mean_time, max_time, rows, blks_hit, blks_read, blks_dirty, temp_blks = row

        print(f"\n{idx}. Query ID: {queryid}")
        print(f"   調用次數: {calls:,}")
        print(f"   總執行時間: {total_time:.2f}s | 平均: {mean_time:.3f}s | 最大: {max_time:.3f}s")
        print(f"   返回行數: {rows:,}")
        print(f"   緩存命中: {blks_hit:,} | 磁盤讀取: {blks_read:,} | 臨時塊: {temp_blks:,}")
        print(f"   查詢: {query_text[:200]}")

def get_database_size(cursor):
    """查詢數據庫大小"""

    query = """
    SELECT
        datname,
        pg_size_pretty(pg_database_size(datname)) as size,
        pg_database_size(datname) as size_bytes
    FROM pg_database
    WHERE datname NOT IN ('template0', 'template1', 'rdsadmin')
    ORDER BY pg_database_size(datname) DESC;
    """

    cursor.execute(query)
    results = cursor.fetchall()

    print("\n" + "="*100)
    print("💾 數據庫大小")
    print("="*100)

    for db, size, size_bytes in results:
        print(f"{db:<30} {size:>15}")

def get_table_io_stats(cursor):
    """查詢表的 I/O 統計"""

    query = """
    SELECT
        schemaname,
        tablename,
        heap_blks_read,
        heap_blks_hit,
        CASE
            WHEN heap_blks_hit + heap_blks_read = 0 THEN 0
            ELSE ROUND(100.0 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 2)
        END as cache_hit_ratio,
        idx_blks_read,
        idx_blks_hit,
        CASE
            WHEN idx_blks_hit + idx_blks_read = 0 THEN 0
            ELSE ROUND(100.0 * idx_blks_hit / (idx_blks_hit + idx_blks_read), 2)
        END as idx_cache_hit_ratio
    FROM pg_statio_user_tables
    WHERE heap_blks_read + heap_blks_hit > 0
    ORDER BY heap_blks_read DESC
    LIMIT 20;
    """

    cursor.execute(query)
    results = cursor.fetchall()

    print("\n" + "="*100)
    print("📊 Top 20 表 I/O 統計 (磁盤讀取最多)")
    print("="*100)
    print(f"\n{'Schema':<15} {'表名':<30} {'堆讀取':<12} {'堆命中':<12} {'命中率%':<10} {'索引讀':<12} {'索引命中':<12} {'索引命中率%':<12}")
    print("─"*100)

    for row in results:
        schema, table, heap_read, heap_hit, cache_ratio, idx_read, idx_hit, idx_ratio = row
        print(f"{schema:<15} {table:<30} {heap_read:<12,} {heap_hit:<12,} {cache_ratio:<10} {idx_read:<12,} {idx_hit:<12,} {idx_ratio:<12}")

def main():
    parser = argparse.ArgumentParser(description='PostgreSQL 連接和查詢分析工具')
    parser.add_argument('--host', required=True, help='數據庫主機地址')
    parser.add_argument('--port', default='5432', help='端口 (默認: 5432)')
    parser.add_argument('--database', required=True, help='數據庫名稱')
    parser.add_argument('--user', required=True, help='用戶名')
    parser.add_argument('--password', required=True, help='密碼')

    args = parser.parse_args()

    print("\n" + "="*100)
    print("🔍 PostgreSQL 連接和查詢分析工具")
    print("="*100)
    print(f"主機: {args.host}")
    print(f"數據庫: {args.database}")
    print(f"用戶: {args.user}")
    print(f"時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    try:
        # 連接數據庫
        conn = psycopg2.connect(
            host=args.host,
            port=args.port,
            database=args.database,
            user=args.user,
            password=args.password,
            connect_timeout=10
        )

        cursor = conn.cursor()

        print("\n✅ 數據庫連接成功！")

        # 執行各種分析
        get_connection_stats(cursor)
        get_active_connections(cursor)
        get_database_size(cursor)
        get_table_io_stats(cursor)
        get_slow_queries(cursor)

        cursor.close()
        conn.close()

        print("\n" + "="*100)
        print("✅ 分析完成")
        print("="*100 + "\n")

    except psycopg2.Error as e:
        print(f"\n❌ 數據庫連接錯誤：{e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ 錯誤：{e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
