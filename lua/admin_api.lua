-- 관리자 API Lua 스크립트
local json = require "cjson"
local redis = require "resty.redis"

local _M = {}

-- Redis 연결
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

-- 차단된 IP 목록 조회
function _M.get_blocked_ips()
    local blocked_ips = ngx.shared.blocked_ips
    local result = {}
    
    local keys = blocked_ips:get_keys(1000)
    for _, key in ipairs(keys) do
        local reason = blocked_ips:get(key)
        table.insert(result, {
            ip = key,
            reason = reason,
            blocked_at = os.time()
        })
    end
    
    ngx.header.content_type = "application/json"
    ngx.say(json.encode(result))
end

-- IP 차단 해제
function _M.unblock_ip()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    local data = json.decode(body)
    
    if data and data.ip then
        local blocked_ips = ngx.shared.blocked_ips
        blocked_ips:delete(data.ip)
        
        ngx.header.content_type = "application/json"
        ngx.say(json.encode({success = true, message = "IP 차단 해제됨"}))
    else
        ngx.status = 400
        ngx.say(json.encode({success = false, message = "IP 주소가 필요합니다"}))
    end
end

-- 통계 정보 조회
function _M.get_stats()
    local red = get_redis()
    if not red then
        ngx.status = 500
        ngx.say(json.encode({success = false, message = "Redis 연결 실패"}))
        return
    end
    
    local stats = {
        total_requests = red:get("total_requests") or 0,
        blocked_requests = red:get("blocked_requests") or 0,
        unique_ips = red:scard("unique_ips") or 0,
        threat_levels = {
            low = red:get("threat_low") or 0,
            medium = red:get("threat_medium") or 0,
            high = red:get("threat_high") or 0,
            critical = red:get("threat_critical") or 0
        }
    }
    
    red:close()
    
    ngx.header.content_type = "application/json"
    ngx.say(json.encode(stats))
end

-- 실시간 로그 조회
function _M.get_logs()
    local red = get_redis()
    if not red then
        ngx.status = 500
        ngx.say(json.encode({success = false, message = "Redis 연결 실패"}))
        return
    end
    
    local logs = red:lrange("security_logs", 0, 99) -- 최근 100개 로그
    red:close()
    
    ngx.header.content_type = "application/json"
    ngx.say(json.encode(logs))
end

-- API 요청 처리
function _M.handle_request()
    local uri = ngx.var.request_uri
    local method = ngx.var.request_method
    
    if uri == "/admin/api/blocked-ips" and method == "GET" then
        _M.get_blocked_ips()
    elseif uri == "/admin/api/unblock" and method == "POST" then
        _M.unblock_ip()
    elseif uri == "/admin/api/stats" and method == "GET" then
        _M.get_stats()
    elseif uri == "/admin/api/logs" and method == "GET" then
        _M.get_logs()
    else
        ngx.status = 404
        ngx.say(json.encode({success = false, message = "API 엔드포인트를 찾을 수 없습니다"}))
    end
end

return _M
