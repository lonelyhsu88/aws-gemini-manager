# wilddiggr 記憶體問題修復指南

## 🎯 問題根源

**發現關鍵配置**：`DebugMode="1"` 在生產環境啟用，導致過度的日誌記錄

```xml
<services ... DebugMode="1" ... >
```

這個配置很可能控制：
- ✅ GORM SQL 日誌級別（每次查詢都記錄詳細 SQL）
- ✅ Zap Logger 詳細級別（Info/Debug 級別）
- ✅ 應用層的 debug 日誌

---

## 📍 配置位置

### Git 源倉庫（需要修改的地方）

```yaml
Repository: https://gitlab.ftgaming.cc/devops/kustomize-prd.git
Path: gemini-game/overlays/prd/arcade-svc/arcade-wilddiggr-game
Branch: main (或 master)
```

### 當前部署信息

```yaml
Namespace: wilddiggr-prd
ConfigMap: wilddiggr-config
ArgoCD App: wilddiggr-prd (自動同步已啟用)
Current Revision: c785e9f93c4897d32ca690774262e51ca3b38b4a
```

---

## 🔧 修復步驟

### 方案 A：通過 GitLab 修改（推薦）

#### Step 1: Clone 倉庫

```bash
# 進入工作目錄
cd ~/gemini/claude-project

# Clone 配置倉庫
git clone https://gitlab.ftgaming.cc/devops/kustomize-prd.git
cd kustomize-prd

# 切換到正確的分支
git checkout main  # 或 master
```

#### Step 2: 找到配置文件

配置文件應該在以下位置之一：

```bash
# 方式 1: ConfigMap YAML
gemini-game/overlays/prd/arcade-svc/arcade-wilddiggr-game/configmap.yaml

# 方式 2: Kustomization patches
gemini-game/overlays/prd/arcade-svc/arcade-wilddiggr-game/kustomization.yaml
gemini-game/overlays/prd/arcade-svc/arcade-wilddiggr-game/patches/

# 查找包含 DebugMode 的文件
cd gemini-game/overlays/prd/arcade-svc/arcade-wilddiggr-game
grep -r "DebugMode" .
```

#### Step 3: 修改配置

找到包含以下內容的文件：

**修改前**：
```xml
<services id="0" name="AG" account="wilddiggrgame1" typeId="3" serverId="4001" processors="4" GroupName="arcade" GroupNo="000" DebugMode="1" GameType="StandAloneWildDigGR" BatchSpeed="50">
```

**修改後**：
```xml
<services id="0" name="AG" account="wilddiggrgame1" typeId="3" serverId="4001" processors="4" GroupName="arcade" GroupNo="000" DebugMode="0" GameType="StandAloneWildDigGR" BatchSpeed="50">
```

**關鍵修改**：`DebugMode="1"` → `DebugMode="0"`

#### Step 4: 提交變更

```bash
# 檢查修改
git diff

# 添加變更
git add .

# 提交（使用規範的 commit message）
git commit -m "fix(wilddiggr): disable DebugMode to reduce memory usage

Changes:
- Set DebugMode from 1 to 0 in wilddiggr-prd config
- This will disable verbose GORM SQL logging
- This will reduce Zap logger verbosity

Rationale:
Memory usage has reached 96.5% (965Mi/1Gi) due to excessive logging.
Analysis shows GORM SQL logging and Zap logger are the primary causes.

Impact:
- Expected memory reduction: 30-50%
- Log volume reduction: 70-80%
- No impact on error/warning logs

Related: WILDDIGGR_MEMORY_ANALYSIS_REPORT.md"

# 推送到遠端
git push origin main  # 或 master
```

#### Step 5: 等待 ArgoCD 自動同步

由於啟用了自動同步（`selfHeal: true`），ArgoCD 會在幾分鐘內自動部署：

```bash
# 監控 ArgoCD 同步狀態
kubectl get application wilddiggr-prd -n argocd -w

# 或通過 ArgoCD UI 查看
# https://<your-argocd-url>/applications/wilddiggr-prd
```

#### Step 6: 驗證部署

```bash
# 等待 pod 重啟（約 1-2 分鐘）
kubectl rollout status statefulset -n wilddiggr-prd

# 檢查新的配置
kubectl exec -n wilddiggr-prd wilddiggr-0 -- cat /app/setting.xml | grep DebugMode
# 預期輸出：DebugMode="0"

# 監控記憶體使用（等待 10-30 分鐘觀察）
watch -n 60 'kubectl top pod wilddiggr-0 -n wilddiggr-prd'
```

---

### 方案 B：直接修改 ConfigMap（臨時方案，不推薦）

⚠️ **警告**：這個方法的修改會在下次 ArgoCD 同步時被覆蓋！僅用於緊急測試。

```bash
# 編輯 ConfigMap
kubectl edit configmap wilddiggr-config -n wilddiggr-prd

# 在編輯器中找到：DebugMode="1"
# 改為：DebugMode="0"
# 保存並退出 (:wq)

# 重啟 pod 以應用新配置
kubectl delete pod wilddiggr-0 -n wilddiggr-prd
# StatefulSet 會自動重建 pod

# 驗證
kubectl exec -n wilddiggr-prd wilddiggr-0 -- cat /app/setting.xml | grep DebugMode
```

**注意**：使用方案 B 後，必須盡快執行方案 A 來永久修復！

---

## 📊 預期效果

### 修改前（當前狀態）

```yaml
Memory Usage: 965Mi / 1Gi (96.5%)
Log Level: Debug/Info (詳細)
SQL Logging: 啟用（每次查詢都記錄）
```

### 修改後（預期）

```yaml
Memory Usage: < 600Mi / 1Gi (< 60%)  # 降低 30-50%
Log Level: Warn/Error (僅警告和錯誤)
SQL Logging: 禁用或僅記錄慢查詢
Log Volume: 減少 70-80%
```

---

## 🔍 驗證檢查清單

### 立即檢查（修改後 5 分鐘）

- [ ] **ConfigMap 已更新**
  ```bash
  kubectl get configmap wilddiggr-config -n wilddiggr-prd -o yaml | grep DebugMode
  # 預期：DebugMode="0"
  ```

- [ ] **Pod 已重啟**
  ```bash
  kubectl get pod wilddiggr-0 -n wilddiggr-prd
  # 檢查 AGE 是否為幾分鐘前
  ```

- [ ] **應用配置已生效**
  ```bash
  kubectl exec -n wilddiggr-prd wilddiggr-0 -- cat /app/setting.xml | grep DebugMode
  # 預期：DebugMode="0"
  ```

### 短期監控（修改後 30 分鐘）

- [ ] **記憶體使用開始下降**
  ```bash
  kubectl top pod wilddiggr-0 -n wilddiggr-prd
  # 預期：< 800Mi (開始下降趨勢)
  ```

- [ ] **日誌量明顯減少**
  ```bash
  kubectl exec -n wilddiggr-prd wilddiggr-0 -- du -sh /app/log/
  # 對比修改前的日誌大小
  ```

- [ ] **應用正常運行**
  ```bash
  kubectl logs -n wilddiggr-prd wilddiggr-0 --tail=50
  # 檢查無錯誤，僅有正常的 Warn/Error 日誌
  ```

### 長期驗證（修改後 24 小時）

- [ ] **記憶體穩定在安全水平**
  ```bash
  kubectl top pod wilddiggr-0 -n wilddiggr-prd
  # 預期：< 600Mi / 1Gi (< 60%)
  ```

- [ ] **無 OOM Kill 事件**
  ```bash
  kubectl describe pod wilddiggr-0 -n wilddiggr-prd | grep -i "oom\|killed"
  # 預期：無結果
  ```

- [ ] **業務指標正常**
  - 檢查遊戲服務響應時間
  - 檢查錯誤率
  - 檢查玩家連接數

---

## 🚨 回滾方案

如果修改後出現問題，可以快速回滾：

### 回滾 Git 提交

```bash
cd ~/gemini/claude-project/kustomize-prd

# 查看最近的 commit
git log --oneline -5

# 回滾到上一個版本
git revert HEAD

# 推送回滾
git push origin main
```

### 或直接修改回 DebugMode="1"

```bash
# 重複方案 A 的步驟，但改回 DebugMode="1"
```

---

## 💡 其他可能的日誌配置

如果 `DebugMode` 修改後效果不明顯，可能還需要檢查以下配置：

### 1. 環境變數

檢查是否有日誌相關的環境變數：

```bash
# 查看 Deployment/StatefulSet
cd ~/gemini/claude-project/kustomize-prd/gemini-game/overlays/prd/arcade-svc/arcade-wilddiggr-game

# 查找環境變數配置
grep -r "LOG_LEVEL\|DEBUG\|GORM\|ZAP" .
```

可能需要添加/修改：

```yaml
env:
  - name: LOG_LEVEL
    value: "warn"  # 或 "error"
  - name: GORM_LOG_LEVEL
    value: "warn"
  - name: ZAP_LOG_LEVEL
    value: "warn"
```

### 2. 應用啟動參數

檢查 `/app/entry.sh` 是否有啟動參數：

```bash
kubectl exec -n wilddiggr-prd wilddiggr-0 -- cat /app/entry.sh
```

可能需要添加 `--log-level=warn` 之類的參數。

---

## 📞 需要幫助？

### 檢查項目

1. **無法訪問 GitLab？**
   - 確認你有 `kustomize-prd` 倉庫的寫入權限
   - 檢查 VPN/網路連接

2. **找不到配置文件？**
   - 執行：`find . -name "*.yaml" -o -name "*.yml" | xargs grep -l "DebugMode"`
   - 可能在 `patches/` 或 `base/` 目錄中

3. **ArgoCD 不同步？**
   - 檢查 ArgoCD UI：https://<your-argocd-url>
   - 手動觸發同步：`argocd app sync wilddiggr-prd`
   - 檢查 sync policy：`kubectl get app wilddiggr-prd -n argocd -o yaml | grep syncPolicy -A 10`

4. **修改後記憶體沒下降？**
   - 等待時間可能需要更長（1-2 小時）
   - 檢查配置是否真的生效：`kubectl exec ... cat /app/setting.xml`
   - 查看 pprof 確認日誌分配是否減少

### 聯繫方式

如果遇到問題，請提供：
1. `kubectl top pod wilddiggr-0 -n wilddiggr-prd` 的輸出
2. `kubectl get configmap wilddiggr-config -n wilddiggr-prd -o yaml` 的輸出
3. 錯誤日誌（如果有）

---

**下一步：立即執行方案 A，將 DebugMode 改為 0**
