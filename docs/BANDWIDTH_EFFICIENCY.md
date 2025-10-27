# nginx 능동방어 시스템: 대역폭 효율 전략

## 문제 상황
공격자의 요청을 단순히 `return 403`으로 차단하면:
- 공격자는 계속 요청을 보냄
- 서버는 응답을 만들어야 함 (CPU, 메모리 사용)
- 대역폭 소모
- **비용 증가**

## 해결 전략

### 1. 🚫 **444로 즉시 연결 종료** (가장 효율적)
```nginx
server {
    location / {
        access_by_lua_block {
            if is_malicious_ip() then
                ngx.status = 444 -- HTTP 응답 없이 연결 종료
                ngx.exit(444)    -- 대역폭 소비 제로
            end
        }
        proxy_pass http://backend;
    }
}
```
**장점**: 대역폭 소비 제로, CPU 최소 사용
**단점**: 로그에 기록 안 남을 수 있음

### 2. 🕐 **타임아웃으로 리소스 소모**
```nginx
location / {
    access_by_lua_block {
        if is_attacking_ip() then
            ngx.sleep(60)  -- 공격자를 60초 대기시키기
            ngx.status = 503
            ngx.say("{}")  -- 최소 응답 (100 bytes 미만)
            ngx.exit(503)
        end
    }
    proxy_pass http://backend;
}
```
**장점**: 공격자가 리소스 소모, 서버는 최소 응답
**단점**: 서버도 리소스 사용

### 3. 🍯 **Honey Token (가짜 취약 페이지)**
```nginx
location /admin/ {
    access_by_lua_block {
        if is_suspicious_ip() then
            -- 가짜 로그인 페이지 제공
            ngx.say('<html>Fake Login Page</html>')
            ngx.exit(200)
            -- 공격자가 크리덴셜 입력을 시도하도록 유도
            log_attack_attempt()
        end
    }
    return 404; -- 정상 IP는 404
}
```
**장점**: 공격 패턴 파악 가능, 실제 취약점은 없음
**단점**: 구현 복잡도 높음

### 4. 📊 **작은 응답으로 CPU 소모**
```nginx
location / {
    access_by_lua_block {
        if is_malicious() then
            -- CPU 집약적 작업 (공격자 CPU 소모)
            local sum = 0
            for i = 1, 1000000 do
                sum = sum + i
            end
            ngx.say(tostring(sum))
            ngx.exit(200)
        end
    }
    proxy_pass http://backend;
}
```
**장점**: 공격자의 CPU 소모
**단점**: 서버도 CPU 사용

### 5. 🌑 **Shadow Ban (숨겨진 차단)**
```nginx
location / {
    access_by_lua_block {
        if is_shadow_banned() then
            -- 차단 당한 것을 모르게 함
            ngx.sleep(30)  -- 계속 대기시키기
            ngx.status = 504
            ngx.exit(504)
        end
    }
    proxy_pass http://backend;
}
```
**장점**: 공격자가 계속 요청 보냄 (시간 소모)
**단점**: 서버도 리소스 사용

## 권장 전략 조합

### 단계별 방어 (Multi-Layer Defense)

```
공격 감지
    ↓
[1단계] 444로 즉시 종료 (대역폭 보호)
    ↓ (재시도)
[2단계] 타임아웃 (시간 소모)
    ↓ (계속 시도)
[3단계] Honey Token (정보 수집)
    ↓
[4단계] Shadow Ban (숨겨진 차단)
```

### 구현 코드

```lua
-- lua/advanced_defense.lua 수정
function _M.smart_defense()
    local client_ip = ngx.var.remote_addr
    local threat_level = calculate_threat_level(client_ip)
    
    -- 1단계: 명확한 공격 → 444
    if threat_level == "critical" then
        ngx.status = 444
        ngx.exit(444)
    end
    
    -- 2단계: 의심스러운 행위 → 타임아웃
    if threat_level == "high" then
        ngx.sleep(10)
        ngx.status = 503
        ngx.say("{}")
        ngx.exit(503)
    end
    
    -- 3단계: 관찰 필요 → Honey Token
    if threat_level == "medium" then
        apply_honey_trap(client_ip)
    end
    
    -- 4단계: 정상 또는 낮은 위험
    -- 백엔드로 전달
end
```

## 비용 비교

### 기존 방식 (403 차단)
- 공격자 요청: 1000 req/sec
- 응답 크기: 100 bytes
- **대역폭**: 100 KB/sec
- **월 비용**: ~$50-100 (AWS 기준)

### 개선 방식 (444 종료)
- 공격자 요청: 1000 req/sec
- 응답 크기: 0 bytes (연결 종료)
- **대역폭**: 거의 제로
- **월 비용**: ~$1-5

### 개선 방식 (타임아웃)
- 공격자 요청: 1000 req/sec
- 응답 대기: 10초
- **공격자 CPU 소모**: 증가
- **서버 부하**: 중간

## 결론

**최적의 능동방어 전략**:
1. **대역폭 보호**: 444 사용 (즉시 종료)
2. **공격자 비용 증가**: 타임아웃 + 작은 응답
3. **정보 수집**: Honey Token
4. **숨겨진 차단**: Shadow Ban

이렇게 하면 **서버 비용을 최소화**하면서 **공격자의 비용을 최대화**할 수 있습니다!

## 추가 팁

### nginx map을 사용한 빠른 필터링
```nginx
# Lua 실행 전에 nginx map으로 빠르게 차단
map $remote_addr $block_reason {
    default "";
    "1.2.3.4" "spammer";
}

server {
    if ($block_reason) {
        return 444; # Lua 실행 안 함 (더 빠름)
    }
    
    access_by_lua_block {
        -- 여기서 추가 검사
    }
}
```

### Redis를 활용한 분산 방어
```lua
-- 여러 nginx 서버가 같은 차단 목록 공유
local red = redis:new()
red:connect("redis-cluster")

local is_blocked = red:get("blocked:" .. client_ip)
if is_blocked then
    ngx.exit(444)
end
```
