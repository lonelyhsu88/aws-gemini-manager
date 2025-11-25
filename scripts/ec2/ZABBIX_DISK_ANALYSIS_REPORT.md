# 🔍 Zabbix Server 磁碟空間深入分析報告

**實例**: gemini-monitor-01 (i-040c741a76a42169b)
**分析日期**: 2025-11-15
**分析方式**: AWS Systems Manager (SSM) Remote Commands
**當前狀態**: ⚠️ **78% 使用率** (47GB / 60GB)

---

## 📊 磁碟使用概況

### 總覽
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p1   60G   47G   14G  78% /      ← 系統碟（問題所在）
/dev/nvme1n1    100G   40G   61G  40% /data  ← 資料碟（正常）
```

### 目錄大小分布
| 目錄 | 大小 | 佔比 | 說明 |
|------|------|------|------|
| `/var` | 40 GB | 85% | **最大佔用** - 主要是 Docker |
| `/opt` | 4.4 GB | 9% | PMM Server 數據 |
| `/usr` | 3.0 GB | 6% | 系統程式 |
| `/home` | 943 MB | <1% | 用戶資料 |
| `/boot` | 91 MB | <1% | 3 個核心版本 |
| 其他 | <100 MB | <1% | - |

---

## 🔥 重點發現：可釋放 30-40GB 空間

### 1️⃣ **Docker 容器日誌** - 25GB（最大元凶！）

| 容器 | 日誌大小 | 狀態 | 建議 |
|------|---------|------|------|
| **Grafana** | **23 GB** | Running | 🔴 **立即清理** |
| Zabbix Web | 1.7 GB | Running | 🟡 建議清理 |
| Zabbix Server | 260 MB | Running | 🟢 可接受 |
| MariaDB | <1 MB | Running | 🟢 正常 |

**日誌檔案位置**：
```bash
# Grafana 日誌（23GB）
/var/lib/docker/containers/9e0162c7ccf869b7ef68afcf11038236711197fe8f2517cc9dc72718c5241763/
  └─ 9e0162c7ccf869b7ef68afcf11038236711197fe8f2517cc9dc72718c5241763-json.log

# Zabbix Web 日誌（1.7GB）
/var/lib/docker/containers/9e7e7d3873036085119ac2ea3ddde8a69de21b4e88de9ed88c56322bbd9f7d02/
  └─ 9e7e7d3873036085119ac2ea3ddde8a69de21b4e88de9ed88c56322bbd9f7d02-json.log
```

**清理方式**：
```bash
# 方式 1: 清空但保留檔案（推薦 - 服務不中斷）
truncate -s 0 /var/lib/docker/containers/9e0162c7ccf8.../9e0162c7ccf8...-json.log
truncate -s 0 /var/lib/docker/containers/9e7e7d387303.../9e7e7d387303...-json.log

# 方式 2: 重啟容器並清理（會短暫中斷）
docker restart grafana zabbix-web-apache-mysql

# 方式 3: 使用 docker-compose（如果有）
cd <docker-compose-directory>
docker-compose restart grafana
```

**預期釋放**: 24-25 GB ✅

---

### 2️⃣ **Docker Build Cache** - 3.57GB

```bash
# 查看
docker system df

# 清理（安全 - 不影響運行中的容器）
docker builder prune -a --force

# 或完整清理（包含未使用的 images）
docker system prune -a --force
```

**預期釋放**: 3.5 GB ✅

---

### 3️⃣ **未使用的 Docker Images** - 2-5GB

**當前 Images**（23 個）：
| Image | Tag | Size | 狀態 | 建議 |
|-------|-----|------|------|------|
| grafana/grafana-enterprise | 11.6.2 | 691 MB | ✅ 使用中 | 保留 |
| grafana/grafana-enterprise | 12.0.1 | 704 MB | ❌ 未使用 | 刪除 |
| grafana/grafana-enterprise | 9.3.2 | 338 MB | ❌ 未使用 | 刪除 |
| percona/pmm-server | 2.37 | 2.03 GB | ❌ 未使用 | 刪除 |
| zabbix/zabbix-web-apache-mysql | 6.0.7 | 587 MB | ❌ 未使用 | 刪除 |
| zabbix/zabbix-server-mysql | 6.0.7 | 475 MB | ❌ 未使用 | 刪除 |
| clickvisual/clickvisual | master | 146 MB | ❌ 未使用 | 刪除 |
| postgres | latest | 417 MB | ❌ 未使用 | 刪除 |
| elastalert2 | latest | 490 MB | ❌ 未使用 | 刪除 |
| percona/percona-server | 5.7.27 | 585 MB | ❌ 未使用 | 刪除 |
| python | 3.9-alpine | 48 MB | ❌ 未使用 | 刪除 |
| node | 6-alpine | 56 MB | ❌ 未使用 | 刪除 |

**清理命令**：
```bash
# 刪除未使用的 images
docker image prune -a --force

# 或手動刪除特定 image
docker rmi grafana/grafana-enterprise:12.0.1
docker rmi percona/pmm-server:2.37
docker rmi zabbix/zabbix-web-apache-mysql:6.0.7
# ... 其他未使用的 images
```

**預期釋放**: 4-5 GB ✅

---

### 4️⃣ **PMM Server 資料** - 3.3GB

```bash
/opt/pmm/pmm-server-data  # 3.3GB
```

**說明**: Percona Monitoring and Management Server 的舊資料

**建議**:
- 🔍 確認 PMM 是否還在使用
- ❓ 如果不再使用，可完全移除
- ⚠️ 如果還在使用，需要清理舊的監控資料

**清理命令**（⚠️ 確認不再使用才執行）：
```bash
# 檢查是否有 PMM 容器運行
docker ps -a | grep pmm

# 如果沒有使用，刪除資料
sudo rm -rf /opt/pmm/pmm-server-data
```

**預期釋放**: 3.3 GB（如果不再使用）

---

### 5️⃣ **YUM Package Cache** - 1.9GB

```bash
/var/cache/yum  # 1.9GB
```

**清理命令**（完全安全）：
```bash
sudo yum clean all
```

**預期釋放**: 1.9 GB ✅

---

### 6️⃣ **舊的 Kernel 版本** - 50-100MB

**當前安裝的核心**：
```
vmlinuz-5.10.227-219.884.amzn2.x86_64  (9.7 MB)
vmlinuz-5.10.230-223.885.amzn2.x86_64  (9.7 MB)
vmlinuz-5.10.234-225.910.amzn2.x86_64  (9.8 MB) ← 當前使用
```

**清理命令**：
```bash
# 檢查當前核心
uname -r  # 應該顯示 5.10.234-225.910.amzn2.x86_64

# 列出已安裝的核心
sudo yum list installed | grep kernel

# 刪除舊核心（保留當前和前一個版本）
sudo yum remove kernel-5.10.227-219.884.amzn2.x86_64
```

**預期釋放**: 50-100 MB

---

### 7️⃣ **其他項目**

#### els_platform_report - 793MB
```bash
/opt/els_platform_report  # 793MB
  ├─ go_db_export_report: 407MB
  └─ .git: 387MB
```

**建議**: 清理 .git 歷史或移至 /data

#### home 目錄 - 943MB
```bash
/home/ec2-user  # 943MB
  └─ .local/share/TabNine/models/ce94127b.tabninemodel: 242MB
```

**建議**: TabNine 模型可以刪除（IDE 程式碼補全工具）

#### Oracle Instant Client - 309MB
```bash
/opt/oracle/instantclient_19_19  # 309MB
```

**建議**: 如果不再需要連接 Oracle 資料庫，可刪除

---

## 📋 清理優先順序與預期效果

### 🔴 Priority 1: 立即執行（零風險）

| 項目 | 大小 | 風險 | 命令 |
|------|------|------|------|
| Grafana 容器日誌 | 23 GB | 🟢 無 | `truncate -s 0 /var/lib/docker/containers/.../...json.log` |
| YUM cache | 1.9 GB | 🟢 無 | `sudo yum clean all` |
| Docker build cache | 3.6 GB | 🟢 無 | `docker builder prune -a --force` |
| **小計** | **28.5 GB** | - | - |

**執行後可用空間**: 14GB → **42.5GB** (71% → **29%**) ✅

---

### 🟡 Priority 2: 建議執行（低風險）

| 項目 | 大小 | 風險 | 說明 |
|------|------|------|------|
| Zabbix Web 日誌 | 1.7 GB | 🟡 低 | truncate 或重啟容器 |
| 未使用 Docker images | 4-5 GB | 🟡 低 | 確認不再使用才刪除 |
| 舊 kernel | 50-100 MB | 🟡 低 | 保留當前和前一版本 |
| **小計** | **6-7 GB** | - | - |

**執行後可用空間**: 42.5GB → **48-49GB** (29% → **18-20%**) ✅

---

### 🟠 Priority 3: 評估後執行（需確認）

| 項目 | 大小 | 風險 | 說明 |
|------|------|------|------|
| PMM Server 資料 | 3.3 GB | 🟠 中 | 確認不再使用 |
| els_platform_report | 793 MB | 🟡 低 | 確認是否需要 |
| Oracle Client | 309 MB | 🟡 低 | 確認是否需要連接 Oracle |
| TabNine 模型 | 242 MB | 🟢 無 | IDE 工具，可刪除 |
| **小計** | **4-5 GB** | - | - |

---

## 🚀 一鍵清理腳本

### 方案 A: 最安全清理（28GB）

```bash
#!/bin/bash
# 零風險清理腳本 - 釋放約 28GB

echo "🧹 開始安全清理..."

# 1. 清理 Grafana 容器日誌（23GB）
echo "清理 Grafana 日誌..."
sudo truncate -s 0 /var/lib/docker/containers/9e0162c7ccf869b7ef68afcf11038236711197fe8f2517cc9dc72718c5241763/*-json.log

# 2. 清理 YUM cache（1.9GB）
echo "清理 YUM cache..."
sudo yum clean all

# 3. 清理 Docker build cache（3.6GB）
echo "清理 Docker build cache..."
docker builder prune -a --force

echo "✅ 清理完成！預期釋放 ~28GB"
df -h /
```

### 方案 B: 完整清理（35-40GB）

```bash
#!/bin/bash
# 完整清理腳本 - 釋放約 35-40GB

# 執行方案 A 的所有步驟
# ... (同上) ...

# 額外步驟：

# 4. 清理 Zabbix Web 日誌（1.7GB）
echo "清理 Zabbix Web 日誌..."
sudo truncate -s 0 /var/lib/docker/containers/9e7e7d3873036085119ac2ea3ddde8a69de21b4e88de9ed88c56322bbd9f7d02/*-json.log

# 5. 刪除未使用的 Docker images（4-5GB）
echo "刪除未使用的 Docker images..."
docker image prune -a --force

# 6. 刪除舊核心（50-100MB）
echo "刪除舊核心..."
sudo yum remove -y kernel-5.10.227-219.884.amzn2.x86_64

# 7. 清理 PMM 資料（如果不再使用）（3.3GB）
# echo "清理 PMM 資料..."
# sudo rm -rf /opt/pmm/pmm-server-data

# 8. 清理 TabNine 模型（242MB）
echo "清理 TabNine 模型..."
rm -rf /home/ec2-user/.local/share/TabNine

echo "✅ 完整清理完成！預期釋放 ~35-40GB"
df -h /
```

---

## 🔧 設定 Docker 日誌輪替（防止再次發生）

### 方式 1: 全域設定（推薦）

編輯 `/etc/docker/daemon.json`：

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

重啟 Docker：
```bash
sudo systemctl restart docker
```

### 方式 2: docker-compose 設定

```yaml
version: '3'
services:
  grafana:
    image: grafana/grafana-enterprise:11.6.2
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### 方式 3: Cron 定期清理

```bash
# 每週日凌晨 2 點清理超過 1GB 的容器日誌
0 2 * * 0 find /var/lib/docker/containers -name '*-json.log' -size +1G -exec truncate -s 500M {} \;
```

---

## 📊 清理後預期結果

| 階段 | 可用空間 | 使用率 | 狀態 |
|------|---------|--------|------|
| 🔴 當前 | 14 GB | 78% | ⚠️ 警告 |
| 🟢 方案 A 後 | 42 GB | 29% | ✅ 健康 |
| 🟢 方案 B 後 | 48-50 GB | 18-20% | ✅ 優秀 |

---

## ⚠️ 執行前檢查清單

- [ ] 已建立 EBS Snapshot 備份
- [ ] 確認 Zabbix 服務狀態正常
- [ ] 選擇低峰時段執行
- [ ] 確認有權限執行 sudo 命令
- [ ] 準備好回滾方案

---

## 🔄 長期維護建議

1. **設定 Docker 日誌輪替**（最重要！）
   - 防止日誌無限增長
   - 建議: max-size=10m, max-file=3

2. **定期清理 Docker**
   ```bash
   # 每月執行
   docker system prune -a --volumes --force
   ```

3. **監控磁碟使用率**
   - 安裝 CloudWatch Agent
   - 設定 80% 警告告警

4. **定期檢查大檔案**
   ```bash
   # 每週執行
   find / -type f -size +1G -exec ls -lh {} \; 2>/dev/null
   ```

5. **審查不必要的服務**
   - PMM Server 是否還需要？
   - Oracle Client 是否還使用？
   - 舊的 Docker images 是否可刪除？

---

## 📞 需要協助？

如果在清理過程中遇到問題，請聯絡：
- DevOps Team
- Zabbix 管理員

---

**分析工具**: AWS Systems Manager (SSM)
**報告產生時間**: 2025-11-15
**下次檢查**: 建議每月執行一次深入分析
