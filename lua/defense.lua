-- nginx 능동방어 시스템 메인 Lua 스크립트
local json = require "cjson"
local redis = require "resty.redis"

local _M = {}

-- Redis 연결 설정
local function get_redis()
    local red = redis:new()
    red:set_timeouts(1000, 1000, 1000)
    local ok, err = red:connect("127.0.0.1", 6379)
    if not ok then
        ngx.log(ngx.ERR, "Redis 연결 실패: ", err)
        return nil
    end
    return red
end

-- IP 위험도 점수 계산
local function calculate_threat_score(ip)
    local red = get_redis()
    if not red then return 0 end
    
    local score = 0
    
    -- 요청 빈도 체크
    local request_count = red:get("req_count:" .. ip) or 0
    if tonumber(request_count) > 100 then
        score = score + 30
    end
    
    -- 의심스러운 User-Agent 체크
    local user_agent = ngx.var.http_user_agent or ""
    if string.match(user_agent, "bot|crawler|spider|scanner") then
        score = score + 20
    end
    
    -- 비정상적인 요청 패턴 체크
    local uri = ngx.var.request_uri or ""
    if string.match(uri, "\.\./|\.\.\\|admin|wp-admin|phpmyadmin") then
        score = score + 40
    end
    
    -- SQL Injection 패턴 체크
    if string.match(uri, "union|select|insert|delete|drop|script") then
        score = score + 50
    end
    
    red:close()
    return score
end

-- IP 차단 여부 확인
local function is_ip_blocked(ip)
    local blocked_ips = ngx.shared.blocked_ips
    return blocked_ips:get(ip) ~= nil
end

-- IP를 차단 목록에 추가
local function block_ip(ip, reason)
    local blocked_ips = ngx.shared.blocked_ips
    blocked_ips:set(ip, reason, 3600) -- 1시간 차단
    
    -- 로그 기록
    ngx.log(ngx.WARN, "IP 차단: " .. ip .. " - 이유: " .. reason)
end

-- 요청 검증
function _M.check_request()
    local client_ip = ngx.var.remote_addr
    local uri = ngx.var.request_uri or ""
    local method = ngx.var.request_method or ""
    local user_agent = ngx.var.http_user_agent or ""
    
    -- 이미 차단된 IP인지 확인
    if is_ip_blocked(client_ip) then
        ngx.var.blocked = "1"
        ngx.var.block_reason = "blocked_ip"
        ngx.var.threat_level = "high"
        ngx.status = 403
        ngx.say("Access Denied")
        ngx.exit(403)
    end
    
    -- 위험도 점수 계산
    local threat_score = calculate_threat_score(client_ip)
    
    -- 위험도에 따른 처리
    if threat_score > 80 then
        block_ip(client_ip, "high_threat_score")
        ngx.var.blocked = "1"
        ngx.var.block_reason = "high_threat"
        ngx.var.threat_level = "critical"
        ngx.status = 403
        ngx.say("Access Denied")
        ngx.exit(403)
    elseif threat_score > 50 then
        ngx.var.threat_level = "high"
        -- Rate limiting 강화
        ngx.req.set_header("X-Threat-Level", "high")
    elseif threat_score > 20 then
        ngx.var.threat_level = "medium"
        ngx.req.set_header("X-Threat-Level", "medium")
    else
        ngx.var.threat_level = "low"
    end
    
    -- 특정 공격 패턴 감지
    if string.match(uri, "\.php$") and method == "GET" then
        block_ip(client_ip, "php_scanning")
        ngx.var.blocked = "1"
        ngx.var.block_reason = "php_scanning"
        ngx.var.threat_level = "critical"
        ngx.status = 403
        ngx.say("Access Denied")
        ngx.exit(403)
    end
    
    -- Bot 감지
    if string.match(user_agent, "bot|crawler|spider") and not string.match(user_agent, "googlebot|bingbot") then
        ngx.var.threat_level = "medium"
        ngx.req.set_header("X-Bot-Detected", "true")
    end
end

-- 관리자 접근 검증
function _M.check_admin_access()
    local client_ip = ngx.var.remote_addr
    local auth_header = ngx.var.http_authorization
    
    -- 관리자 IP 화이트리스트 확인
    local admin_ips = {"127.0.0.1", "192.168.1.0/24"}
    local is_admin_ip = false
    
    for _, ip in ipairs(admin_ips) do
        if client_ip == ip or string.match(client_ip, "^" .. string.gsub(ip, "/24", "")) then
            is_admin_ip = true
            break
        end
    end
    
    if not is_admin_ip then
        ngx.status = 403
        ngx.say("Admin access denied")
        ngx.exit(403)
    end
    
    -- Basic Auth 확인
    if not auth_header then
        ngx.header["WWW-Authenticate"] = 'Basic realm="Admin Area"'
        ngx.status = 401
        ngx.say("Authentication required")
        ngx.exit(401)
    end
end

return _M
