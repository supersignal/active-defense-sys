-- 공통 위협 감지 로직
-- Apache와 nginx 모두에서 사용 가능한 공통 방어 로직

local json = require "cjson"

local _M = {}

-- 위협 점수 계산 (Apache/npm nginx 공통)
function _M.calculate_threat_score(client_ip, uri, method, user_agent, headers)
    local score = 0
    local threats = {}
    
    -- 1. SQL Injection 감지
    local sql_patterns = {
        "union", "select", "insert", "delete", "update", "drop",
        "exec", "execute", "script", "1=1", "' OR '1'='1"
    }
    
    for _, pattern in ipairs(sql_patterns) do
        if string.match(uri, pattern) or string.match(headers or "", pattern) then
            score = score + 30
            table.insert(threats, "sql_injection")
        end
    end
    
    -- 2. XSS 감지
    if string.match(uri, "<script>") or string.match(uri, "javascript:") then
        score = score + 25
        table.insert(threats, "xss")
    end
    
    -- 3. Path Traversal 감지
    if string.match(uri, "%.%.%/") or string.match(uri, "%.%.\\\\") then
        score = score + 35
        table.insert(threats, "path_traversal")
    end
    
    -- 4. Command Injection 감지
    if string.match(uri, "%|") or string.match(uri, "&&") or string.match(uri, "`") then
        score = score + 40
        table.insert(threats, "command_injection")
    end
    
    -- 5. 의심스러운 User-Agent
    if user_agent == "" or user_agent == nil then
        score = score + 15
        table.insert(threats, "suspicious_user_agent")
    end
    
    -- 6. Bot/Crawler 감지 (허용된 것 제외)
    if string.match(user_agent, "bot|spider|crawler|scanner") then
        if not string.match(user_agent, "googlebot|bingbot") then
            score = score + 10
            table.insert(threats, "bot_detected")
        end
    end
    
    -- 7. 민감한 경로 스캔
    local sensitive_paths = {
        "wp-admin", "phpmyadmin", "admin", "login",
        "config", "backup", ".env", ".git"
    }
    
    for _, path in ipairs(sensitive_paths) do
        if string.match(uri, path) then
            score = score + 20
            table.insert(threats, "sensitive_scan")
        end
    end
    
    -- 8. 파일 확장자 스캔
    local suspicious_extensions = {
        "%.php", "%.asp", "%.aspx", "%.jsp", "%.sh",
        "%.pl", "%.py", "%.rb", "%.conf"
    }
    
    for _, ext in ipairs(suspicious_extensions) do
        if string.match(uri, ext .. "$") then
            score = score + 15
            table.insert(threats, "file_scan")
        end
    end
    
    return score, threats
end

-- IP 평판 계산
function _M.calculate_ip_reputation(client_ip, history)
    -- history는 이전 요청 기록 (최근 100개 요청 등)
    local score = 50 -- 기본 중립 평판
    
    if history then
        -- 좋은 행동: 정상적인 User-Agent, 유효한 리퍼러
        -- 나쁜 행동: 404 요청 많음, 다양한 경로 스캔
        
        local bad_requests = 0
        for _, request in ipairs(history) do
            if request.status == 404 then
                bad_requests = bad_requests + 1
            end
        end
        
        if bad_requests > 50 then
            score = score - 30 -- 평판 하락
        end
        
        if bad_requests < 10 then
            score = score + 20 -- 평판 상승
        end
    end
    
    return math.max(0, math.min(100, score))
end

-- Rate Limiting 임계값 계산 (IP 평판 기반)
function _M.calculate_rate_limit(client_ip, reputation)
    local base_limit = 20 -- 기본 초당 20개 요청
    
    -- 평판에 따라 임계값 조정
    if reputation > 80 then
        return math.floor(base_limit / 10) -- 1초당 2개
    elseif reputation > 60 then
        return math.floor(base_limit / 4) -- 1초당 5개
    elseif reputation < 40 then
        return math.floor(base_limit * 2) -- 1초당 40개
    else
        return base_limit
    end
end

-- 차단 여부 결정
function _M.should_block(client_ip, threat_score, reputation, frequency)
    -- 1. 매우 높은 위험도 (80점 이상)
    if threat_score > 80 then
        return true, "critical_threat", "즉시 차단"
    end
    
    -- 2. 평판이 나쁜 IP
    if reputation < 30 and threat_score > 30 then
        return true, "low_reputation", "평판 기반 차단"
    end
    
    -- 3. 매우 빠른 요청 빈도
    if frequency > 100 then -- 초당 100개 이상
        return true, "high_frequency", "빈번한 요청 차단"
    end
    
    -- 4. 계속된 의심스러운 요청
    if frequency > 30 and threat_score > 50 then
        return true, "suspicious_pattern", "의심스러운 패턴 차단"
    end
    
    return false, nil, nil
end

-- 차단 방법 결정 (444, 429, 403 등)
function _M.decide_block_method(threat_score, reason)
    -- 매우 심각한 위협 → 444 (즉시 연결 종료)
    if threat_score > 80 or reason == "command_injection" then
        return 444, "즉시 연결 종료"
    end
    
    -- DDoS 시도 → 429 + 타임아웃
    if reason == "high_frequency" then
        return 429, "Too Many Requests"
    end
    
    -- 일반적인 위협 → 403
    return 403, "Access Denied"
end

-- 사용 패턴 분석
function _M.analyze_behavior(client_ip, requests)
    local analysis = {
        total_requests = #requests,
        unique_paths = 0,
        error_ratio = 0,
        suspicious_patterns = {}
    }
    
    local paths = {}
    local errors = 0
    
    for _, req in ipairs(requests) do
        -- 경로 추적
        if not paths[req.path] then
            paths[req.path] = true
            analysis.unique_paths = analysis.unique_paths + 1
        end
        
        -- 오류 비율
        if req.status >= 400 then
            errors = errors + 1
        end
        
        -- 의심스러운 패턴 감지
        if req.user_agent == "" then
            table.insert(analysis.suspicious_patterns, "empty_user_agent")
        end
    end
    
    analysis.error_ratio = errors / analysis.total_requests
    
    return analysis
end

-- 방어 전략 결정
function _M.decide_defense_strategy(client_ip, threat_score, reputation, behavior)
    -- strategy: "allow", "rate_limit", "honey_trap", "block"
    
    -- 매우 안전한 IP
    if reputation > 70 and threat_score < 20 then
        return "allow"
    end
    
    -- 의심스러운 IP (관찰 필요)
    if reputation < 50 and threat_score > 30 and threat_score < 60 then
        return "honey_trap"
    end
    
    -- 매우 위험한 IP
    if threat_score > 60 or reputation < 30 then
        return "block"
    end
    
    -- Rate Limiting 적용
    if threat_score > 30 or behavior.error_ratio > 0.5 then
        return "rate_limit"
    end
    
    return "allow"
end

return _M
