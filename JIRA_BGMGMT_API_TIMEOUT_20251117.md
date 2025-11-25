# bg-mgmtapi CreateAgent API Timeout Issue

**JIRA Ticket**: [OPS-819](https://jira.ftgaming.cc/browse/OPS-819)
**Created**: 2025-11-17
**Status**: Resolved
**Priority**: High
**Affected Services**: bg-mgmtapi, bg-centerserver, bcn-gate02 (gate2 container)

---

## Executive Summary

bg-mgmtapi service experienced intermittent timeout errors (50% failure rate) when calling CreateAgent API at `http://172.31.17.24:5000/agent/`. Root cause identified as **bcn-gate02** (gate2 container on arcade-rel-srv-01) being unresponsive due to host CPU overload. Issue resolved after upgrading arcade-rel-srv-01 from t3.small to t3.medium.

---

## Timeline

| Time (UTC) | Event | Details |
|------------|-------|---------|
| 15:58:01 | First gate2 error | connection reset by peer |
| 15:58:03 | Connection refused | bcn-gate02 at 172.31.14.180:5001 |
| 16:04:08 | CreateAgent started | GFA0010 creation process |
| 16:04:08-16:04:10 | Game servers sync | All 50+ servers completed (0.2s) |
| 16:04:10 | bcn-gate01 sync | Completed in ~2 seconds |
| 16:04:10 | bcn-gate02 sync started | **No response received** |
| 16:04:38 | HTTP timeout | 30 seconds elapsed |
| 16:04:49 | DeadlineExceeded error | RPC call failed |

---

## Problem Description

### Initial Discovery

**User Command (External Network)**:
```bash
curl --location 'https://uat-mgmt-api.elsgame.cc/api/v2/agent' \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJVc2VyIjp7InVzZXJfaWQiOjE3LCJ1c2VyX25hbWUiOiJmYXRjYXQiLCJsYXN0X2xvZ2luX3RpbWUiOiIyMDI1LTExLTE3VDA2OjAzOjE0LjQ2NTExMDExM1oiLCJyb2xlcyI6WyJhZG1pbiJdfSwiZXhwIjoxNzMxOTIwNTk0LCJpc3MiOiJiZ19tZ210X2FwaSJ9.MLSH91YEGMsKQVY2ZNnacLfDLBe8UW4X78C7MUVGTks' \
--data '{
    "AgentName": "GFA0010",
    "EnableLoyalty": 1,
    "Currency": "php",
    "EnableGameLobby": 1,
    "EnableTags": 1,
    "EnableBanners": 1,
    "EnableAutoSettle": 0,
    "EnableItem": 1
}'
```

**Error Response**:
```json
{
    "data": null,
    "msg": "Post \"http://172.31.17.24:5000/agent/\": context deadline exceeded",
    "status": false
}
```

**Key Observation**: External API call returns internal IP address (172.31.17.24) in error message, indicating the error occurs in the internal service communication between:
- `bg-mgmtapi` (external-facing API at uat-mgmt-api.elsgame.cc)
- `bg-centerserver` (internal service at 172.31.17.24:5000)

### Symptom Summary

**Internal Error**:
```
POST "http://172.31.17.24:5000/agent/": context deadline exceeded
```

**Characteristics**:
- **Failure rate**: 50% (13 failures vs 12 successes in 15:50-17:00 period)
- **Timeout duration**: Exactly 30 seconds (bg-mgmtapi HTTP client timeout)
- **Success duration**: 3-4 seconds when working
- **Pattern**: Intermittent failures, no clear time pattern
- **Affected endpoint**: CreateAgent API (POST /agent/)

**Log Evidence (bg-mgmtapi)**:
```json
{"level":"warn","time":"2025-11-17 16:04:38:352","caller":"controller/agent.go:237","msg":"[restapi] SendCreateAgent Error:Post \"http://172.31.17.24:5000/agent/\": context deadline exceeded"}
```

**Successful Response Example** (when working):
```json
{
    "data": {
        "AgentName": "GFA0010",
        "CallbackUrl": "",
        "Currency": "php",
        "EnableAutoSettle": false,
        "EnableBanners": true,
        "EnableGameLobby": true,
        "EnableItem": true,
        "EnableLoyalty": true,
        "EnableTags": true,
        "Hash": "b07910fcd9d0fb2b15c68e8982a27e8d9f13cdfc0df2c09b52476c12396ff7d092b3d4569fff0336601b4218c0e7ced2",
        "Pid": "GFA0010",
        "Remark": "",
        "WalletType": 0
    },
    "msg": "success",
    "status": true
}
```

---

## Root Cause Analysis

### Primary Cause

**bcn-gate02 (gate2 container) unresponsive due to host CPU overload** (Confidence: 95%+)

### Evidence Chain

1. **Host Resource Exhaustion**
   - Host: arcade-rel-srv-01 (i-0845e488b033a51b2)
   - Private IP: 172.31.14.180
   - Instance type: t3.small (2 vCPU, 2 GB RAM)
   - CPU usage: 87.9% during incident
   - Workload: 8 Docker containers competing for 2 vCPU resources

2. **bcn-gate02 Connection Errors**
   ```json
   {"level":"error","time":"2025-11-17 15:58:03:145","caller":"demand/gate.go:225","msg":"[Demand-Gate] 呼叫對 bcn-gate02 的 RPC CreatePid 請求失敗，錯誤訊息 [rpc error: code = Unavailable desc = connection error: desc = \"transport: Error while dialing dial tcp 172.31.14.180:5001: connect: connection refused\"]"}
   ```

3. **CreateAgent Execution Flow** (GFA0010 example)
   ```
   16:04:08:338 - Database operations (0.007s) ✅
   16:04:08:354 - SyncLoyaltyAddPid (0.076s) ✅
   16:04:08:430 - SyncAllGameAddAgent (0.206s) ✅
     ↳ 50+ game servers all responded in 1-3ms each

   16:04:08:644 - SyncAllGateAddAgent started
     ↳ bcn-gate01: 16:04:08:644 → 16:04:10:564 (2s) ✅
     ↳ bcn-gate02: 16:04:10:564 → **NO RESPONSE** ❌
     ↳ gate01: Never reached (blocked by gate02)

   16:04:38 - HTTP client timeout (30s)
   16:04:49 - DeadlineExceeded error
   ```

4. **Container Status**
   - Container name: gate2
   - Image: arcade-gate-stage:21
   - Port: 5001
   - Status: Up ~1 hour (restarted after instance upgrade)
   - Previously: Connection refused during CPU overload period

### Contributing Factors

- **No timeout on gate RPC calls**: bg-centerserver waits indefinitely for gate response
- **Synchronous fan-out pattern**: Single gate failure blocks entire CreateAgent flow
- **No automatic restart policy**: gate2 container required manual restart after instance upgrade
- **No circuit breaker**: Continued attempting to call unresponsive service
- **No health monitoring**: No alerts when gate containers become unresponsive

---

## Service Architecture

### Service Locations

**bcn-gate01**:
- Host: hash-rel-srv-01 (i-09f5b89a51db5cb7e)
- Private IP: 172.31.27.243
- Public IP: 43.198.49.44
- Container: gate1
- Image: bcn-gate-stage:121
- Port: 4001
- Status: ✅ Up 11 days (stable)

**bcn-gate02**:
- Host: arcade-rel-srv-01 (i-0845e488b033a51b2)
- Private IP: 172.31.14.180
- Public IP: 95.40.86.68
- Container: gate2
- Image: arcade-gate-stage:21
- Port: 5001
- Status: ⚠️ Up ~1 hour (recently restarted post-upgrade)

**bg-centerserver**:
- Host: bingo-rel-srv-01 (i-0156659c38fa6ee66)
- Private IP: 172.31.17.24
- Public IP: 16.162.129.247
- Container: bg-centerserver
- Ports: 5000 (REST), 4000 (RPC)
- Status: ✅ Running

**bg-mgmtapi**:
- Host: bingo-rel-srv-01 (same as bg-centerserver)
- Port: Calls bg-centerserver:5000
- HTTP timeout: 30 seconds

### CreateAgent Flow Architecture

```
bg-mgmtapi
  ↓ HTTP POST (30s timeout)
bg-centerserver:5000
  ├─ 1. Database operations (0.007s)
  ├─ 2. SyncLoyaltyAddPid (0.076s)
  ├─ 3. SyncAllGameAddAgent (0.206s)
  │    ├─ minesclgame1 (1-3ms)
  │    ├─ limbogame1 (1-3ms)
  │    ├─ plinkogame1 (1-3ms)
  │    └─ ... 50+ game servers ...
  └─ 4. SyncAllGateAddAgent (BLOCKING)
       ├─ bcn-gate01 (hash-rel-srv-01:4001) - 2s ✅
       ├─ bcn-gate02 (arcade-rel-srv-01:5001) - HANGS ❌
       └─ gate01 (bingo-rel-srv-01) - Never reached
```

**Problem**: Synchronous sequential calls to gates. If any gate hangs, entire request times out.

---

## Resolution

### Immediate Fix (Completed)

1. **Upgraded arcade-rel-srv-01**
   ```bash
   # Stop instance
   aws --profile gemini-pro_ck ec2 stop-instances --instance-ids i-0845e488b033a51b2

   # Modify instance type
   aws --profile gemini-pro_ck ec2 modify-instance-attribute \
     --instance-id i-0845e488b033a51b2 \
     --instance-type t3.medium

   # Start instance
   aws --profile gemini-pro_ck ec2 start-instances --instance-ids i-0845e488b033a51b2
   ```

   **Result**:
   - CPU usage: 87.9% → ~6%
   - RAM: 2 GB → 4 GB (+100%)
   - All containers stable

2. **Manually restarted gate2 container**
   ```bash
   ssh ec2-user@95.40.86.68
   docker restart gate2
   ```

   **Result**:
   - gate2 now responding to RPC calls
   - API timeout errors resolved

### Verification

- ✅ CPU usage stable at ~6%
- ✅ All 8 containers running normally on arcade-rel-srv-01
- ✅ gate2 responding to RPC calls
- ✅ CreateAgent API success rate: 100%
- ✅ No timeout errors in logs

---

## Follow-up Actions

### Critical (Immediate)

- [ ] **Configure gate2 auto-restart**
  ```bash
  docker update --restart=always gate2
  ```

- [ ] **Add RPC timeout for gate calls in bg-centerserver**
  ```go
  // Recommended: 5-10 seconds per gate
  ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
  defer cancel()
  ```
  - Prevents single gate failure from blocking entire flow
  - Should be implemented in `demand/gate.go`

- [ ] **Configure auto-restart for all containers on arcade-rel-srv-01**
  ```bash
  docker update --restart=always $(docker ps -q)
  ```

### High Priority

- [ ] **Implement circuit breaker for gate calls**
  - Auto-skip unresponsive gates after N consecutive failures
  - Reduce cascading failures
  - Example: Skip gate after 3 consecutive timeouts for 5 minutes

- [ ] **Change to async gate sync**
  - Gate synchronization should NOT block CreateAgent HTTP response
  - Options:
    - Use goroutines with context timeout
    - Use message queue for async processing
    - Return success immediately, sync gates in background

- [ ] **Add monitoring alerts**
  - Alert when gate RPC calls fail (>10% failure rate)
  - Alert when gate containers stop
  - Alert when arcade-rel-srv-01 CPU >70%
  - CloudWatch or Prometheus metrics

- [ ] **Document gate service dependencies**
  - Which services depend on bcn-gate01/02
  - Impact if gates are unavailable
  - Recovery procedures

### Medium Priority

- [ ] **Review container resource limits on arcade-rel-srv-01**
  - Set CPU/memory limits per container
  - Prevent single container from consuming all resources
  - Document in docker-compose.yml

- [ ] **Add health checks for gate containers**
  - Docker HEALTHCHECK directive
  - Periodic RPC health check endpoint
  - Auto-restart on health check failure

- [ ] **Implement retry logic with exponential backoff**
  - For gate RPC calls
  - For bg-mgmtapi → bg-centerserver calls
  - With circuit breaker to prevent thundering herd

- [ ] **Review other t3.small instances**
  - Check if any other instances have similar issues
  - Capacity planning based on actual workload

---

## Technical Details

### Log Analysis

**Successful CreateAgent (3-4 seconds)**:
```
16:07:19:698 - CreateAgent started (GFA0028)
16:07:19:698-16:07:23:770 - All operations completed
Duration: ~4 seconds
Components: DB + Loyalty + Games (0.2s) + Gates (3.8s)
```

**Failed CreateAgent (30+ seconds timeout)**:
```
16:04:08:338 - CreateAgent started (GFA0010)
16:04:08:430-16:04:08:636 - Game servers sync (0.2s) ✅
16:04:08:644-16:04:10:564 - bcn-gate01 sync (2s) ✅
16:04:10:564 - bcn-gate02 sync started
16:04:38 - HTTP timeout (30s elapsed) ❌
16:04:49 - DeadlineExceeded error
```

**Key Observation**: All game servers (50+) complete in <0.2s, but gates take 2-4s. When bcn-gate02 hangs, it blocks for 30+ seconds.

### Code References

Relevant code locations in bg-centerserver:

- `demand/demand.go:2447` - SyncAllGameAddAgent entry point
- `demand/demand.go:2581` - SyncAllGateAddAgent entry point
- `demand/gate.go:225` - RPC CreatePid call to gates
- `demand/gate.go:61` - Gate monitoring/health check

Relevant code in bg-mgmtapi:

- `controller/agent.go:237` - SendCreateAgent error handling

### Performance Baseline

**Normal CreateAgent latency breakdown**:
- Database operations: 7-10ms
- SyncLoyaltyAddPid: 70-80ms
- SyncAllGameAddAgent: 200-250ms (50+ servers)
- SyncAllGateAddAgent: 2-4s (3 gates sequential)
- **Total**: 3-4 seconds

**Timeout scenario**:
- Same as above until SyncAllGateAddAgent
- bcn-gate02 hangs indefinitely
- bg-mgmtapi HTTP client times out at 30s
- **Total**: 30+ seconds → Error

---

## Lessons Learned

1. **Resource Sizing is Critical**
   - t3.small (2GB RAM) insufficient for 8 Docker containers
   - CPU overload affects ALL services on host, including unrelated containers
   - Proper capacity planning essential for production workloads
   - Monitor resource usage trends, not just current usage

2. **RPC Timeout Configuration**
   - Always set timeouts for external RPC calls
   - Default Go context timeout may be too long (or infinite)
   - Per-service timeout prevents cascading failures
   - Recommended: 5-10s for synchronous calls, shorter for async

3. **Service Resilience Patterns**
   - Single service failure should NOT block entire flow
   - Circuit breaker pattern critical for distributed systems
   - Async processing for non-critical operations
   - Graceful degradation when dependencies fail

4. **Container Management Best Practices**
   - Auto-restart policies (`restart: always`) prevent manual intervention
   - Health checks enable proactive detection of failures
   - Resource limits prevent resource exhaustion
   - Document container dependencies and recovery procedures

5. **Monitoring and Alerting**
   - Proactive monitoring > reactive troubleshooting
   - Alert on degradation before complete failure
   - Track both success rate AND latency
   - Container-level metrics as important as host-level

6. **Synchronous vs Asynchronous Design**
   - Gate synchronization is non-critical for CreateAgent success
   - Should be async to not block user-facing API
   - Consider event-driven architecture for cross-service sync
   - Evaluate critical path vs nice-to-have operations

---

## Related Issues

- **[OPS-818](https://jira.ftgaming.cc/browse/OPS-818)**: arcade-rel-srv-01 SSH Timeout & CPU Overload Issue
  - Same root cause (CPU overload on arcade-rel-srv-01)
  - Same resolution (instance upgrade to t3.medium)
  - Timeline: Same day, related incidents

---

## References

### AWS Resources

- **AWS Profile**: gemini-pro_ck
- **Region**: ap-east-1 (Hong Kong)

### Log Files

- bg-mgmtapi: `/var/log/BG-MGMT-API1/Bg-Mgmt-Server.log`
- bg-centerserver: `/var/log/BGCenterServer1/Center-Server.log`

### Useful Commands

```bash
# Check bg-mgmtapi logs for timeout errors
ssh ec2-user@16.162.129.247 "grep 'context deadline exceeded' /var/log/BG-MGMT-API1/Bg-Mgmt-Server.log"

# Check bg-centerserver logs for gate errors
ssh ec2-user@16.162.129.247 "grep 'bcn-gate02' /var/log/BGCenterServer1/Center-Server.log | grep error"

# Check gate2 container status
ssh ec2-user@95.40.86.68 "docker ps -a | grep gate2"

# Monitor gate2 logs
ssh ec2-user@95.40.86.68 "docker logs -f gate2"
```

---

**Document Version**: 1.0
**Last Updated**: 2025-11-17 18:00 CST
**Author**: DevOps Team (via Claude Code)
