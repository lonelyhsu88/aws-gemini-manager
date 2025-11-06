#!/usr/bin/env python3
"""
比較自定義 RDS 參數組與預設參數組的差異
"""

import boto3
import json
from collections import defaultdict

# 設定
AWS_PROFILE = 'gemini-pro_ck'
CUSTOM_PARAM_GROUP = 'postgresql14-monitoring-params-postgresmonitoringparametergroup-mywcenlqp0z2'
DEFAULT_PARAM_GROUP = 'default.postgres14'

def get_parameters(session, param_group_name, source='user'):
    """獲取參數組的參數"""
    rds = session.client('rds')

    params = {}
    paginator = rds.get_paginator('describe_db_parameters')

    page_params = {
        'DBParameterGroupName': param_group_name
    }

    if source:
        page_params['Source'] = source

    for page in paginator.paginate(**page_params):
        for param in page['Parameters']:
            params[param['ParameterName']] = {
                'Value': param.get('ParameterValue', ''),
                'ApplyMethod': param.get('ApplyMethod', ''),
                'DataType': param.get('DataType', ''),
                'Description': param.get('Description', ''),
                'AllowedValues': param.get('AllowedValues', ''),
                'Source': param.get('Source', '')
            }

    return params

def main():
    print("=" * 100)
    print("RDS 參數組比較分析")
    print("=" * 100)
    print()

    # 建立 boto3 session
    session = boto3.Session(profile_name=AWS_PROFILE)

    # 獲取自定義參數組中修改的參數
    print(f"📋 正在獲取自定義參數組的修改參數...")
    print(f"   參數組: {CUSTOM_PARAM_GROUP}")
    print()

    custom_params = get_parameters(session, CUSTOM_PARAM_GROUP, source='user')

    print(f"✅ 找到 {len(custom_params)} 個被修改的參數")
    print()

    # 獲取預設參數組中相同參數的值
    print(f"📋 正在獲取預設參數組的對應參數...")
    print(f"   參數組: {DEFAULT_PARAM_GROUP}")
    print()

    default_params = get_parameters(session, DEFAULT_PARAM_GROUP, source=None)

    print(f"✅ 預設參數組共有 {len(default_params)} 個參數")
    print()

    # 比較差異
    print("=" * 100)
    print("📊 參數差異對比")
    print("=" * 100)
    print()

    # 分類參數
    monitoring_params = []
    performance_params = []
    logging_params = []
    other_params = []

    for param_name in sorted(custom_params.keys()):
        custom_value = custom_params[param_name]['Value']
        default_value = default_params.get(param_name, {}).get('Value', '(預設未設定)')
        apply_method = custom_params[param_name]['ApplyMethod']

        param_info = {
            'name': param_name,
            'custom': custom_value,
            'default': default_value,
            'apply_method': apply_method
        }

        # 分類
        if 'log_' in param_name or 'logging' in param_name:
            logging_params.append(param_info)
        elif 'track_' in param_name or 'stat' in param_name or 'pg_stat' in param_name:
            monitoring_params.append(param_info)
        elif 'autovacuum' in param_name or 'checkpoint' in param_name or 'max_' in param_name or 'shared_' in param_name:
            performance_params.append(param_info)
        else:
            other_params.append(param_info)

    # 輸出分類結果
    categories = [
        ("🔍 監控與統計參數", monitoring_params),
        ("📝 日誌記錄參數", logging_params),
        ("⚡ 性能調校參數", performance_params),
        ("🔧 其他參數", other_params)
    ]

    for category_name, params_list in categories:
        if not params_list:
            continue

        print()
        print(f"{category_name} ({len(params_list)} 個)")
        print("-" * 100)
        print(f"{'參數名稱':<45} | {'自定義值':<25} | {'預設值':<20} | 套用方式")
        print("-" * 100)

        for p in params_list:
            custom = p['custom'] if p['custom'] else '(空)'
            default = p['default'] if p['default'] else '(空)'

            # 截斷過長的值
            if len(custom) > 25:
                custom = custom[:22] + '...'
            if len(default) > 20:
                default = default[:17] + '...'

            apply_icon = '🔄' if p['apply_method'] == 'pending-reboot' else '⚡'

            print(f"{p['name']:<45} | {custom:<25} | {default:<20} | {apply_icon} {p['apply_method']}")

    print()
    print("=" * 100)
    print("📊 統計摘要")
    print("=" * 100)
    print(f"監控與統計參數: {len(monitoring_params)} 個")
    print(f"日誌記錄參數:   {len(logging_params)} 個")
    print(f"性能調校參數:   {len(performance_params)} 個")
    print(f"其他參數:       {len(other_params)} 個")
    print(f"總共修改:       {len(custom_params)} 個參數")
    print()

    # 計算需要重啟的參數數量
    reboot_required = sum(1 for p in custom_params.values() if p['ApplyMethod'] == 'pending-reboot')
    immediate_apply = sum(1 for p in custom_params.values() if p['ApplyMethod'] == 'immediate')

    print(f"🔄 需要重啟才能生效: {reboot_required} 個")
    print(f"⚡ 立即生效:          {immediate_apply} 個")
    print()

    print("💡 圖示說明：")
    print("   🔄 = pending-reboot (需要重啟實例才能生效)")
    print("   ⚡ = immediate (修改後立即生效)")
    print()

if __name__ == '__main__':
    main()
