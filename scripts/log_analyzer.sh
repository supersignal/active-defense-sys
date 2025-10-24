#!/bin/bash

# nginx 능동방어 시스템 로그 분석 스크립트
# 실시간 보안 위협 분석 및 알림

LOG_DIR="/var/log/nginx"
SECURITY_LOG="$LOG_DIR/security.log"
ACCESS_LOG="$LOG_DIR/access.log"
ANALYSIS_LOG="/var/log/nginx-defense-analysis.log"
ALERT_LOG="/var/log/nginx-defense-alerts.log"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $ANALYSIS_LOG
}

# 알림 함수
send_alert() {
    local level=$1
    local message=$2
    local ip=$3
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message - IP: $ip" >> $ALERT_LOG
    
    case $level in
        "CRITICAL")
            echo -e "${RED}[CRITICAL]${NC} $message - IP: $ip"
            # 이메일 알림 (선택사항)
            # echo "CRITICAL: $message - IP: $ip" | mail -s "nginx 보안 위험" admin@yourdomain.com
            ;;
        "HIGH")
            echo -e "${YELLOW}[HIGH]${NC} $message - IP: $ip"
            ;;
        "MEDIUM")
            echo -e "${BLUE}[MEDIUM]${NC} $message - IP: $ip"
            ;;
    esac
}

# IP 위험도 분석
analyze_ip_threat() {
    local ip=$1
    local time_window=${2:-3600} # 기본 1시간
    
    # 최근 1시간 내 요청 수
    local request_count=$(grep "$ip" $ACCESS_LOG | awk -v start=$(date -d "1 hour ago" '+%d/%b/%Y:%H:%M:%S') '
        BEGIN { count = 0 }
        $4 >= "[" start { count++ }
        END { print count }
    ')
    
    # 차단된 요청 수
    local blocked_count=$(grep "blocked=1.*$ip" $SECURITY_LOG | wc -l)
    
    # 의심스러운 요청 패턴
    local suspicious_patterns=$(grep "$ip" $ACCESS_LOG | grep -E "(admin|wp-admin|phpmyadmin|\.php|\.asp|\.jsp)" | wc -l)
    
    # User-Agent 분석
    local bot_patterns=$(grep "$ip" $ACCESS_LOG | grep -E "(bot|crawler|spider|scanner)" | wc -l)
    
    # 위험도 점수 계산
    local threat_score=0
    
    if [ $request_count -gt 1000 ]; then
        threat_score=$((threat_score + 30))
    elif [ $request_count -gt 500 ]; then
        threat_score=$((threat_score + 20))
    elif [ $request_count -gt 100 ]; then
        threat_score=$((threat_score + 10))
    fi
    
    if [ $blocked_count -gt 10 ]; then
        threat_score=$((threat_score + 40))
    elif [ $blocked_count -gt 5 ]; then
        threat_score=$((threat_score + 25))
    elif [ $blocked_count -gt 0 ]; then
        threat_score=$((threat_score + 10))
    fi
    
    if [ $suspicious_patterns -gt 5 ]; then
        threat_score=$((threat_score + 30))
    elif [ $suspicious_patterns -gt 0 ]; then
        threat_score=$((threat_score + 15))
    fi
    
    if [ $bot_patterns -gt 3 ]; then
        threat_score=$((threat_score + 20))
    fi
    
    echo $threat_score
}

# 실시간 로그 모니터링
monitor_realtime() {
    log_message "실시간 보안 모니터링 시작"
    
    tail -f $SECURITY_LOG | while read line; do
        if echo "$line" | grep -q "blocked=1"; then
            local ip=$(echo "$line" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
            local reason=$(echo "$line" | grep -o 'reason="[^"]*"' | sed 's/reason="//;s/"//')
            local threat_level=$(echo "$line" | grep -o 'threat_level="[^"]*"' | sed 's/threat_level="//;s/"//')
            
            case $threat_level in
                "critical")
                    send_alert "CRITICAL" "위험도 높은 공격 감지: $reason" "$ip"
                    ;;
                "high")
                    send_alert "HIGH" "높은 위험도 공격 감지: $reason" "$ip"
                    ;;
                "medium")
                    send_alert "MEDIUM" "중간 위험도 공격 감지: $reason" "$ip"
                    ;;
            esac
        fi
    done
}

# 일일 보안 리포트 생성
generate_daily_report() {
    local report_date=$(date '+%Y-%m-%d')
    local report_file="/var/log/nginx-defense-report-$report_date.txt"
    
    log_message "일일 보안 리포트 생성: $report_file"
    
    {
        echo "=== nginx 능동방어 시스템 일일 보안 리포트 ==="
        echo "생성일: $report_date"
        echo ""
        
        echo "=== 요약 통계 ==="
        echo "총 요청 수: $(wc -l < $ACCESS_LOG)"
        echo "차단된 요청 수: $(grep "blocked=1" $SECURITY_LOG | wc -l)"
        echo "고유 IP 수: $(awk '{print $1}' $ACCESS_LOG | sort -u | wc -l)"
        echo ""
        
        echo "=== 위험도별 통계 ==="
        echo "Critical 위험: $(grep 'threat_level="critical"' $SECURITY_LOG | wc -l)"
        echo "High 위험: $(grep 'threat_level="high"' $SECURITY_LOG | wc -l)"
        echo "Medium 위험: $(grep 'threat_level="medium"' $SECURITY_LOG | wc -l)"
        echo "Low 위험: $(grep 'threat_level="low"' $SECURITY_LOG | wc -l)"
        echo ""
        
        echo "=== 상위 공격 IP (Top 10) ==="
        grep "blocked=1" $SECURITY_LOG | awk '{print $1}' | sort | uniq -c | sort -nr | head -10
        echo ""
        
        echo "=== 공격 유형별 통계 ==="
        grep "blocked=1" $SECURITY_LOG | grep -o 'reason="[^"]*"' | sed 's/reason="//;s/"//' | sort | uniq -c | sort -nr
        echo ""
        
        echo "=== 시간대별 공격 분포 ==="
        grep "blocked=1" $SECURITY_LOG | awk '{print $4}' | sed 's/\[//' | cut -d: -f2 | sort | uniq -c | sort -nr
        echo ""
        
        echo "=== 의심스러운 User-Agent (Top 10) ==="
        grep "blocked=1" $SECURITY_LOG | grep -o '"http_user_agent":"[^"]*"' | sed 's/"http_user_agent":"//;s/"//' | sort | uniq -c | sort -nr | head -10
        echo ""
        
        echo "=== 권장사항 ==="
        local critical_count=$(grep 'threat_level="critical"' $SECURITY_LOG | wc -l)
        if [ $critical_count -gt 10 ]; then
            echo "- Critical 위험이 높습니다. 추가 보안 조치가 필요합니다."
        fi
        
        local unique_ips=$(awk '{print $1}' $ACCESS_LOG | sort -u | wc -l)
        if [ $unique_ips -gt 1000 ]; then
            echo "- 접근하는 고유 IP가 많습니다. Rate Limiting 설정을 검토하세요."
        fi
        
        echo "- 정기적인 로그 분석을 통해 새로운 공격 패턴을 파악하세요."
        echo "- 차단된 IP 목록을 정기적으로 검토하고 화이트리스트를 관리하세요."
        
    } > $report_file
    
    log_message "일일 보안 리포트 생성 완료: $report_file"
}

# IP 화이트리스트 관리
manage_whitelist() {
    local whitelist_file="/etc/nginx/whitelist.conf"
    
    # 신뢰할 수 있는 IP 목록 (예시)
    local trusted_ips=(
        "127.0.0.1"
        "192.168.1.0/24"
        "10.0.0.0/8"
    )
    
    {
        echo "# 자동 생성된 화이트리스트"
        echo "# 생성일: $(date)"
        echo ""
        
        for ip in "${trusted_ips[@]}"; do
            echo "allow $ip;"
        done
        
        echo "deny all;"
        
    } > $whitelist_file
    
    log_message "화이트리스트 업데이트 완료: $whitelist_file"
}

# 성능 분석
analyze_performance() {
    log_message "성능 분석 시작"
    
    # 응답 시간 분석
    local avg_response_time=$(awk '{print $NF}' $ACCESS_LOG | grep -E '^[0-9]+\.[0-9]+$' | awk '{sum+=$1; count++} END {print sum/count}')
    
    # 상태 코드 분포
    local status_codes=$(awk '{print $9}' $ACCESS_LOG | sort | uniq -c | sort -nr)
    
    # 상위 요청 경로
    local top_paths=$(awk '{print $7}' $ACCESS_LOG | sort | uniq -c | sort -nr | head -10)
    
    log_message "평균 응답 시간: ${avg_response_time}초"
    log_message "상태 코드 분포: $status_codes"
    log_message "상위 요청 경로: $top_paths"
}

# 메인 함수
main() {
    case "${1:-monitor}" in
        "monitor")
            monitor_realtime
            ;;
        "report")
            generate_daily_report
            ;;
        "whitelist")
            manage_whitelist
            ;;
        "performance")
            analyze_performance
            ;;
        "analyze")
            local ip=${2:-""}
            if [ -n "$ip" ]; then
                local threat_score=$(analyze_ip_threat "$ip")
                log_message "IP $ip의 위험도 점수: $threat_score"
            else
                log_message "분석할 IP 주소를 입력하세요."
            fi
            ;;
        *)
            echo "사용법: $0 {monitor|report|whitelist|performance|analyze <ip>}"
            echo ""
            echo "  monitor     - 실시간 보안 모니터링"
            echo "  report      - 일일 보안 리포트 생성"
            echo "  whitelist   - 화이트리스트 업데이트"
            echo "  performance - 성능 분석"
            echo "  analyze     - 특정 IP 위험도 분석"
            ;;
    esac
}

# 스크립트 실행
main "$@"
