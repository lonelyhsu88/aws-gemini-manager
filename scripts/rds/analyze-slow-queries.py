#!/usr/bin/env python3
"""
分析 PostgreSQL RDS 慢查詢
使用 pg_stat_statements 擴展來識別和分析慢查詢

需求: pip install psycopg2-binary tabulate
"""

import argparse
import json
import sys
from datetime import datetime
from typing import List, Dict, Any

try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
    from tabulate import tabulate
except ImportError as e:
    print(f"錯誤: 缺少必要的 Python 套件")
    print(f"請執行: pip install psycopg2-binary tabulate")
    sys.exit(1)


class SlowQueryAnalyzer:
    """慢查詢分析器"""

    def __init__(self, host: str, port: int, database: str, user: str, password: str):
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.password = password
        self.conn = None

    def connect(self):
        """連接到資料庫"""
        try:
            self.conn = psycopg2.connect(
                host=self.host,
                port=self.port,
                database=self.database,
                user=self.user,
                password=self.password,
                connect_timeout=10
            )
            print(f"✓ 成功連接到 {self.database}@{self.host}")
            return True
        except Exception as e:
            print(f"✗ 連接失敗: {e}")
            return False

    def close(self):
        """關閉連接"""
        if self.conn:
            self.conn.close()

    def check_pg_stat_statements(self) -> bool:
        """檢查 pg_stat_statements 是否啟用"""
        try:
            with self.conn.cursor() as cur:
                cur.execute("""
                    SELECT EXISTS(
                        SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'
                    );
                """)
                exists = cur.fetchone()[0]

                if not exists:
                    print("✗ pg_stat_statements 擴展未啟用")
                    print("請在資料庫中執行: CREATE EXTENSION pg_stat_statements;")
                    return False

                print("✓ pg_stat_statements 擴展已啟用")
                return True
        except Exception as e:
            print(f"✗ 檢查 pg_stat_statements 失敗: {e}")
            return False

    def get_slow_queries(self, limit: int = 20, min_mean_time_ms: float = 100.0) -> List[Dict[str, Any]]:
        """
        獲取慢查詢列表

        Args:
            limit: 返回的查詢數量
            min_mean_time_ms: 最小平均執行時間（毫秒）
        """
        query = """
        SELECT
            queryid,
            LEFT(query, 100) as query_preview,
            calls,
            total_exec_time / 1000 as total_time_sec,
            mean_exec_time as mean_time_ms,
            max_exec_time as max_time_ms,
            min_exec_time as min_time_ms,
            stddev_exec_time as stddev_time_ms,
            rows,
            100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS cache_hit_ratio
        FROM pg_stat_statements
        WHERE mean_exec_time >= %s
        ORDER BY mean_exec_time DESC
        LIMIT %s;
        """

        try:
            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(query, (min_mean_time_ms, limit))
                return cur.fetchall()
        except Exception as e:
            print(f"✗ 查詢慢查詢失敗: {e}")
            return []

    def get_most_time_consuming(self, limit: int = 20) -> List[Dict[str, Any]]:
        """獲取總執行時間最長的查詢（可能執行次數多但單次不慢）"""
        query = """
        SELECT
            queryid,
            LEFT(query, 100) as query_preview,
            calls,
            total_exec_time / 1000 as total_time_sec,
            mean_exec_time as mean_time_ms,
            max_exec_time as max_time_ms,
            100.0 * total_exec_time / SUM(total_exec_time) OVER() AS pct_total_time
        FROM pg_stat_statements
        WHERE query NOT LIKE '%pg_stat_statements%'
        ORDER BY total_exec_time DESC
        LIMIT %s;
        """

        try:
            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(query, (limit,))
                return cur.fetchall()
        except Exception as e:
            print(f"✗ 查詢總耗時失敗: {e}")
            return []

    def get_query_details(self, queryid: int) -> Dict[str, Any]:
        """獲取特定查詢的完整詳細資訊"""
        query = """
        SELECT
            queryid,
            query,
            calls,
            total_exec_time,
            mean_exec_time,
            max_exec_time,
            min_exec_time,
            stddev_exec_time,
            rows,
            shared_blks_hit,
            shared_blks_read,
            shared_blks_dirtied,
            shared_blks_written,
            local_blks_hit,
            local_blks_read,
            temp_blks_read,
            temp_blks_written,
            blk_read_time,
            blk_write_time
        FROM pg_stat_statements
        WHERE queryid = %s;
        """

        try:
            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(query, (queryid,))
                return cur.fetchone()
        except Exception as e:
            print(f"✗ 查詢詳細資訊失敗: {e}")
            return None

    def get_statistics_summary(self) -> Dict[str, Any]:
        """獲取整體統計摘要"""
        query = """
        SELECT
            COUNT(*) as total_queries,
            SUM(calls) as total_calls,
            SUM(total_exec_time) / 1000 as total_exec_time_sec,
            AVG(mean_exec_time) as avg_mean_time_ms,
            MAX(max_exec_time) as max_time_ms,
            SUM(rows) as total_rows
        FROM pg_stat_statements;
        """

        try:
            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(query)
                return cur.fetchone()
        except Exception as e:
            print(f"✗ 查詢統計摘要失敗: {e}")
            return None

    def print_slow_queries_report(self, min_mean_time_ms: float = 100.0, limit: int = 20):
        """列印慢查詢報告"""
        print("\n" + "="*100)
        print(f"慢查詢分析報告 - {self.database}")
        print(f"時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"條件: 平均執行時間 >= {min_mean_time_ms} ms")
        print("="*100)

        # 整體統計
        summary = self.get_statistics_summary()
        if summary:
            print("\n【整體統計】")
            print(f"  總查詢數: {summary['total_queries']:,}")
            print(f"  總執行次數: {summary['total_calls']:,}")
            print(f"  總執行時間: {summary['total_exec_time_sec']:,.2f} 秒")
            print(f"  平均執行時間: {summary['avg_mean_time_ms']:,.2f} ms")
            print(f"  最大執行時間: {summary['max_time_ms']:,.2f} ms")
            print(f"  總返回行數: {summary['total_rows']:,}")

        # 慢查詢列表
        print(f"\n【平均執行時間最慢的 {limit} 個查詢】")
        slow_queries = self.get_slow_queries(limit=limit, min_mean_time_ms=min_mean_time_ms)

        if slow_queries:
            table_data = []
            for i, q in enumerate(slow_queries, 1):
                table_data.append([
                    i,
                    q['queryid'],
                    q['calls'],
                    f"{q['mean_time_ms']:.2f}",
                    f"{q['max_time_ms']:.2f}",
                    f"{q['total_time_sec']:.2f}",
                    f"{q['cache_hit_ratio']:.1f}%" if q['cache_hit_ratio'] else "N/A",
                    q['query_preview']
                ])

            headers = ['#', 'Query ID', 'Calls', 'Avg(ms)', 'Max(ms)', 'Total(s)', 'Cache Hit', 'Query Preview']
            print(tabulate(table_data, headers=headers, tablefmt='grid'))
        else:
            print(f"  沒有找到平均執行時間 >= {min_mean_time_ms} ms 的查詢")

        # 總耗時最多的查詢
        print(f"\n【總執行時間最長的 {limit} 個查詢】")
        time_consuming = self.get_most_time_consuming(limit=limit)

        if time_consuming:
            table_data = []
            for i, q in enumerate(time_consuming, 1):
                table_data.append([
                    i,
                    q['queryid'],
                    q['calls'],
                    f"{q['mean_time_ms']:.2f}",
                    f"{q['max_time_ms']:.2f}",
                    f"{q['total_time_sec']:.2f}",
                    f"{q['pct_total_time']:.2f}%",
                    q['query_preview']
                ])

            headers = ['#', 'Query ID', 'Calls', 'Avg(ms)', 'Max(ms)', 'Total(s)', '% Total', 'Query Preview']
            print(tabulate(table_data, headers=headers, tablefmt='grid'))

        print("\n" + "="*100)

    def export_to_json(self, output_file: str, min_mean_time_ms: float = 100.0):
        """匯出分析結果為 JSON"""
        result = {
            'database': self.database,
            'timestamp': datetime.now().isoformat(),
            'summary': self.get_statistics_summary(),
            'slow_queries': self.get_slow_queries(limit=50, min_mean_time_ms=min_mean_time_ms),
            'time_consuming_queries': self.get_most_time_consuming(limit=50)
        }

        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(result, f, indent=2, default=str)

        print(f"\n✓ 分析結果已匯出到: {output_file}")


def main():
    parser = argparse.ArgumentParser(description='分析 PostgreSQL RDS 慢查詢')
    parser.add_argument('--host', required=True, help='RDS 端點')
    parser.add_argument('--port', type=int, default=5432, help='端口 (預設: 5432)')
    parser.add_argument('--database', required=True, help='資料庫名稱')
    parser.add_argument('--user', required=True, help='資料庫用戶')
    parser.add_argument('--password', required=True, help='資料庫密碼')
    parser.add_argument('--min-time', type=float, default=100.0,
                       help='最小平均執行時間 (ms, 預設: 100)')
    parser.add_argument('--limit', type=int, default=20,
                       help='顯示的查詢數量 (預設: 20)')
    parser.add_argument('--export', help='匯出 JSON 檔案路徑')
    parser.add_argument('--query-id', type=int, help='查詢特定 Query ID 的詳細資訊')

    args = parser.parse_args()

    # 創建分析器
    analyzer = SlowQueryAnalyzer(
        host=args.host,
        port=args.port,
        database=args.database,
        user=args.user,
        password=args.password
    )

    # 連接資料庫
    if not analyzer.connect():
        sys.exit(1)

    # 檢查 pg_stat_statements
    if not analyzer.check_pg_stat_statements():
        sys.exit(1)

    try:
        # 查詢特定 Query ID
        if args.query_id:
            details = analyzer.get_query_details(args.query_id)
            if details:
                print(f"\n查詢詳細資訊 (ID: {args.query_id})")
                print("="*100)
                for key, value in details.items():
                    print(f"  {key}: {value}")
                print("="*100)
            else:
                print(f"找不到 Query ID: {args.query_id}")
        else:
            # 列印報告
            analyzer.print_slow_queries_report(
                min_mean_time_ms=args.min_time,
                limit=args.limit
            )

            # 匯出 JSON
            if args.export:
                analyzer.export_to_json(args.export, min_mean_time_ms=args.min_time)

    finally:
        analyzer.close()


if __name__ == '__main__':
    main()
