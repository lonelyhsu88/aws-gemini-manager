# Akamai CDN 動態 API 緩存策略

**適用場景**: 動態 API 內容需要緩存但又要保證數據正確性
**API 類型**:
1. `ds-r.geminiservice.cc/domains?type=Hash` - 域名配置 API
2. `gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo` - 遊戲信息 API

---

## 📋 動態 API 分類與策略

### 情況判斷流程

```
您的 API 是動態的，請先確認屬於哪種類型：

1️⃣ 參數化動態 (Parameter-based Dynamic)
   - 根據參數返回不同內容
   - 相同參數 = 相同響應
   - 不包含用戶特定信息
   → 適合：參數化緩存 ✅

2️⃣ 用戶特定動態 (User-specific Dynamic)
   - 包含用戶 ID、餘額、積分等
   - 不同用戶 = 不同響應
   → 適合：私有緩存或不緩存 ⚠️

3️⃣ 時間敏感動態 (Time-sensitive Dynamic)
   - 內容頻繁變化（秒級/分鐘級）
   - 需要即時更新
   → 適合：短時緩存 + 條件請求 ⚠️

4️⃣ 半靜態動態 (Semi-static Dynamic)
   - 內容變化不頻繁（小時/天級）
   - 但技術上是動態生成
   → 適合：中長時緩存 ✅
```

---

## 🎯 針對您的兩個 API 的策略

### API 1: 域名配置 API
**URL**: `https://ds-r.geminiservice.cc/domains?type=Hash`

#### 特性分析
```javascript
// 可能的響應格式
{
  "type": "Hash",
  "domains": {
    "primary": "hash.example.com",
    "backup": "hash-backup.example.com",
    "cdn": "hash-cdn.example.com"
  },
  "version": "1.2.3",
  "timestamp": "2025-10-31T10:00:00Z"
}
```

**判斷問題**：
- ❓ 是否包含用戶特定信息？（用戶 ID、令牌等）
- ❓ 不同用戶看到的域名是否相同？
- ❓ 更新頻率如何？（每秒？每分鐘？每小時？）
- ❓ 是否有版本控制？

#### 策略 A: 如果是「參數化動態 + 半靜態」(推薦)

**適用條件**:
- ✅ 所有用戶看到相同的域名配置
- ✅ 更新頻率低（幾小時/天）
- ✅ 按 `type` 參數返回不同配置

**Akamai Property Manager 配置**:

```json
{
  "name": "Cache Domains API - Parameterized",
  "criteria": [
    {
      "name": "path",
      "options": {
        "matchOperator": "MATCHES_ONE_OF",
        "values": ["/domains"],
        "matchCaseSensitive": false
      }
    },
    {
      "name": "requestHeader",
      "options": {
        "matchOperator": "DOES_NOT_EXIST",
        "headerName": "Authorization"
      }
    }
  ],
  "children": [
    {
      "name": "Caching Configuration",
      "behaviors": [
        {
          "name": "caching",
          "options": {
            "behavior": "MAX_AGE",
            "mustRevalidate": false,
            "ttl": "5m"
          }
        },
        {
          "name": "downstreamCache",
          "options": {
            "behavior": "ALLOW",
            "allowBehavior": "LESSER",
            "sendHeaders": "CACHE_CONTROL_AND_EXPIRES",
            "sendPrivate": false
          }
        },
        {
          "name": "cacheKeyQueryParams",
          "options": {
            "behavior": "INCLUDE",
            "parameters": ["type"],
            "exactMatch": true
          }
        },
        {
          "name": "cacheId",
          "options": {
            "rule": "domains-api-${query:type}",
            "includeValue": true
          }
        }
      ]
    },
    {
      "name": "Response Headers",
      "behaviors": [
        {
          "name": "modifyOutgoingResponseHeader",
          "options": {
            "action": "MODIFY",
            "standardAddHeaderName": "CACHE_CONTROL",
            "newHeaderValue": "public, max-age=300, stale-while-revalidate=60"
          }
        },
        {
          "name": "modifyOutgoingResponseHeader",
          "options": {
            "action": "MODIFY",
            "customHeaderName": "X-Cache-Info",
            "newHeaderValue": "domains-api-cached"
          }
        }
      ]
    }
  ]
}
```

**關鍵配置說明**:

1. **Cache Key 包含參數**:
   ```json
   "cacheKeyQueryParams": {
     "behavior": "INCLUDE",
     "parameters": ["type"]
   }
   ```
   - 不同 `type` 參數會創建不同的緩存項
   - `?type=Hash` 和 `?type=Slot` 分別緩存

2. **TTL 設置**:
   ```
   CDN TTL: 5 分鐘
   Browser TTL: 5 分鐘
   Stale-while-revalidate: 60 秒
   ```

3. **條件**:
   - 只緩存沒有 `Authorization` 頭的請求（公共數據）

---

#### 策略 B: 如果包含「時間敏感數據」

**適用條件**:
- ⚠️ 配置可能隨時更新（故障轉移）
- ⚠️ 需要較快的更新速度

**Akamai 配置**:

```json
{
  "name": "Cache Domains API - Time Sensitive",
  "criteria": [
    {
      "name": "path",
      "options": {
        "matchOperator": "MATCHES_ONE_OF",
        "values": ["/domains"]
      }
    }
  ],
  "behaviors": [
    {
      "name": "caching",
      "options": {
        "behavior": "MAX_AGE",
        "ttl": "1m"
      }
    },
    {
      "name": "prefreshCache",
      "options": {
        "enabled": true,
        "prefreshval": 90
      }
    },
    {
      "name": "downstreamCache",
      "options": {
        "behavior": "ALLOW",
        "sendHeaders": "CACHE_CONTROL",
        "allowBehavior": "FROM_VALUE",
        "value": "max-age=60, stale-if-error=300"
      }
    }
  ]
}
```

**關鍵特性**:
- **TTL**: 1 分鐘（快速更新）
- **Prefresh**: 在緩存剩餘 10% 時間時後台更新
- **Stale-if-error**: 錯誤時使用 5 分鐘內的舊緩存

---

### API 2: 遊戲信息 API
**URL**: `https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko`

#### 特性分析
```javascript
// 可能的響應格式
{
  "gameId": "StandAlonePlinko",
  "productId": "ELS",
  "url": "https://game.example.com/plinko/index.html",
  "version": "2.1.5",
  "config": {
    "maxBet": 1000,
    "minBet": 10
  },
  // ❓ 是否包含用戶信息？
  "userId": "xxx",  // 如果有 = 不能公共緩存
  "balance": 5000   // 如果有 = 不能公共緩存
}
```

**判斷問題**：
- ❓ 響應是否包含 `userId`、`balance`、`token` 等用戶特定字段？
- ❓ 相同 `productId` + `gameType` 是否對所有用戶返回相同內容？
- ❓ 遊戲版本更新頻率？

#### 策略 A: 如果是「純配置數據」（不含用戶信息）

**Akamai 配置**:

```json
{
  "name": "Cache GameInfo API - Configuration Only",
  "criteria": [
    {
      "name": "path",
      "options": {
        "matchOperator": "MATCHES_ONE_OF",
        "values": ["/api/v1/operator/url/gameInfo"]
      }
    },
    {
      "name": "requestHeader",
      "options": {
        "matchOperator": "DOES_NOT_EXIST",
        "headerName": "Authorization"
      }
    }
  ],
  "behaviors": [
    {
      "name": "caching",
      "options": {
        "behavior": "MAX_AGE",
        "ttl": "10m"
      }
    },
    {
      "name": "cacheKeyQueryParams",
      "options": {
        "behavior": "INCLUDE",
        "parameters": ["productId", "gameType"],
        "exactMatch": true
      }
    },
    {
      "name": "cacheId",
      "options": {
        "rule": "gameinfo-${query:productId}-${query:gameType}"
      }
    },
    {
      "name": "downstreamCache",
      "options": {
        "behavior": "ALLOW",
        "sendHeaders": "CACHE_CONTROL",
        "allowBehavior": "LESSER"
      }
    },
    {
      "name": "modifyOutgoingResponseHeader",
      "options": {
        "action": "MODIFY",
        "standardAddHeaderName": "CACHE_CONTROL",
        "newHeaderValue": "public, max-age=600, s-maxage=1800, stale-if-error=3600"
      }
    }
  ]
}
```

**特點**:
- **Cache Key**: 基於 `productId` + `gameType` 組合
- **CDN TTL**: 10 分鐘
- **Browser TTL**: 10 分鐘
- **CDN 延長**: `s-maxage=1800` (30 分鐘，CDN 層更激進)
- **錯誤容忍**: 1 小時內的舊緩存可用

---

#### 策略 B: 如果包含「用戶特定數據」

**⚠️ 重要**: 如果響應包含用戶信息，必須使用以下策略

**Akamai 配置**:

```json
{
  "name": "Cache GameInfo API - User Specific",
  "criteria": [
    {
      "name": "path",
      "options": {
        "matchOperator": "MATCHES_ONE_OF",
        "values": ["/api/v1/operator/url/gameInfo"]
      }
    },
    {
      "name": "requestHeader",
      "options": {
        "matchOperator": "EXISTS",
        "headerName": "Authorization"
      }
    }
  ],
  "behaviors": [
    {
      "name": "caching",
      "options": {
        "behavior": "NO_STORE"
      }
    },
    {
      "name": "downstreamCache",
      "options": {
        "behavior": "ALLOW",
        "sendHeaders": "CACHE_CONTROL",
        "sendPrivate": true,
        "allowBehavior": "FROM_VALUE",
        "value": "private, max-age=60, must-revalidate"
      }
    },
    {
      "name": "modifyOutgoingResponseHeader",
      "options": {
        "action": "MODIFY",
        "standardAddHeaderName": "CACHE_CONTROL",
        "newHeaderValue": "private, max-age=60, must-revalidate"
      }
    },
    {
      "name": "modifyOutgoingResponseHeader",
      "options": {
        "action": "ADD",
        "standardAddHeaderName": "VARY",
        "newHeaderValue": "Authorization, Cookie"
      }
    }
  ]
}
```

**關鍵點**:
- **CDN 不緩存**: `NO_STORE` (避免數據洩露)
- **瀏覽器緩存**: `private, max-age=60` (僅用戶本地緩存 1 分鐘)
- **Vary 頭**: 確保不同用戶的響應不會混淆

---

## 🔐 安全性檢查清單

### 緩存前必須確認

**對於 `/domains` API**:
- [ ] 響應是否對所有用戶相同？
- [ ] 是否包含任何敏感信息？（密鑰、令牌）
- [ ] 是否包含用戶特定信息？（ID、名稱、餘額）
- [ ] 更新頻率是多少？（決定 TTL）

**對於 `/gameInfo` API**:
- [ ] 響應是否包含用戶 ID？
- [ ] 響應是否包含用戶餘額或積分？
- [ ] 響應是否包含會話令牌？
- [ ] 相同參數是否對所有用戶返回相同內容？

### 測試方法

**測試 1: 檢查響應是否包含用戶信息**
```bash
# 用不同的 Authorization 頭測試
curl -H "Authorization: Bearer USER_A_TOKEN" \
  "https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko" \
  > response_user_a.json

curl -H "Authorization: Bearer USER_B_TOKEN" \
  "https://gameinfo-api.geminiservice.cc/api/v1/operator/url/gameInfo?productId=ELS&gameType=StandAlonePlinko" \
  > response_user_b.json

# 比較響應
diff response_user_a.json response_user_b.json

# 如果有差異 → 用戶特定，不能公共緩存
# 如果相同 → 可以公共緩存
```

**測試 2: 檢查更新頻率**
```bash
# 每分鐘請求一次，觀察響應變化
for i in {1..10}; do
  curl -s "https://ds-r.geminiservice.cc/domains?type=Hash" | md5
  sleep 60
done

# 如果 hash 頻繁變化 → 短 TTL
# 如果 hash 不變 → 長 TTL
```

---

## 🎛️ Akamai 高級功能

### 1. GraphQL 緩存 (如果使用 GraphQL)

```json
{
  "name": "GraphQL API Caching",
  "criteria": [
    {
      "name": "path",
      "options": {
        "matchOperator": "MATCHES_ONE_OF",
        "values": ["/graphql"]
      }
    },
    {
      "name": "requestMethod",
      "options": {
        "matchOperator": "IS",
        "value": "POST"
      }
    }
  ],
  "behaviors": [
    {
      "name": "graphqlCaching",
      "options": {
        "enabled": true,
        "operations": [
          {
            "operationName": "GetGameInfo",
            "ttl": "10m"
          },
          {
            "operationName": "GetDomains",
            "ttl": "5m"
          }
        ]
      }
    }
  ]
}
```

---

### 2. Edge Side Includes (ESI) - 部分動態內容

如果頁面大部分靜態，只有小部分動態：

```html
<!-- 靜態部分可以緩存 -->
<html>
<body>
  <div class="game-container">
    <!-- 動態部分不緩存 -->
    <esi:include src="/api/user/balance" />

    <!-- 靜態遊戲配置可以緩存 -->
    <esi:include src="/api/game/config?id=Plinko" ttl="600" />
  </div>
</body>
</html>
```

**Akamai 配置**:
```json
{
  "name": "ESI Processing",
  "behaviors": [
    {
      "name": "edgeSideIncludes",
      "options": {
        "enabled": true,
        "enableViaHTTP": true
      }
    }
  ]
}
```

---

### 3. Adaptive Acceleration (自適應加速)

針對動態 API 的智能優化：

```json
{
  "name": "Adaptive Acceleration for APIs",
  "criteria": [
    {
      "name": "path",
      "options": {
        "matchOperator": "MATCHES_ONE_OF",
        "values": ["/api/*"]
      }
    }
  ],
  "behaviors": [
    {
      "name": "adaptiveAcceleration",
      "options": {
        "enablePush": true,
        "preloadEnable": true,
        "source": "mPulse",
        "titleHttps": true,
        "titleHttp2": true,
        "compression": true
      }
    }
  ]
}
```

**效果**:
- HTTP/2 Server Push
- 智能預加載
- 壓縮優化
- 即使不緩存，也能加速 20-30%

---

### 4. Prefetching & Prefresh Cache

**Prefresh** (後台刷新緩存):
```json
{
  "name": "Prefresh Cache",
  "behaviors": [
    {
      "name": "prefreshCache",
      "options": {
        "enabled": true,
        "prefreshval": 90
      }
    }
  ]
}
```

**原理**:
```
緩存 TTL: 300 秒
Prefresh: 90%

時間線:
0s    - 用戶 A 訪問，CDN MISS，回源獲取，緩存建立
10s   - 用戶 B 訪問，CDN HIT (1ms)
270s  - 用戶 C 訪問，CDN HIT (1ms)
      - 觸發 Prefresh (剩餘 10% TTL)
      - CDN 後台向源服務器請求新內容
275s  - 用戶 D 訪問，返回舊緩存 (1ms)
      - 同時後台更新完成
280s  - 緩存已更新為新內容
300s  - TTL 到期，但已經有新內容
```

**優點**: 用戶永遠不會等待回源

---

## 📊 推薦配置總結

### 場景 1: 兩個 API 都是「純配置數據」（推薦）

**假設**:
- 不包含用戶特定信息
- 相同參數返回相同內容
- 更新頻率低（小時級）

**配置**:

#### `/domains` API
```
TTL: 5 分鐘
Cache Key: type 參數
Downstream: 允許瀏覽器緩存 5 分鐘
Stale-while-revalidate: 60 秒
```

#### `/gameInfo` API
```
TTL: 10 分鐘
Cache Key: productId + gameType
Downstream: 允許瀏覽器緩存 10 分鐘
CDN s-maxage: 30 分鐘（更激進）
Stale-if-error: 1 小時
```

**預期效果**:
```
孟買用戶首次訪問:
- API 延遲: 8 秒 (回源香港)
- 總時間: 28 秒

孟買用戶第二次訪問 (緩存窗口內):
- API 延遲: 0.01 秒 (CDN 緩存)
- 總時間: 12 秒 ✅ 改善 57%

其他孟買用戶:
- API 延遲: 0.01 秒 (CDN 緩存)
- 總時間: 10-12 秒 ✅
```

---

### 場景 2: 包含「用戶特定數據」

**配置**:

#### `/domains` API (公共)
```
CDN 緩存: 5 分鐘 (public)
```

#### `/gameInfo` API (用戶特定)
```
CDN 緩存: NO_STORE (不緩存)
瀏覽器緩存: private, 60 秒
Vary: Authorization, Cookie
```

**預期效果**:
```
孟買用戶首次訪問:
- domains API: 400ms (首次) → 1ms (第二次)
- gameInfo API: 400ms (每次都回源)
- 總時間: 28 秒 → 20 秒 ✅ 改善 29%
```

**建議**: 考慮拆分 API
```javascript
// 公共配置 API (可緩存)
GET /api/v1/game/config?gameType=Plinko
→ 返回遊戲配置 (無用戶信息)

// 用戶特定 API (不緩存)
GET /api/v1/user/game-status?gameType=Plinko
→ 返回用戶狀態 (餘額、等級等)

// 客戶端合併
const [config, userStatus] = await Promise.all([
  fetch('/api/v1/game/config?gameType=Plinko'),  // 從 CDN
  fetch('/api/v1/user/game-status?gameType=Plinko')  // 回源
]);
```

---

## 🛠️ 完整 Akamai Property Manager 配置範例

### 完整配置文件

```json
{
  "rules": {
    "name": "default",
    "children": [
      {
        "name": "Performance Optimization",
        "children": [
          {
            "name": "API Caching - Domains",
            "comments": "域名配置 API - 參數化緩存",
            "criteria": [
              {
                "name": "path",
                "options": {
                  "matchOperator": "MATCHES_ONE_OF",
                  "values": ["/domains"],
                  "matchCaseSensitive": false
                }
              }
            ],
            "behaviors": [
              {
                "name": "caching",
                "options": {
                  "behavior": "MAX_AGE",
                  "mustRevalidate": false,
                  "ttl": "5m"
                }
              },
              {
                "name": "cacheKeyQueryParams",
                "options": {
                  "behavior": "INCLUDE",
                  "parameters": ["type"],
                  "exactMatch": true
                }
              },
              {
                "name": "downstreamCache",
                "options": {
                  "behavior": "ALLOW",
                  "allowBehavior": "LESSER",
                  "sendHeaders": "CACHE_CONTROL_AND_EXPIRES",
                  "sendPrivate": false
                }
              },
              {
                "name": "modifyOutgoingResponseHeader",
                "options": {
                  "action": "MODIFY",
                  "standardAddHeaderName": "CACHE_CONTROL",
                  "newHeaderValue": "public, max-age=300, stale-while-revalidate=60"
                }
              },
              {
                "name": "modifyOutgoingResponseHeader",
                "options": {
                  "action": "ADD",
                  "standardAddHeaderName": "VARY",
                  "newHeaderValue": "Accept-Encoding"
                }
              }
            ]
          },
          {
            "name": "API Caching - GameInfo",
            "comments": "遊戲信息 API - 參數化緩存",
            "criteria": [
              {
                "name": "path",
                "options": {
                  "matchOperator": "MATCHES_ONE_OF",
                  "values": ["/api/v1/operator/url/gameInfo"],
                  "matchCaseSensitive": true
                }
              },
              {
                "name": "requestHeader",
                "options": {
                  "matchOperator": "DOES_NOT_EXIST",
                  "headerName": "Authorization"
                }
              }
            ],
            "behaviors": [
              {
                "name": "caching",
                "options": {
                  "behavior": "MAX_AGE",
                  "ttl": "10m"
                }
              },
              {
                "name": "cacheKeyQueryParams",
                "options": {
                  "behavior": "INCLUDE",
                  "parameters": ["productId", "gameType"],
                  "exactMatch": true
                }
              },
              {
                "name": "prefreshCache",
                "options": {
                  "enabled": true,
                  "prefreshval": 90
                }
              },
              {
                "name": "downstreamCache",
                "options": {
                  "behavior": "ALLOW",
                  "allowBehavior": "FROM_VALUE",
                  "value": "max-age=600, s-maxage=1800, stale-if-error=3600"
                }
              },
              {
                "name": "modifyOutgoingResponseHeader",
                "options": {
                  "action": "MODIFY",
                  "standardAddHeaderName": "CACHE_CONTROL",
                  "newHeaderValue": "public, max-age=600, s-maxage=1800, stale-if-error=3600"
                }
              }
            ]
          },
          {
            "name": "API No Cache - Authenticated",
            "comments": "帶 Authorization 的請求不緩存",
            "criteria": [
              {
                "name": "path",
                "options": {
                  "matchOperator": "MATCHES_ONE_OF",
                  "values": ["/api/*"]
                }
              },
              {
                "name": "requestHeader",
                "options": {
                  "matchOperator": "EXISTS",
                  "headerName": "Authorization"
                }
              }
            ],
            "behaviors": [
              {
                "name": "caching",
                "options": {
                  "behavior": "NO_STORE"
                }
              },
              {
                "name": "downstreamCache",
                "options": {
                  "behavior": "ALLOW",
                  "sendHeaders": "CACHE_CONTROL",
                  "sendPrivate": true,
                  "allowBehavior": "FROM_VALUE",
                  "value": "private, max-age=60"
                }
              }
            ]
          }
        ]
      },
      {
        "name": "Cache Purge Support",
        "comments": "支持快速清除緩存",
        "behaviors": [
          {
            "name": "fastInvalidate",
            "options": {
              "enabled": true
            }
          }
        ]
      }
    ],
    "behaviors": [
      {
        "name": "origin",
        "options": {
          "hostname": "origin.geminiservice.cc",
          "forwardHostHeader": "REQUEST_HOST_HEADER",
          "cacheKeyHostname": "REQUEST_HOST_HEADER",
          "compress": true,
          "enableTrueClientIp": true,
          "httpPort": 80,
          "httpsPort": 443
        }
      },
      {
        "name": "cpCode",
        "options": {
          "value": {
            "id": 123456
          }
        }
      }
    ],
    "options": {
      "is_secure": true
    }
  }
}
```

---

## 🚀 部署步驟

### 1. Akamai Control Center 部署

```bash
# 使用 Akamai CLI
akamai property-manager create-property \
  --contract ctr_XXX \
  --group grp_XXX \
  --product prd_XXX \
  --name "geminiservice-api-optimization"

# 上傳配置
akamai property-manager update-property \
  --property geminiservice-api-optimization \
  --file akamai-config.json

# 激活到 Staging
akamai property-manager activate-property \
  --property geminiservice-api-optimization \
  --network staging \
  --email alerts@example.com \
  --note "API caching optimization"

# 測試 Staging
curl -H "Pragma: akamai-x-get-cache-key" \
  "https://ds-r-staging.geminiservice.cc/domains?type=Hash"

# 激活到 Production
akamai property-manager activate-property \
  --property geminiservice-api-optimization \
  --network production \
  --email alerts@example.com \
  --note "API caching optimization - production"
```

---

### 2. 驗證緩存配置

```bash
# 測試 1: 檢查 Cache-Control 頭
curl -I "https://ds-r.geminiservice.cc/domains?type=Hash"

# 預期輸出:
# Cache-Control: public, max-age=300, stale-while-revalidate=60
# X-Cache: Miss from cloudfront (首次)
# X-Cache-Key: /domains/L/type=Hash

# 測試 2: 驗證緩存命中
curl -I "https://ds-r.geminiservice.cc/domains?type=Hash"

# 預期輸出:
# Cache-Control: public, max-age=300
# X-Cache: Hit from cloudfront (第二次)
# Age: 10

# 測試 3: 驗證不同參數分別緩存
curl -I "https://ds-r.geminiservice.cc/domains?type=Slot"

# 預期輸出:
# X-Cache: Miss from cloudfront (不同參數 = 新緩存項)
```

---

### 3. 性能測試

```bash
# 從孟買測試
ssh -i ~/.ssh/game-test-mumbai-key.pem ubuntu@MUMBAI_IP

# 測試首次訪問 (MISS)
time curl -s "https://ds-r.geminiservice.cc/domains?type=Hash" > /dev/null
# 預期: ~0.4s

# 測試緩存命中 (HIT)
time curl -s "https://ds-r.geminiservice.cc/domains?type=Hash" > /dev/null
# 預期: ~0.01s ✅

# 測試遊戲加載
./test-with-urls.sh 5
# 預期: 平均 12 秒 (vs 當前 28 秒) ✅
```

---

## 📊 監控配置

### Akamai mPulse 設置

```html
<!-- 在網頁中添加 -->
<script>
window.BOOMR_config = {
  beacon_url: "https://c.go-mpulse.net/api/beacon",
  ResourceTiming: {
    enabled: true,
    clearOnBeacon: true
  },
  autorun: false
};
</script>
<script src="//c.go-mpulse.net/boomerang/YOUR_API_KEY" async></script>
```

### CloudWatch 自定義指標

```javascript
// Lambda@Edge 函數監控緩存命中率
exports.handler = async (event) => {
  const response = event.Records[0].cf.response;
  const cacheStatus = response.headers['x-cache'] ?
    response.headers['x-cache'][0].value : 'UNKNOWN';

  // 發送到 CloudWatch
  await cloudwatch.putMetricData({
    Namespace: 'CDN/Cache',
    MetricData: [{
      MetricName: 'CacheHitRate',
      Value: cacheStatus.includes('Hit') ? 1 : 0,
      Unit: 'Count'
    }]
  }).promise();

  return response;
};
```

---

## ❓ 決策輔助

### 請確認以下問題，我將提供最適合的配置

**對於 `/domains` API**:
1. 是否所有用戶看到相同的域名配置？ (是/否)
2. 是否包含用戶 ID、令牌等敏感信息？ (是/否)
3. 更新頻率？ (實時/分鐘級/小時級/天級)
4. 是否需要即時故障轉移？ (是/否)

**對於 `/gameInfo` API**:
1. 響應是否包含用戶餘額、積分等？ (是/否)
2. 相同 productId+gameType 是否對所有用戶相同？ (是/否)
3. 遊戲版本更新頻率？ (每天/每週/每月)
4. 是否有版本號可用於緩存失效？ (是/否)

---

**文檔版本**: 1.0
**最後更新**: 2025-10-31
**作者**: Claude Code + DevOps Team
**適用**: Akamai Property Manager
