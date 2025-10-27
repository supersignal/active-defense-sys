#!/bin/bash

# 고속 반복 공격 감지 및 차단
# 같은 IP에서 같은 페이지를 초당 5000-10000회 호출하는 공격 감지

REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"

# 임계치 설정
LOW_THRESHOLD=1000   # 1000 TPS 이상 - 경고
MID_THRESHOLD=5000   # 5000 TPS 이상 - 주의
HIGH_THRESHOLD=10000 # 10000 TPS 이상 - 즉시 차단

# Redis 연결 테스트
test_redis() {
    if ! redis-cli -h $REDIS_HOST -p $REDIS_PORT ping > /dev/null 2>&1; then
        echo "Redis 연결 실패: $REDIS_HOST:$REDIS_PORT"
        exit 1
    fi
}

# 로그 파일 모니터링
monitor_log_file() {
    local log_file=${1:-/var/log/nginx/access.log}
    
    echo "=== 고속 공격 모니터링 시작 ==="
    echo "로그 파일: $log_file"
    echo "임계치: $LOW_THRESHOLD (경고) / $MID_THRESHOLD (주의) / $HIGH_THRESHOLD (즉시차단) TPS"
    echo ""
    
    # tail -f로 실시간 모니터링
    tail -f "$log_file" | while read line; do
        # IP 추출
        ip=$(echo "$line" | awk '{print $1}')
        
        # URI 추출
        uri=$(echo "$line" | grep -oP '"[^"]+"' | awk '{print $2}' | cut -d'?' -f1)
        
        if [ -n "$ip" ] && [ -n "$uri" ]; then
            # Redis에 카운트 증가 (1초 윈도우)
            local key="highspeed:${ip}:${uri}"
            
            redis-cli -h $REDIS_HOST -p $REDIS_PORT INCR "$key"
            redis-cli -h $REDIS_HOST -p $REDIS_PORT EXPIRE "$key" 1  # 1초 TTL
            
            # 현재 호출 수 확인
            local count=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT GET "$key")
            
            if [ $count ] && [ $count -ge $HIGH_THRESHOLD ]; then
                echo "$(date '+%H:%M:%S') - 🚨 즉시 차단: IP $ip → $uri ($count TPS) - 초고속 공격!"
                # 즉시 차단
                redis-cli -h $REDIS_HOST -p $REDIS_PORT SETEX "blocked:$ip" 3600 "high_speed_attack:$uri"
                
            elif [ $count ] && [ $count -ge $MID_THRESHOLD ]; then
                echo "$(date '+%H:%M:%S') - ⚠️ 주의: IP $ip → $uri ($count TPS)"
                
            elif [ $count ] && [ $count -ge $LOW_THRESHOLD ]; then
                echo "$(date '+%H:%M:%S') - ⚡ 경고: IP $ip → $uri ($count TPS)"
            fi
        fi
    done
}

# 최근 로그 분석
analyze_recent_logs() {
    local log_file=${1:-/var/log/nginx/access.log}
    local window=${2:-60}  # 분석 윈도우 (초)
    
    echo "=== 최근 ${window}초 로그 분석 ==="
    echo ""
    
    # IP+URI별 요청 수 집계
    awk -v window="$window" '
    {
        ip = $1
        # URI 추출
        match($0, /"[^"]*"/, request)
        split(request[0], parts, " ")
        uri = parts[2]
        gsub(/\?.*/, "", uri)  # 쿼리 파라미터 제거
        
        key = ip "|" uri
        count[key]++
        ip_info[key] = ip
        uri_info[key] = uri
    }
    END {
        print "IP별 페이지별 호출 수:"
        print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        for (key in count) {
            ip = ip_info[key]
            uri = uri_info[key]
            req_per_sec = count[key] / window
            
            if (req_per_sec >= 10000) {
                print "🚨 " ip " → " uri " : " count[key] " 호출 (" req_per_sec " TPS) [즉시차단]"
            } else if (req_per_sec >= 5000) {
                print "⚠️  " ip " → " uri " : " count[key] " 호출 (" req_per_sec " TPS) [주의]"
            } else if (req_per_sec >= 1000) {
                print "⚡ " ip " → " uri " : " count[key] " 호출 (" req_per_sec " TPS)"
            }
        }
    }
    ' "$log_file"
}

# 특정 IP의 상세 정보
show_ip_details() {
    local ip=$1
    local log_file=${2:-/var/log/nginx/access.log}
    
    echo "=== IP $ip의 상세 정보 ==="
    echo ""
    
    # 최근 호출 패턴
    grep "^$ip " "$log_file" | tail -20 | while read line; do
        time=$(echo "$line" | awk '{print $4}' | tr -d '[]')
        uri=$(echo "$line" | grep -oP '"[^"]+"' | awk '{print $2}')
        status=$(echo "$line" | awk '{print $9}')
        
        echo "$time | $status | $uri"
    done
    
    echo ""
    echo "통계:"
    grep "^$ip " "$log_file" | awk '
    {
        match($0, /"[^"]*"/, request)
        split(request[0], parts, " ")
        uri = parts[2]
        gsub(/\?.*/, "", uri)
        
        uri_count[uri]++
        status = $9
        status_count[status]++
        total++
    }
    END {
        print "총 요청: " total
        
        # URI별 집계
        print ""
        print "페이지별 호출:"
        for (uri in uri_count) {
            if (uri_count[uri] > 10) {
                print "  " uri " : " uri_count[uri] " 회"
            }
        }
        
        # 상태별 집계
        print ""
        print "상태 코드별:"
        for (status in status_count) {
            print "  " status " : " status_count[status] " 회"
        }
    }
    '
}

# 메인 실행
main() {
    case "${1:-analyze}" in
        "monitor")
            test_redis
            monitor_log_file "$2"
            ;;
        "analyze")
            analyze_recent_logs "$2" "$3"
            ;;
        "ip")
            if [ -z "$2" ]; then
                echo "사용법: $0 ip <IP_ADDRESS>"
                exit 1
            fi
            show_ip_details "$2" "$3"
            ;;
        *)
            echo "사용법: $0 {monitor|analyze|ip <IP>}"
            echo ""
            echo "  monitor             - 실시간 모니터링 (tail -f)"
            echo "  analyze [log] [time] - 최근 로그 분석"
            echo "  ip <IP>            - 특정 IP 상세 정보"
            ;;
    esac
}

# 실행
main "$@"