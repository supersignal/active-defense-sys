-- nginx 능동방어 시스템 고급 방어 전략
-- 대역폭 보호 및 효율적인 능동방어
local json = require "cjson"
local redis = require "resty.redis"

local _M = {}

-- 공유 메모리 영역
local blocked_ips = ngx.shared.blocked_ips
local ip_reputation = ngx.shared.ip_reputation
local suspicious_ips = ngx.shared.suspicious_ips

-- Redis 연결 (선택사항)
local function get_redis()
    local red = redis:new()
    red:set_timeouts(100, 100, 100) -- 짧은 타임아웃으로 빠른 처리
    local ok, err = red:connect("127.0.0.1", 6379)
    if not ok then
        return nil
    end
    return red
end

-- 1. 초기 단계에서 빠르게 차단 (최소 대역폭 소비)
local function early_reject(ip, reason)
    ngx.status = 429 -- Too Many Requests
    ngx.header["Retry-After"] = "60"
    ngx.header["X-RateLimit-Limit"] = "1"
    ngx.header["X-RateLimit-Remaining"] = "0"
    ngx.say("{\"error\":\"rate_limit_exceeded\",\"retry_after\":60}")
    ngx.exit(429)
end

-- 2. 특별 처리: 심각한 위협은 즉시 444로 연결 종료 (대역폭 소비 제로)
local function immediate_disconnect(ip, reason)
    ngx.log(ngx.WARN, "즉시 연결 종료: " .. ip .. " - 이유: " .. reason)
    ngx.status = 444 -- 연결 종료 (대역폭 소비 없음)
    ngx.exit(444)
end

-- 3. Honey Token 기반 능동방어 (서버 리소스 최소 사용)
local function apply_honey_trap(ip, uri)
    -- 가짜 취약 페이지 제공 (최소 리소스)
    if string.match(uri, "admin|wp-admin|phpmyadmin|\.php$|\.asp$") then
        ngx.header.content_type = "text/html"
        ngx.say("<html><body><h1>404 Not Found</h1></body></html>")
        ngx.status = 404
        
        -- 의심스러운 IP로 마킹 (추가 모니터링)
        suspicious_ips:set(ip, "honey_trap_visited", 300)
        
        ngx.exit(404)
    end
end

-- 4. Shadow Ban (전체 HTTP 처리 안함, 단순히 타임아웃)
local function shadow_ban(ip)
    -- 무응답 또는 매우 느린 응답
    ngx.sleep(30) -- 30초 대기
    ngx.status = 504 -- Gateway Timeout
    ngx.exit(504)
end

-- 5. 대역폭 보호: 작은 페이지로 타임아웃 생성
local function bandwidth_protection(ip)
    local red = get_redis()
    if not red then
        early_reject(ip, "no_redis")
        return
    end
    
    -- 요청 수 체크
    local key = "req_count:" .. ip
    local count = red:get(key) or 0
    count = count + 1
    red:set(key, count, 60) -- 60초 TTL
    
    red:close()
    
    -- 비정상적인 요청 빈도
    if count > 50 then
        -- 작은 크기의 fake 응답 (1KB 이하)
        ngx.header.content_type = "application/json"
        ngx.say("{}")
        ngx.status = 200
        ngx.exit(200)
    end
    
    -- 매우 높은 빈도면 타임아웃
    if count > 100 then
        ngx.sleep(10) -- 10초 대기 후 응답
        ngx.status = 503
        ngx.say("{\"error\":\"service_unavailable\"}")
        ngx.exit(503)
    end
end

-- 6. 계층적 위협 대응 (위험도에 따른 처리)
function _M.smart_defense()
    local client_ip = ngx.var.remote_addr
    local uri = ngx.var.request_uri or ""
    local user_agent = ngx.var.http_user_agent or ""
    local method = ngx.var.request_method or ""
    
    -- A. 이미 차단된 IP → 즉시 444 (대역폭 소비 제로)
    if blocked_ips:get(client_ip) then
        immediate_disconnect(client_ip, "already_blocked")
    end
    
    -- B. SQL Injection, XSS 등 명확한 공격 → 즉시 444
    if string.match(uri, "union|select|script>|javascript:|onerror=") then
        blocked_ips:set(client_ip, "injection_attempt", 7200) -- 2시간 차단
        immediate_disconnect(client_ip, "injection_detected")
    end
    
    -- C. 의심스러운 행위 → Honey Token으로 유도 (최소 리소스)
    if string.match(uri, "\.\./|admin|wp-admin|phpmyadmin") then
        blocked_ips:set(client_ip, "probing", 1800) -- 30분 차단
        apply_honey_trap(client_ip, uri)
    end
    
    -- D. 비정상적인 빈도 → 대역폭 보호 모드
    local red = get_redis()
    if red then
        local key = "freq:" .. client_ip
        local freq = red:get(key) or 0
        freq = freq + 1
        red:set(key, freq, 10) -- 10초 윈도우
        red:close()
        
        if freq > 30 then
            -- Shadow Ban 적용
            blocked_ips:set(client_ip, "high_frequency", 900) -- 15분 차단
            shadow_ban(client_ip)
        end
    end
    
    -- E. Bot 트래픽 → 정적 응답 또는 444
    if string.match(user_agent, "bot|crawler|spider") and 
       not string.match(user_agent, "googlebot|bingbot") then
        
        -- 화이트리스트된 검색엔진이 아니면 빠르게 차단
        if not string.match(user_agent, "Googlebot|Bingbot") then
            ngx.status = 403
            ngx.header["X-Bot-Detected"] = "true"
            ngx.say("{\"error\":\"bot_disallowed\"}")
            ngx.exit(403)
        end
    end
    
    -- F. 정상 사용자는 일반 처리
    -- 여기까지 도달한 요청만 실제 백엔드로 전달
end

-- 7. 적응형 Rate Limiting
function _M.adaptive_rate_limit()
    local client_ip = ngx.var.remote_addr
    local red = get_redis()
    
    if not red then return end
    
    -- 과거 평판 조회
    local reputation_key = "reputation:" .. client_ip
    local reputation = tonumber(red:get(reputation_key)) or 50
    
    -- 평판에 따른 Rate Limit 조정
    local rate_limit
    if reputation > 80 then
        rate_limit = 1 -- 1 request per second
        block_ip(client_ip, "low_reputation")
    elseif reputation > 60 then
        rate_limit = 5
    elseif reputation > 40 then
        rate_limit = 10
    else
        rate_limit = 20
    end
    
    red:close()
    
    -- Lua shared dict로 간단한 rate limit 구현
    local limit_key = "limit:" .. client_ip
    local count = tonumber(blocked_ips:get(limit_key)) or 0
    
    if count >= rate_limit then
        ngx.status = 429
        ngx.header["Retry-After"] = "60"
        ngx.say("{\"error\":\"rate_limit_exceeded\"}")
        ngx.exit(429)
    end
    
    blocked_ips:set(limit_key, count + 1, 1) -- 1초 TTL
end

-- 8. 위협 정보 수집 (차단하지 않고 정보만)
function _M.collect_threat_intel()
    local client_ip = ngx.var.remote_addr
    local uri = ngx.var.request_uri or ""
    local user_agent = ngx.var.http_user_agent or ""
    
    local red = get_redis()
    if not red then return end
    
    -- 위협 정보를 ZSet으로 수집 (정렬된 집합)
    local threat_score = 0
    
    if string.match(uri, "admin|wp-admin") then
        threat_score = threat_score + 10
    end
    
    if string.match(uri, "\.php$|\.asp$") then
        threat_score = threat_score + 15
    end
    
    if string.match(user_agent, "bot|crawler") then
        threat_score = threat_score + 5
    end
    
    -- ZSet에 점수 저장 (시간순 정렬)
    red:zadd("threat_intel", os.time(), json.encode({
        ip = client_ip,
        uri = uri,
        user_agent = user_agent,
        threat_score = threat_score
    }))
    
    -- 오래된 데이터 삭제 (7일)
    red:zremrangebyscore("threat_intel", 0, os.time() - 604800)
    
    red:close()
end

-- 9. 스마트 차단 해제 (시간 기반 자동 해제)
function _M.auto_unblock_check(ip)
    local block_info = blocked_ips:get(ip)
    if not block_info then
        return false
    end
    
    local info = json.decode(block_info)
    local block_time = info.blocked_at or 0
    local duration = info.duration or 3600
    local elapsed = os.time() - block_time
    
    if elapsed > duration then
        blocked_ips:delete(ip)
        return true
    end
    
    return false
end

return _M
