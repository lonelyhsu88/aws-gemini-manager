# API 緩存策略建議

## 📋 當前 API 分析

### 1. **域名配置 API**
```
URL: https://ds-r.geminiservice.cc/domains?type=Hash
用途: 獲取遊戲服務器域名配置
當前緩存: cache-control: no-cache, no-store
```

**特性分析**:
- ✅ **靜態性高** - 域名配置很少變動
- ✅ **通用性高** - 所有用戶響應相同
- ✅ **可預測** - 更新頻率可控
- ❌ **需要即時性** - 故障轉移時需要快速更新

**建議緩存策略**:
```http
Cache-Control: public, max-age=300, stale-while-revalidate=60
Vary: Accept-Encoding
```

**說明**:
- `public` - CDN 和瀏覽器都可緩存
- `max-age=300` - 緩存 5 分鐘
- `stale-while-revalidate=60` - 過期後 60 秒內先返回舊數據，同時後台更新
- **優點**: 減少 95%+ 的請求，5 分鐘內幾乎零延遲
- **風險**: 故障轉移時最多 5 分鐘延遲（可接受）

---

### 2. **遊戲信息 API**
```
URL: https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo
參數: productId, gameType
用途: 獲取遊戲配置、版本信息
當前緩存: 可能是 no-cache
```

**特性分析**:
- ✅ **半靜態** - 遊戲配置不常變
- ✅ **可區分** - 按 productId + gameType 緩存
- ⚠️ **版本相關** - 遊戲更新時需要刷新
- ❌ **可能包含動態數據** - 需要確認是否有用戶特定信息

**建議緩存策略** (如果是純配置):
```http
Cache-Control: public, max-age=600, s-maxage=1800, stale-if-error=3600
Vary: Accept, productId, gameType
ETag: "<version-hash>"
```

**說明**:
- `max-age=600` - 瀏覽器緩存 10 分鐘
- `s-maxage=1800` - CDN 緩存 30 分鐘（更激進）
- `stale-if-error=3600` - 錯誤時可使用 1 小時內的舊數據
- `ETag` - 支持條件請求（304 Not Modified）
- **優點**: 大幅減少回源，支持版本控制
- **部署**: 遊戲更新時清除 CDN 緩存

**建議緩存策略** (如果包含動態數據):
```http
Cache-Control: private, max-age=60
Vary: Authorization, Cookie
```

---

## 🎯 完整緩存策略矩陣

| API 類型 | 緩存策略 | 緩存時間 | 適用場景 |
|---------|---------|---------|---------|
| **1. 靜態配置** | `public, max-age=3600` | 1 小時 | 系統配置、常量 |
| **2. 遊戲元數據** | `public, max-age=600, s-maxage=1800` | 10-30 分鐘 | 遊戲列表、配置 |
| **3. 域名服務** | `public, max-age=300` | 5 分鐘 | DNS/域名映射 |
| **4. 用戶狀態** | `private, max-age=30` | 30 秒 | 用戶信息（瀏覽器緩存） |
| **5. 實時數據** | `no-cache, must-revalidate` | 驗證後使用 | 遊戲狀態、餘額 |
| **6. 敏感操作** | `no-store, no-cache` | 不緩存 | 登入、支付 |

---

## 🔧 實施方案

### 方案 A: 服務端修改 (推薦)

在 API 服務器設置響應頭：

```go
// Go 示例
func DomainsHandler(w http.ResponseWriter, r *http.Request) {
    // 設置緩存頭
    w.Header().Set("Cache-Control", "public, max-age=300, stale-while-revalidate=60")
    w.Header().Set("Vary", "Accept-Encoding")
    
    // 返回響應
    json.NewEncoder(w).Encode(domains)
}
```

```javascript
// Node.js 示例
app.get('/domains', (req, res) => {
    res.set({
        'Cache-Control': 'public, max-age=300, stale-while-revalidate=60',
        'Vary': 'Accept-Encoding'
    });
    
    res.json(domains);
});
```

---

### 方案 B: CDN 層覆蓋 (快速部署)

在 Akamai CDN 配置中設置緩存規則：

```javascript
// Akamai Property Manager 規則示例
{
    "name": "Cache API Responses",
    "criteria": [
        {
            "name": "path",
            "options": {
                "matchOperator": "MATCHES_ONE_OF",
                "values": [
                    "/domains",
                    "/api/v1/operator/url/gameInfo"
                ]
            }
        }
    ],
    "behaviors": [
        {
            "name": "caching",
            "options": {
                "behavior": "MAX_AGE",
                "mustRevalidate": false,
                "ttl": "5m",
                "defaultTtl": "5m"
            }
        },
        {
            "name": "downstreamCache",
            "options": {
                "behavior": "ALLOW",
                "allowBehavior": "LESSER",
                "sendHeaders": "CACHE_CONTROL"
            }
        }
    ]
}
```

**Akamai 配置步驟**:
1. 登入 Akamai Control Center
2. 進入 Property Manager
3. 編輯對應的 Property
4. 添加 "Caching" 規則
5. 設置路徑匹配 + 緩存行為
6. 激活配置

---

### 方案 C: 條件緩存 (平衡方案)

使用 ETag 和條件請求：

**服務端**:
```javascript
app.get('/gameInfo', (req, res) => {
    const data = getGameInfo(req.query);
    const etag = generateETag(data);
    
    // 檢查客戶端 ETag
    if (req.headers['if-none-match'] === etag) {
        return res.status(304).end(); // Not Modified
    }
    
    res.set({
        'ETag': etag,
        'Cache-Control': 'public, max-age=300, must-revalidate'
    });
    
    res.json(data);
});
```

**優點**:
- 數據未變時返回 304（只有頭，無 body）
- 節省帶寬 90%+
- 保持數據即時性

---

## 📈 預期效果

### 實施前 (孟買):
```
每個遊戲加載:
- API 請求: 5 次
- 每次延遲: 0.4 秒
- API 總時間: 2.0 秒
- 總加載時間: 28 秒
```

### 實施後 (孟買):
```
首次加載:
- API 請求: 5 次（建立緩存）
- 每次延遲: 0.4 秒
- API 總時間: 2.0 秒
- 總加載時間: 28 秒

第二次加載（5 分鐘內）:
- API 請求: 0 次（從 CDN 緩存）
- API 延遲: 0.001 秒
- API 總時間: 0.005 秒
- 總加載時間: 12 秒 ✅ 改善 57%！

其他用戶（緩存命中）:
- API 從孟買 CDN 返回
- 延遲: 1.1ms
- 總加載時間: 10-12 秒 ✅
```

---

## ⚠️ 風險與注意事項

### 1. **緩存失效問題**

**問題**: 配置更新後，用戶仍使用舊緩存

**解決方案**:
```bash
# 方案 A: 版本化 URL
/domains?type=Hash&v=1.2.3

# 方案 B: CDN 緩存清除
curl -X POST https://api.akamai.com/ccu/v3/invalidate/url \
  -H "Content-Type: application/json" \
  -d '{"objects": ["https://ds-r.geminiservice.cc/domains?type=Hash"]}'

# 方案 C: 使用 ETag
ETag: "v1.2.3"
If-None-Match: "v1.2.3"
```

---

### 2. **用戶特定數據洩露**

**問題**: 如果 API 包含用戶特定信息，可能被 CDN 緩存並返回給其他用戶

**解決方案**:
```http
# 包含用戶數據的 API 必須設置
Cache-Control: private, max-age=60
Vary: Cookie, Authorization

# 或完全不緩存
Cache-Control: no-store
```

---

### 3. **緩存雪崩**

**問題**: 大量緩存同時過期，造成源服務器壓力

**解決方案**:
```http
# 添加隨機抖動
Cache-Control: public, max-age=300
# 在服務端添加 0-60 秒的隨機偏移

# 或使用 stale-while-revalidate
Cache-Control: public, max-age=300, stale-while-revalidate=60
```

---

## 🎯 推薦實施步驟

### Phase 1: 低風險 API (立即實施)
1. ✅ 域名配置 API: `max-age=300`
2. ✅ 遊戲元數據 API (非用戶相關): `max-age=600`
3. **預期改善**: 50-70% 延遲降低

### Phase 2: 條件請求 (1-2 週後)
1. ✅ 添加 ETag 支持
2. ✅ 實施 304 響應
3. **預期改善**: 額外 20-30% 帶寬節省

### Phase 3: 激進緩存 (測試後)
1. ⚠️ 提高 CDN 緩存時間到 30 分鐘
2. ⚠️ 實施自動緩存清除機制
3. **預期改善**: 90%+ 請求由 CDN 服務

---

## 📊 監控指標

實施後需要監控：

```javascript
// 1. 緩存命中率
const cacheHitRate = (cdnHits / totalRequests) * 100;
// 目標: >80%

// 2. 平均響應時間
const avgResponseTime = totalTime / totalRequests;
// 目標: <50ms (從孟買)

// 3. 回源率
const originRate = (originRequests / totalRequests) * 100;
// 目標: <20%

// 4. 錯誤率
const errorRate = (errors / totalRequests) * 100;
// 目標: <0.1%
```

---

## 🔗 參考資源

- [HTTP Caching - MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching)
- [Akamai Caching Best Practices](https://techdocs.akamai.com/property-mgr/docs/caching)
- [Cache-Control Header](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)

