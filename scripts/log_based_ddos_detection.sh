#!/bin/bash

# access log 기반 DDOS 분석 스크립트
# Apache 또는 nginx access log를 실시간으로 분석

LOG_FILE=${1:-"/var/log/nginx/access.log"}
WINDOW=${2:-60}  # 분석 시간 윈도우 (초)
THRESHOLD=${3:-100}  # 임계치 (초당 요청 수)

echo "=== DDOS 판단 시스템 (Access Log 기반) ==="
echo "로그 파일: $LOG_FILE"
echo "분석 윈도우: ${WINDOW}초"
echo "임계치: ${THRESHOLD} req/s"
echo ""

# 최근 N초간의 IP별 요청 수 집계
analyze_log() {
    local log_file=$1
    local window=$2
    local threshold=$3
    
    # 현재 시간에서 N초 전까지의 로그 분석
    local cutoff=$(date -d "$window seconds ago" '+%d/%b/%Y:%H:%M:%S')
    
    echo "분석 시작 시간: $cutoff"
    echo ""
    
    # IP별 요청 수 집계
    awk -v cutoff="$cutoff" '
    BEGIN {
        # 시간 파싱을 위한 배열
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
        # log format: $remote_addr - $remote_user [$time_local] "$request" ...
        # 시간 추출
        match($0, /\[([^]]+)\]/, time_match)
        if (time_match[1]) {
            log_time = time_match[1]
            
            # 시간 비교 (간단한 문자열 비교)
            if (log_time >= cutoff) {
                # IP 추출
                ip = $1
                ip_count[ip]++
            }
        }
    }
    END {
        # 결과 출력
        print "IP별 요청 수:"
        for (ip in ip_count) {
            req_per_sec = ip_count[ip] / window
            print ip " : " ip_count[ip] " 요청 (" req_per_sec " req/s)"
            
            # 임계치 초과 확인
            if (req_per_sec > threshold) {
                print "  >>> DDOS 의심! <<<"
            }
        }
    }
    ' window=$window threshold=$threshold $log_file
}

# 실시간 모니터링 (tail -f)
monitor_realtime() {
    echo "실시간 모니터링 모드..."
    echo ""
    
    tail -f $LOG_FILE | while read line; do
        # IP 추출
        ip=$(echo "$line" | awk '{print $1}')
        
        # Redis에 카운트 증가
        redis-cli INCR "req_count:$ip"
        redis-cli EXPIRE "req_count:$ip" 60  # 60초 TTL
        
        # 초당 요청 수 계산
        local count=$(redis-cli GET "req_count:$ip")
        if [ $count -gt $THRESHOLD ]; then
            echo "$(date '+%H:%M:%S') - DDOS 의심: $ip (${count} req/s)"
            
            # IP 차단 (nginx 또는 Apache)
            # nginx 경우:
            #   redis-cli SET "blocked:$ip" "ddos_attack"
            
            # Apache 경우:
            #   echo "$ip DDOS 의심" >> /etc/apache2/blocked_ips.txt
        fi
    done
}

# 과거 로그 분석
analyze_historical() {
    echo "과거 로그 분석 모드..."
    echo ""
    
    local start_date=$(date -d "1 hour ago" '+%Y%m%d%H%M%S')
    
    # 최근 1시간 로그 분석
    if [ -f "${LOG_FILE}.gz" ]; then
        zcat ${LOG_FILE}.gz | grep "^$start_date" | \
            awk '{count[$1]++} END {for (ip in count) print ip " : " count[ip] " requests"}'
    fi
    
    # 현재 로그 분석
    if [ -f "$LOG_FILE" ]; then
        awk '{count[$1]++} END {
            for (ip in count) {
                req_per_sec = count[ip] / 60  # 1분 기준
                if (req_per_sec > 100) {
                    print ip " : " count[ip] " requests (" req_per_sec " req/s) [DDOS 의심]"
                }
            }
        }' $LOG_FILE
    fi
}

# 메인 실행
case "${1:-analyze}" in
    "monitor")
        monitor_realtime
        ;;
    "analyze")
        analyze_log "$LOG_FILE" "$WINDOW" "$THRESHOLD"
        ;;
    "historical")
        analyze_historical
        ;;
    *)
        echo "사용법: $0 {monitor|analyze|historical}"
        echo ""
        echo "  monitor    - 실시간 모니터링 (tail -f)"
        echo "  analyze    - 로그 파일 분석"
        echo "  historical - 과거 로그 분석"
        ;;
esac
