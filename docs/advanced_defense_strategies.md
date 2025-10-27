# nginx 능동방어 시스템 개선안
# 대역폭 효율적 능동방어 전략

# 현재 문제점:
# - 단순 403/444 차단은 공격자가 계속 요청을 보내면 대역폭 소모
# - 차단된 IP도 HTTP 요청/응답을 처리해야 함 (CPU, 메모리 사용)

# 개선 전략:

## 1. 초기 단계에서 빠른 차단 (Early Rejection)
# - Lua에서 요청을 분석하기 전에 nginx map을 사용하여 빠르게 차단
# - 스테이터스 코드 429 (Too Many Requests) 사용
map $remote_addr $block_reason {
    default "";
    # 차단된 IP는 즉시 429로 처리 (map에서 처리되므로 Lua 오버헤드 없음)
    # include /etc/nginx/blocked_ips.conf; # 동적 차단 목록
}

# map을 이용한 빠른 차단
map $block_reason $should_reject {
    "" 0;
    default 1;
}

server {
    listen 80;
    server_name your-domain.com;
    
    # map 기반 빠른 차단 (Lua 실행 전)
    if ($should_reject) {
        return 429 "Too Many Requests";
    }
    
    # 이후 Lua 스크립트 실행
    access_by_lua_block {
        local advanced = require "advanced_defense"
        advanced.smart_defense()
    }
}

## 2. 444 사용 (Connection Closed - 대역폭 소비 제로)
# 444는 연결을 즉시 종료하므로 HTTP 응답을 보낼 필요 없음
server {
    location / {
        access_by_lua_block {
            local defense = require "advanced_defense"
            local is_malicious = defense.check_threat()
            
            if is_malicious then
                ngx.status = 444 -- 즉시 연결 종료 (대역폭 소비 제로)
                ngx.exit(444)
            end
        }
        
        proxy_pass http://backend;
    }
}

## 3. 작은 응답으로 타임아웃 생성
# 큰 응답 대신 작은 응답으로 공격자의 시간 소모
server {
    location / {
        access_by_lua_block {
            local client_ip = ngx.var.remote_addr
            local freq = check_frequency(client_ip)
            
            if freq > 100 then
                -- 초기 연결 후 느린 응답 (공격자 리소스 소모)
                ngx.sleep(10) -- 10초 대기
                ngx.status = 503
                ngx.header["X-RateLimit"] = "true"
                ngx.say("{}") -- 최소한의 JSON 응답 (100 bytes 미만)
                ngx.exit(503)
            end
        }
        
        proxy_pass http://backend;
    }
}

## 4. Honey Token (가짜 취약 페이지)
# 공격자를 허위 정보로 유도, 실제 취약점은 없음
server {
    # 실제 관리 페이지는 다른 곳에
    location /admin/ {
        access_by_lua_block {
            local client_ip = ngx.var.remote_addr
            
            -- 의심스러운 IP에게 가짜 페이지 제공
            if is_suspicious(client_ip) then
                ngx.status = 200
                ngx.header.content_type = "text/html"
                ngx.say("<html><body><h1>Login</h1><form method='post'><input type='text' name='user'><input type='password' name='pass'><button>Login</button></form></body></html>")
                ngx.log(ngx.WARN, "Honey token accessed by " .. client_ip)
                ngx.exit(200)
            end
        }
        
        return 404; # 정상 IP는 404
    }
}

## 5. IP Reputation 기반 차등 대응
# 좋은 IP: 빠른 응답, 나쁜 IP: 느린 응답 또는 차단
map $remote_addr $ip_reputation {
    default 50; # 중립
    # 좋은 IP들 (화이트리스트)
    include /etc/nginx/good_ips.conf;
    # 나쁜 IP들 (차단 목록)
    include /etc/nginx/bad_ips.conf;
}

server {
    location / {
        # 평판에 따른 차등 처리
        if ($ip_reputation < 20) {
            return 444; # 나쁜 IP: 즉시 차단
        }
        
        access_by_lua_block {
            local reputation = tonumber(ngx.var.ip_reputation)
            
            -- 평판에 따라 응답 시간 조절
            if reputation < 50 then
                ngx.sleep(3) -- 나쁜 IP: 3초 대기
            elseif reputation < 70 then
                ngx.sleep(1) -- 보통 IP: 1초 대기
            end
            -- 좋은 IP: 대기 없음
        }
        
        proxy_pass http://backend;
    }
}

## 6. Shadow Ban (명시적 차단 안 하고 타임아웃)
# 사용자가 차단 당한 것을 모르게 하여 계속 요청 보내게 함
server {
    location / {
        access_by_lua_block {
            local client_ip = ngx.var.remote_addr
            
            if is_shadow_banned(client_ip) then
                ngx.sleep(60) -- 60초 대기 (공격자 리소스 소모)
                ngx.status = 504
                ngx.exit(504)
            end
        }
        
        proxy_pass http://backend;
    }
}

## 7. 대역폭 보호: 작은 크기의 fake API 응답
# API 공격 시 큰 JSON 대신 작은 stub 응답
location /api/ {
    access_by_lua_block {
        local client_ip = ngx.var.remote_addr
        
        if is_attacking_api(client_ip) then
            ngx.status = 200
            ngx.header.content_type = "application/json"
            ngx.say("{\"status\":\"ok\"}") -- 15 bytes
            ngx.exit(200)
            -- 실제 API 호출 안 함
        end
    }
    
    proxy_pass http://backend;
}

## 8. 무효 요청으로 리소스 소모
# 공격자가 유효한 응답을 받지 못하게 하고 CPU만 사용
location / {
    access_by_lua_block {
        local client_ip = ngx.var.remote_addr
        
        if is_malicious(client_ip) then
            -- CPU 집약적인 작업 (공격자의 CPU 소모)
            local sum = 0
            for i = 1, 1000000 do
                sum = sum + i
            end
            
            ngx.status = 200
            ngx.say(tostring(sum))
            ngx.exit(200)
        end
    }
    
    proxy_pass http://backend;
}
