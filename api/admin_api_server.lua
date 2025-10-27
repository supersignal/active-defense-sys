#!/usr/bin/env lua

-- 능동방어 시스템 API 서버
-- Apache와 nginx 모두 지원

local cjson = require "cjson"
local redis = require "resty.redis"

local _M = {}
local red = nil

-- Redis 연결
local function get_redis()
    if not red then
        red = redis:new()
        red:set_timeouts(1000, 1000, 1000)
        local ok, err = red:connect("127.0.0.1", 6379)
        if not ok then
            ngx.log(ngx.ERR, "Redis 연결 실패: ", err)
            return nil
        end
    end
    return red
end

-- 통계 정보 조회
function _M.get_stats()
    local red = get_redis()
    if not red then
        return {error = "Redis 연결 실패"}
    end
    
    local stats = {
        total_requests = tonumber(red:get("stats:total_requests")) or 0,
        blocked_requests = tonumber(red:get("stats:blocked_requests")) or 0,
        unique_ips = #(red:keys("ip:*")) or 0,
        active_attacks = tonumber(red:get("stats:active_attacks")) or 0,
        whitelist_count = tonumber(red:scard("whitelist")) or 0
    }
    
    return stats
end

-- 차단된 IP 목록 조회
function _M.get_blocked_ips()
    local red = get_redis()
    if not red then
        return {}
    end
    
    local blocked = {}
    local keys = red:keys("blocked:*")
    
    for _, key in ipairs(keys) do
        local ip = string.match(key, "blocked:(.+)")
        local data = red:get(key)
        
        if data then
            local info = cjson.decode(data)
            table.insert(blocked, {
                ip = ip,
                reason = info.reason,
                blocked_at = info.blocked_at,
                threat_level = info.threat_level or "high"
            })
        end
    end
    
    return blocked
end

-- IP 차단 해제
function _M.unblock_ip(ip)
    local red = get_redis()
    if not red then
        return {success = false, message = "Redis 연결 실패"}
    end
    
    red:del("blocked:" .. ip)
    return {success = true, message = "IP 차단 해제됨"}
end

-- IP 수동 차단
function _M.block_ip(ip, reason, duration)
    local red = get_redis()
    if not red then
        return {success = false, message = "Redis 연결 실패"}
    end
    
    local block_data = {
        reason = reason or "수동 차단",
        blocked_at = os.time(),
        threat_level = "manual",
        duration = duration or 3600
    }
    
    red:setex("blocked:" .. ip, block_data.duration, cjson.encode(block_data))
    
    return {success = true, message = "IP 차단됨"}
end

-- 화이트리스트 조회
function _M.get_whitelist()
    local red = get_redis()
    if not red then
        return {}
    end
    
    local whitelist = {}
    local members = red:smembers("whitelist")
    
    for _, ip in ipairs(members) do
        local data = red:get("whitelist:info:" .. ip)
        if data then
            local info = cjson.decode(data)
            table.insert(whitelist, {
                ip = ip,
                reason = info.reason,
                added_at = info.added_at,
                expires = info.expires
            })
        end
    end
    
    return whitelist
end

-- 화이트리스트 추가
function _M.add_whitelist(ip, reason, expiry)
    local red = get_redis()
    if not red then
        return {success = false, message = "Redis 연결 실패"}
    end
    
    red:sadd("whitelist", ip)
    
    local info = {
        reason = reason,
        added_at = os.time(),
        expires = expiry and (os.time() + expiry) or nil
    }
    
    if expiry and expiry > 0 then
        red:setex("whitelist:info:" .. ip, expiry, cjson.encode(info))
    else
        red:set("whitelist:info:" .. ip, cjson.encode(info))
    end
    
    return {success = true, message = "화이트리스트에 추가됨"}
end

-- 화이트리스트 제거
function _M.remove_whitelist(ip)
    local red = get_redis()
    if not red then
        return {success = false, message = "Redis 연결 실패"}
    end
    
    red:srem("whitelist", ip)
    red:del("whitelist:info:" .. ip)
    
    return {success = true, message = "화이트리스트에서 제거됨"}
end

-- 임계치 조회
function _M.get_thresholds()
    local red = get_redis()
    if not red then
        return {
            rate_limit = 100,
            threat_score = 50,
            ddos = 5000,
            sql_injection = "medium",
            xss = "medium"
        }
    end
    
    return {
        rate_limit = tonumber(red:get("threshold:rate_limit")) or 100,
        threat_score = tonumber(red:get("threshold:threat_score")) or 50,
        ddos = tonumber(red:get("threshold:ddos")) or 5000),
        sql_injection = red:get("threshold:sql_injection") or "medium",
        xss = red:get("threshold:xss") or "medium"
    }
end

-- 임계치 저장
function _M.save_thresholds(thresholds)
    local red = get_redis()
    if not red then
        return {success = false, message = "Redis 연결 실패"}
    end
    
    red:set("threshold:rate_limit", thresholds.rate_limit)
    red:set("threshold:threat_score", thresholds.threat_score)
    red:set("threshold:ddos", thresholds.ddos)
    red:set("threshold:sql_injection", thresholds.sql_injection)
    red:set("threshold:xss", thresholds.xss)
    
    return {success = true, message = "임계치 저장됨"}
end

-- API 요청 처리
function _M.handle_request()
    local uri = ngx.var.request_uri
    local method = ngx.var.request_method
    
    -- 요청 본문 읽기
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    local data = nil
    if body then
        data = cjson.decode(body)
    end
    
    -- 응답 헤더 설정
    ngx.header.content_type = "application/json"
    
    -- API 엔드포인트 라우팅
    if uri == "/admin/api/stats" and method == "GET" then
        local stats = _M.get_stats()
        ngx.say(cjson.encode(stats))
    
    elseif uri == "/admin/api/blocked-ips" and method == "GET" then
        local blocked = _M.get_blocked_ips()
        ngx.say(cjson.encode(blocked))
    
    elseif uri == "/admin/api/unblock" and method == "POST" then
        local result = _M.unblock_ip(data.ip)
        ngx.say(cjson.encode(result))
    
    elseif uri == "/admin/api/block-ip" and method == "POST" then
        local result = _M.block_ip(data.ip, data.reason, data.duration)
        ngx.say(cjson.encode(result))
    
    elseif uri == "/admin/api/whitelist" and method == "GET" then
        local whitelist = _M.get_whitelist()
        ngx.say(cjson.encode(whitelist))
    
    elseif uri == "/admin/api/add-whitelist" and method == "POST" then
        local result = _M.add_whitelist(data.ip, data.reason, tonumber(data.expiry))
        ngx.say(cjson.encode(result))
    
    elseif uri == "/admin/api/remove-whitelist" and method == "POST" then
        local result = _M.remove_whitelist(data.ip)
        ngx.say(cjson.encode(result))
    
    elseif uri == "/admin/api/thresholds" and method == "GET" then
        local thresholds = _M.get_thresholds()
        ngx.say(cjson.encode(thresholds))
    
    elseif uri == "/admin/api/thresholds" and method == "POST" then
        local result = _M.save_thresholds(data)
        ngx.say(cjson.encode(result))
    
    else
        ngx.status = 404
        ngx.say(cjson.encode({error = "API 엔드포인트를 찾을 수 없습니다"}))
    end
end

return _M
