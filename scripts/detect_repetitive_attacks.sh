#!/bin/bash

# 반복적인 페이지 무한 호출 공격 감지
# 실제 사용 페이지를 같은 IP가 반복 호출할 때 감지

LOG_FILE=${1:-"/var/log/nginx/access.log"}
THRESHOLD=${2:-20}  # 같은 페이지를 N번 이상 호출 시 의심

echo "=== 반복 페이지 호출 공격 감지 ==="
echo "로그 파일: $LOG_FILE"
echo "임계치: ${THRESHOLD}회"
echo ""

# 최근 5분간 로그 분석
analyze_repetitive_patterns() {
    local log_file=$1
    local threshold=$2
    
    # 현재 시간 기준 5분 전
    local cutoff=$(date -d "5 minutes ago" '+%d/%b/%Y:%H:%M:%S')
    
    echo "분석 시작 시간: $cutoff"
    echo ""
    
    # IP + URI 조합으로 빈도 분석
    awk -v cutoff="$cutoff" -v threshold="$threshold" '
    BEGIN {
        months["Jan"] = 1
        months["Feb"] = 2
        months["Mar"] = 3
        months["Apr"] = 4
        months["May"] = 5
        months["Jun"] = 6
        months["Jul"] = 7
        months["Aug"] = 8
        months["Sep"] = 9
        months["Oct"] = 10
        months["Nov"] = 11
        months["Dec"] = 12
    }
    {
        # 시간 추출
        match($0, /\[([^]]+)\]/, time_match)
        if (time_match[1]) {
            log_time = time_match[1]
            
            # 최근 로그만 분석
            if (log_time >= cutoff) {
                # IP 추출
                ip = $1
                
                # 상태 코드 추출 (9번째 필드)
                status = $9
                
                # URI 추출 (request 필드에서)
                match($0, /"([^"]+)"/, request_match)
                if (request_match[1]) {
                    # URI만 추출 (method와 http 버전 제외)
                    request = request_match[1]
                    split(request, parts, " ")
                    uri = parts[2]
                    
                    # IP + URI 조합 (302는 별도 처리)
                    if (status == 302) {
                        # 리다이렉트는 빠진 파라미터일 수 있음
                        key = ip "|" uri "|302"
                    } else {
                        key = ip "|" uri
                    }
                    
                    count[key]++
                    
                    # 정보 저장
                    ip_info[key] = ip
                    uri_info[key] = uri
                    status_info[key] = status
                }
            }
        }
    }
    END {
        print "IP별 반복 호출 패턴:"
        print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        found = 0
        
        for (key in count) {
            if (count[key] >= threshold) {
                found = 1
                ip = ip_info[key]
                uri = uri_info[key]
                status = status_info[key]
                
                print "⚠️  IP: " ip
                print "   URI: " uri
                print "   호출 횟수: " count[key] " 회"
                print "   초당 호출: " count[key] / 300 " req/s"
                
                # 302 리다이렉트가 많으면 파라미터 누락 공격 가능성
                if (status == 302) {
                    print "   🚨 302 리다이렉트 많이 발생 - 빠진 파라미터 공격 가능!"
                }
                
                print ""
            }
        }
        
        if (!found) {
            print "정상 - 반복 호출 패턴 없음"
        }
    }
    ' $log_file
}

# Redis를 사용한 실시간 카운팅
monitor_realtime_with_redis() {
    echo "Redis 기반 실시간 모니터링..."
    echo ""
    
    tail -f $LOG_FILE | while read line; do
        # IP 추출
        ip=$(echo "$line" | awk '{print $1}')
        
        # URI 추출
        uri=$(echo "$line" | grep -oP '"[^"]+"' | awk '{print $2}')
        
        if [ -n "$ip" ] && [ -n "$uri" ]; then
            # Redis 키: "repetitive:IP:URI"
            local key="repetitive:${ip}:${uri}"
            
            # 카운트 증가
            redis-cli INCR "$key"
            redis-cli EXPIRE "$key" 300  # 5분 TTL
            
            # 임계치 초과 확인
            local count=$(redis-cli GET "$key")
            if [ $count -ge $THRESHOLD ]; then
                echo "$(date '+%H:%M:%S') - 반복 호출 공격 감지: $ip -> $uri (${count}회)"
                
                # IP 차단 (선택사항)
                # redis-cli SET "blocked:$ip" "repetitive_attack"
            fi
        fi
    done
}

# 의심 패턴 상세 분석
analyze_detailed_pattern() {
    local ip=$1
    local log_file=$2
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "IP: $ip의 상세 호출 패턴 분석"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 해당 IP의 최근 요청 추출
    grep "^$ip " $log_file | tail -20 | while read line; do
        # 시간, URI, 상태코드 추출
        time=$(echo "$line" | awk '{print $4}' | tr -d '[]')
        uri=$(echo "$line" | grep -oP '"[^"]+"' | awk '{print $2}')
        status=$(echo "$line" | awk '{print $9}')
        
        echo "$time | $status | $uri"
    done
    
    echo ""
    echo "추가 정보:"
    echo "- 총 요청 수: $(grep "^$ip " $log_file | wc -l)"
    echo "- 성공 응답: $(grep "^$ip " $log_file | awk '$9==200 {count++} END {print count}')"
    echo "- 404 오류: $(grep "^$ip " $log_file | awk '$9==404 {count++} END {print count}')"
    echo "- 403 오류: $(grep "^$ip " $log_file | awk '$9==403 {count++} END {print count}')"
}

# 메인 실행
case "${1:-analyze}" in
    "monitor")
        monitor_realtime_with_redis
        ;;
    "analyze")
        analyze_repetitive_patterns "$LOG_FILE" "$THRESHOLD"
        ;;
    "detail")
        if [ -z "$2" ]; then
            echo "사용법: $0 detail <IP_ADDRESS>"
            exit 1
        fi
        analyze_detailed_pattern "$2" "$LOG_FILE"
        ;;
    *)
        echo "사용법: $0 {monitor|analyze|detail <IP>}"
        echo ""
        echo "  monitor         - 실시간 모니터링 (Redis 사용)"
        echo "  analyze         - 최근 5분 로그 분석"
        echo "  detail <IP>     - 특정 IP의 상세 패턴 분석"
        ;;
esac
