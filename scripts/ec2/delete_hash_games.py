#!/usr/bin/env python3
"""
Delete Hash Games EC2 Instances Script
刪除 Hash Games 的 EC2 實例（帶備份選項）

⚠️  警告: 此操作不可逆！
建議先創建 AMI 快照再刪除實例
"""

import json
import boto3
from datetime import datetime
import sys

# AWS Profile
AWS_PROFILE = 'gemini-pro_ck'

# EBS pricing
EBS_PRICING_PER_GB_MONTH = 0.092

# Hash Games instances to delete
HASH_GAMES_INSTANCES = [
    {'name': 'hash-prd-aviator-game-01', 'id': 'i-06e5b6cf890ce6442', 'type': 't3.small', 'storage': 45},
    {'name': 'hash-prd-aviator2-game-01', 'id': 'i-0df1ecc7c7f8bea69', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-aviator2xin-game-01', 'id': 'i-0ea1a2b608ab63afd', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-crash-game-01', 'id': 'i-0d3ead6de66c740b9', 'type': 't3.micro', 'storage': 50},
    {'name': 'hash-prd-crashcl-game-01', 'id': 'i-032f37acb16addb36', 'type': 't3.micro', 'storage': 50},
    {'name': 'hash-prd-crashgr-game-01', 'id': 'i-07232d0d96320e79a', 'type': 't3.small', 'storage': 25},
    {'name': 'hash-prd-crashne-game-01', 'id': 'i-0d4f5fd402f9883eb', 'type': 't3.micro', 'storage': 25},
    {'name': 'hash-prd-diamonds-01', 'id': 'i-02dc44c71f8673d94', 'type': 't3.micro', 'storage': 30},
    {'name': 'hash-prd-dice-game-01', 'id': 'i-0e92e1e9b58ea4add', 'type': 't3.micro', 'storage': 30},
    {'name': 'hash-prd-dragontower-game-01', 'id': 'i-0621f59337094a0b7', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-egypthilo-game-01', 'id': 'i-073dc09d1d2ae7660', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-hilo-game-01', 'id': 'i-0548aeca9dd190498', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-hilocl-game-01', 'id': 'i-0105f1a8000ec7da7', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-hilogr-game-01', 'id': 'i-0360848b9a7d062b4', 'type': 't3.small', 'storage': 25},
    {'name': 'hash-prd-hilone-game-01', 'id': 'i-00937bc8403afe767', 'type': 't3.micro', 'storage': 25},
    {'name': 'hash-prd-keno-game-01', 'id': 'i-02b1306c3a3fb9422', 'type': 't3.micro', 'storage': 30},
    {'name': 'hash-prd-limbo-game-01', 'id': 'i-00a3e2661cdcc26f2', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-limbocl-game-01', 'id': 'i-0b85ce3ea96a5b500', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-limbogr-game-01', 'id': 'i-0171b57598332fc0e', 'type': 't3.micro', 'storage': 30},
    {'name': 'hash-prd-limbone-game-01', 'id': 'i-0ec1a99358ccfcb2b', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-luckydrop-game-01', 'id': 'i-02f01e6fd455d3439', 'type': 't3.small', 'storage': 25},
    {'name': 'hash-prd-luckydropcoc-game-01', 'id': 'i-0ad3a5854fd8e887b', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-luckydropcoc2-game-01', 'id': 'i-0358460fce5ffbcb3', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-luckydropgx-game-01', 'id': 'i-08cbdfb42729a9138', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-luckyhilo-game-01', 'id': 'i-04abe1e44976bd73f', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-mines-game-01', 'id': 'i-0bf680f6ffb9ceb97', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-minesca-game-01', 'id': 'i-01b50b93d76eb1df3', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-minescl-game-01', 'id': 'i-03fad737441972b3b', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-minesgr-game-01', 'id': 'i-05ea349ce1fd8472f', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-minesma-game-01', 'id': 'i-041fe930a00b4846c', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-minesne-game-01', 'id': 'i-0511d82c5c933fa11', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-minespm-game-01', 'id': 'i-08b9001e30572d205', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-minesraider-game-01', 'id': 'i-0bb617c05e5e1bf63', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-minessc-game-01', 'id': 'i-0fadf3a40054f0244', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-multihilo-game-01', 'id': 'i-0af981b61159f93e0', 'type': 't3.micro', 'storage': 25},
    {'name': 'hash-prd-plinko-game-01', 'id': 'i-0d273ef8dffd7049f', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-plinkocl-game-01', 'id': 'i-01e3aa080e8c8b3ed', 'type': 't3.medium', 'storage': 30},
    {'name': 'hash-prd-plinkogr-game-01', 'id': 'i-08bf8092effb8383a', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-plinkone-game-01', 'id': 'i-02ddad7444c255b88', 'type': 't3.small', 'storage': 30},
    {'name': 'hash-prd-video-poker-game-01', 'id': 'i-05f3f09489ece3eba', 'type': 't3.micro', 'storage': 30},
    {'name': 'hash-prd-wheel-game-01', 'id': 'i-0dc052e6bc451d636', 'type': 't3.micro', 'storage': 30},
]

def print_summary():
    """Print summary of instances to be deleted"""
    total_storage = sum(inst['storage'] for inst in HASH_GAMES_INSTANCES)
    total_cost = total_storage * EBS_PRICING_PER_GB_MONTH

    print("=" * 120)
    print("Hash Games EC2 實例刪除清單")
    print(f"時間: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 120)
    print()
    print("⚠️  警告: 此操作將永久刪除以下實例及其 EBS 卷！")
    print()
    print(f"總實例數: {len(HASH_GAMES_INSTANCES)} 個")
    print(f"總儲存容量: {total_storage} GB")
    print(f"刪除後每月節省: ${total_cost:.2f} USD")
    print()
    print("實例清單:")
    print("-" * 120)
    print(f"{'No.':<5} {'實例名稱':<45} {'Instance ID':<22} {'類型':<12} {'儲存(GB)':<10}")
    print("-" * 120)

    for idx, inst in enumerate(HASH_GAMES_INSTANCES, 1):
        print(f"{idx:<5} {inst['name']:<45} {inst['id']:<22} {inst['type']:<12} {inst['storage']:<10}")

    print("-" * 120)
    print()

def create_amis():
    """Create AMI backups for all instances"""
    session = boto3.Session(profile_name=AWS_PROFILE)
    ec2 = session.client('ec2')

    print("=" * 120)
    print("創建 AMI 備份")
    print("=" * 120)
    print()

    created_amis = []
    failed_amis = []

    for idx, inst in enumerate(HASH_GAMES_INSTANCES, 1):
        ami_name = f"backup-{inst['name']}-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

        try:
            print(f"[{idx}/{len(HASH_GAMES_INSTANCES)}] 創建 AMI: {inst['name']} ({inst['id']})...", end=' ')

            response = ec2.create_image(
                InstanceId=inst['id'],
                Name=ami_name,
                Description=f"Backup before deletion - {inst['name']}",
                NoReboot=True
            )

            ami_id = response['ImageId']
            created_amis.append({
                'instance_name': inst['name'],
                'instance_id': inst['id'],
                'ami_id': ami_id,
                'ami_name': ami_name
            })

            print(f"✅ 成功! AMI ID: {ami_id}")

        except Exception as e:
            print(f"❌ 失敗: {str(e)}")
            failed_amis.append({
                'instance_name': inst['name'],
                'instance_id': inst['id'],
                'error': str(e)
            })

    print()
    print("-" * 120)
    print(f"AMI 創建完成: 成功 {len(created_amis)} 個, 失敗 {len(failed_amis)} 個")
    print("-" * 120)

    if failed_amis:
        print()
        print("❌ 失敗的 AMI 創建:")
        for item in failed_amis:
            print(f"  - {item['instance_name']} ({item['instance_id']}): {item['error']}")

    # Save AMI list
    backup_file = f"hash_games_amis_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(backup_file, 'w') as f:
        json.dump({
            'created_at': datetime.now().isoformat(),
            'successful_amis': created_amis,
            'failed_amis': failed_amis
        }, f, indent=2)

    print()
    print(f"✅ AMI 清單已保存至: {backup_file}")
    print()

    return len(failed_amis) == 0

def terminate_instances():
    """Terminate all Hash Games instances"""
    session = boto3.Session(profile_name=AWS_PROFILE)
    ec2 = session.client('ec2')

    print("=" * 120)
    print("開始刪除實例")
    print("=" * 120)
    print()

    instance_ids = [inst['id'] for inst in HASH_GAMES_INSTANCES]

    deleted_instances = []
    failed_deletions = []

    for idx, inst in enumerate(HASH_GAMES_INSTANCES, 1):
        try:
            print(f"[{idx}/{len(HASH_GAMES_INSTANCES)}] 刪除: {inst['name']} ({inst['id']})...", end=' ')

            response = ec2.terminate_instances(
                InstanceIds=[inst['id']]
            )

            state = response['TerminatingInstances'][0]['CurrentState']['Name']
            deleted_instances.append({
                'instance_name': inst['name'],
                'instance_id': inst['id'],
                'state': state
            })

            print(f"✅ 成功! 狀態: {state}")

        except Exception as e:
            print(f"❌ 失敗: {str(e)}")
            failed_deletions.append({
                'instance_name': inst['name'],
                'instance_id': inst['id'],
                'error': str(e)
            })

    print()
    print("-" * 120)
    print(f"刪除完成: 成功 {len(deleted_instances)} 個, 失敗 {len(failed_deletions)} 個")
    print("-" * 120)

    if failed_deletions:
        print()
        print("❌ 失敗的刪除:")
        for item in failed_deletions:
            print(f"  - {item['instance_name']} ({item['instance_id']}): {item['error']}")

    # Save deletion log
    deletion_file = f"hash_games_deletion_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(deletion_file, 'w') as f:
        json.dump({
            'deleted_at': datetime.now().isoformat(),
            'successful_deletions': deleted_instances,
            'failed_deletions': failed_deletions
        }, f, indent=2)

    print()
    print(f"✅ 刪除日誌已保存至: {deletion_file}")
    print()

    return len(failed_deletions) == 0

def main():
    print()
    print_summary()

    # Ask for confirmation
    print("請選擇操作:")
    print("  1 - 先創建 AMI 備份，然後刪除實例 (推薦)")
    print("  2 - 直接刪除實例 (不建議)")
    print("  3 - 僅創建 AMI 備份，不刪除")
    print("  0 - 取消操作")
    print()

    choice = input("請輸入選項 (0-3): ").strip()

    if choice == '0':
        print()
        print("❌ 操作已取消")
        return

    elif choice == '1':
        print()
        print("選項 1: 先創建 AMI 備份，然後刪除實例")
        print()
        confirm = input("確認要繼續嗎？輸入 'YES' 以確認: ").strip()

        if confirm != 'YES':
            print()
            print("❌ 操作已取消")
            return

        # Create AMIs
        ami_success = create_amis()

        if not ami_success:
            print()
            print("⚠️  部分 AMI 創建失敗，是否仍要繼續刪除實例？")
            confirm2 = input("輸入 'YES' 以繼續刪除: ").strip()
            if confirm2 != 'YES':
                print()
                print("❌ 刪除操作已取消")
                return

        # Terminate instances
        print()
        input("按 Enter 繼續刪除實例...")
        terminate_instances()

    elif choice == '2':
        print()
        print("選項 2: 直接刪除實例 (沒有備份)")
        print()
        print("⚠️  警告: 這將永久刪除實例，且沒有備份！")
        confirm = input("確認要繼續嗎？輸入 'YES DELETE' 以確認: ").strip()

        if confirm != 'YES DELETE':
            print()
            print("❌ 操作已取消")
            return

        terminate_instances()

    elif choice == '3':
        print()
        print("選項 3: 僅創建 AMI 備份")
        print()
        confirm = input("確認要創建 AMI 備份嗎？輸入 'YES' 以確認: ").strip()

        if confirm != 'YES':
            print()
            print("❌ 操作已取消")
            return

        create_amis()

    else:
        print()
        print("❌ 無效的選項")
        return

    print()
    print("=" * 120)
    print("✅ 操作完成")
    print("=" * 120)

    # Calculate savings
    total_storage = sum(inst['storage'] for inst in HASH_GAMES_INSTANCES)
    monthly_savings = total_storage * EBS_PRICING_PER_GB_MONTH

    print()
    print(f"💰 刪除這 {len(HASH_GAMES_INSTANCES)} 個實例後，每月將節省: ${monthly_savings:.2f} USD")
    print(f"💰 每年節省: ${monthly_savings * 12:.2f} USD")
    print()

if __name__ == '__main__':
    main()
