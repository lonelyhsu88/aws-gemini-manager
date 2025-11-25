# wilddiggr 記憶體問題修復工具

## 📋 快速開始

### 🚀 一鍵修復（推薦）

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-gemini-manager
./scripts/wilddiggr/fix-memory-issue.sh
```

這個腳本會自動：
1. ✅ 檢查系統依賴和 kubectl 連接
2. ✅ 顯示當前記憶體使用和配置
3. ✅ Clone/更新配置倉庫
4. ✅ 查找並修改 `DebugMode="1"` → `DebugMode="0"`
5. ✅ 提交變更到 Git
6. ✅ 提供監控指令

### 📖 手動修復

如果需要手動操作，請參考：[WILDDIGGR_CONFIG_FIX_GUIDE.md](../../WILDDIGGR_CONFIG_FIX_GUIDE.md)

---

## 🎯 問題總結

### 根本原因

**配置位置**：
```yaml
Repository: https://gitlab.ftgaming.cc/devops/kustomize-prd.git
Path: gemini-game/overlays/prd/arcade-svc/arcade-wilddiggr-game
```

**問題配置**：
```xml
<services ... DebugMode="1" ...>
```

**導致的結果**：
- ❌ GORM 每次 SQL 查詢都記錄詳細日誌（含正則表達式處理）
- ❌ Zap Logger 記錄 Info/Debug 級別日誌
- ❌ 高頻記憶體分配（1,051,737 次）
- ❌ 日誌文件鎖爭用（44,339 次）
- ❌ 記憶體使用達 96.5% (965Mi/1Gi)

---

## 📊 預期效果

| 指標 | 修改前 | 修改後（預期） |
|------|--------|----------------|
| 記憶體使用 | 965Mi / 1Gi (96.5%) | < 600Mi / 1Gi (< 60%) |
| 日誌級別 | Debug/Info | Warn/Error |
| SQL 日誌 | 全部記錄 | 禁用或僅慢查詢 |
| 日誌量 | 基線 | 減少 70-80% |
| 記憶體分配頻率 | 極高 | 降低 30-50% |

---

## 🔍 驗證步驟

### 1. 立即驗證（修改後 5 分鐘）

```bash
# 檢查配置是否生效
kubectl exec -n wilddiggr-prd wilddiggr-0 -- cat /app/setting.xml | grep DebugMode
# 預期：DebugMode="0"

# 檢查 pod 是否重啟
kubectl get pod wilddiggr-0 -n wilddiggr-prd
# 檢查 AGE 列
```

### 2. 短期監控（修改後 30 分鐘）

```bash
# 持續監控記憶體使用
watch -n 60 'kubectl top pod wilddiggr-0 -n wilddiggr-prd'
# 預期：記憶體開始下降

# 檢查日誌量
kubectl exec -n wilddiggr-prd wilddiggr-0 -- du -sh /app/log/
```

### 3. 長期驗證（修改後 24 小時）

```bash
# 檢查記憶體穩定性
kubectl top pod wilddiggr-0 -n wilddiggr-prd
# 預期：< 600Mi，穩定不再上升

# 檢查無 OOM 事件
kubectl describe pod wilddiggr-0 -n wilddiggr-prd | grep -i oom
# 預期：無結果
```

---

## 🚨 如果需要回滾

```bash
cd ~/gemini/claude-project/kustomize-prd

# 查看 commit 歷史
git log --oneline -5

# 回滾最後一次提交
git revert HEAD

# 推送回滾
git push origin main
```

---

## 📞 相關文檔

- **詳細分析報告**：[WILDDIGGR_MEMORY_ANALYSIS_REPORT.md](../../WILDDIGGR_MEMORY_ANALYSIS_REPORT.md)
- **完整修復指南**：[WILDDIGGR_CONFIG_FIX_GUIDE.md](../../WILDDIGGR_CONFIG_FIX_GUIDE.md)

---

## ⚙️ 腳本選項

```bash
# 顯示幫助
./scripts/wilddiggr/fix-memory-issue.sh --help

# 僅檢查不修改
# (腳本會在每一步詢問確認)
```

---

**創建時間**: 2025-11-16
**最後更新**: 2025-11-16
