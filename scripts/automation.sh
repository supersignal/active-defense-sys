#!/bin/bash

# nginx 능동방어 시스템 자동화 스크립트
# 시스템 관리 및 유지보수 자동화

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nginx-defense-automation.log"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 로그 함수
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# 에러 처리 함수
handle_error() {
    local exit_code=$1
    local message=$2
    if [ $exit_code -ne 0 ]; then
        log_message "ERROR: $message (Exit code: $exit_code)"
        exit $exit_code
    fi
}

# 시스템 상태 확인
check_system_status() {
    log_message "시스템 상태 확인 시작"
    
    # nginx 상태 확인
    if systemctl is-active --quiet nginx; then
        log_message "nginx 서비스: 실행 중"
    else
        log_message "nginx 서비스: 중지됨"
        return 1
    fi
    
    # Redis 상태 확인
    if systemctl is-active --quiet redis; then
        log_message "Redis 서비스: 실행 중"
    else
        log_message "Redis 서비스: 중지됨"
        return 1
    fi
    
    # 디스크 공간 확인
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ $disk_usage -gt 80 ]; then
        log_message "경고: 디스크 사용률이 ${disk_usage}%입니다"
    else
        log_message "디스크 사용률: ${disk_usage}%"
    fi
    
    # 메모리 사용률 확인
    local memory_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    log_message "메모리 사용률: ${memory_usage}%"
    
    # 로그 파일 크기 확인
    local security_log_size=$(du -h /var/log/nginx/security.log 2>/dev/null | cut -f1)
    local access_log_size=$(du -h /var/log/nginx/access.log 2>/dev/null | cut -f1)
    log_message "보안 로그 크기: $security_log_size"
    log_message "접근 로그 크기: $access_log_size"
}

# 설정 파일 검증
validate_config() {
    log_message "nginx 설정 파일 검증 시작"
    
    # nginx 설정 문법 검사
    if nginx -t 2>/dev/null; then
        log_message "nginx 설정 파일: 유효함"
    else
        log_message "nginx 설정 파일: 오류 발견"
        nginx -t 2>&1 | tee -a $LOG_FILE
        return 1
    fi
    
    # Lua 스크립트 파일 존재 확인
    local lua_files=("defense.lua" "admin_api.lua")
    for file in "${lua_files[@]}"; do
        if [ -f "/etc/nginx/lua/$file" ]; then
            log_message "Lua 스크립트 $file: 존재함"
        else
            log_message "Lua 스크립트 $file: 누락됨"
            return 1
        fi
    done
    
    # 관리 인터페이스 파일 확인
    if [ -f "/var/www/admin/index.html" ]; then
        log_message "관리 인터페이스: 존재함"
    else
        log_message "관리 인터페이스: 누락됨"
        return 1
    fi
}

# 로그 로테이션 실행
rotate_logs() {
    log_message "로그 로테이션 실행"
    
    # 수동 로그 로테이션
    if [ -f "/var/log/nginx/access.log" ]; then
        mv /var/log/nginx/access.log /var/log/nginx/access.log.$(date +%Y%m%d_%H%M%S)
        touch /var/log/nginx/access.log
        chown nginx:nginx /var/log/nginx/access.log
        log_message "접근 로그 로테이션 완료"
    fi
    
    if [ -f "/var/log/nginx/security.log" ]; then
        mv /var/log/nginx/security.log /var/log/nginx/security.log.$(date +%Y%m%d_%H%M%S)
        touch /var/log/nginx/security.log
        chown nginx:nginx /var/log/nginx/security.log
        log_message "보안 로그 로테이션 완료"
    fi
    
    # nginx 재시작 (로그 파일 핸들 새로고침)
    systemctl reload nginx
    handle_error $? "nginx 리로드 실패"
}

# 백업 생성
create_backup() {
    local backup_dir="/backup/nginx-defense"
    local backup_name="nginx-defense-backup-$(date +%Y%m%d_%H%M%S)"
    local backup_path="$backup_dir/$backup_name"
    
    log_message "백업 생성 시작: $backup_path"
    
    # 백업 디렉토리 생성
    mkdir -p "$backup_path"
    
    # nginx 설정 백업
    if [ -d "/etc/nginx" ]; then
        cp -r /etc/nginx "$backup_path/"
        log_message "nginx 설정 백업 완료"
    fi
    
    # Lua 스크립트 백업
    if [ -d "/etc/nginx/lua" ]; then
        cp -r /etc/nginx/lua "$backup_path/"
        log_message "Lua 스크립트 백업 완료"
    fi
    
    # 관리 인터페이스 백업
    if [ -d "/var/www/admin" ]; then
        cp -r /var/www/admin "$backup_path/"
        log_message "관리 인터페이스 백업 완료"
    fi
    
    # Redis 데이터 백업
    if systemctl is-active --quiet redis; then
        redis-cli BGSAVE
        sleep 2
        if [ -f "/var/lib/redis/dump.rdb" ]; then
            cp /var/lib/redis/dump.rdb "$backup_path/redis-dump.rdb"
            log_message "Redis 데이터 백업 완료"
        fi
    fi
    
    # 백업 압축
    cd "$backup_dir"
    tar -czf "${backup_name}.tar.gz" "$backup_name"
    rm -rf "$backup_name"
    
    log_message "백업 생성 완료: ${backup_name}.tar.gz"
}

# 오래된 백업 정리
cleanup_old_backups() {
    local backup_dir="/backup/nginx-defense"
    local retention_days=30
    
    log_message "오래된 백업 정리 시작 (${retention_days}일 이상)"
    
    if [ -d "$backup_dir" ]; then
        find "$backup_dir" -name "*.tar.gz" -mtime +$retention_days -delete
        log_message "오래된 백업 정리 완료"
    fi
}

# 보안 업데이트 확인
check_security_updates() {
    log_message "보안 업데이트 확인"
    
    # Ubuntu/Debian
    if command -v apt &> /dev/null; then
        apt update >/dev/null 2>&1
        local updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable")
        if [ $updates -gt 0 ]; then
            log_message "사용 가능한 업데이트: $updates개"
        else
            log_message "모든 패키지가 최신 상태입니다"
        fi
    fi
    
    # CentOS/RHEL
    if command -v yum &> /dev/null; then
        local updates=$(yum check-update 2>/dev/null | grep -c "updates")
        if [ $updates -gt 0 ]; then
            log_message "사용 가능한 업데이트: $updates개"
        else
            log_message "모든 패키지가 최신 상태입니다"
        fi
    fi
}

# 성능 최적화
optimize_performance() {
    log_message "성능 최적화 시작"
    
    # Redis 메모리 정리
    if systemctl is-active --quiet redis; then
        redis-cli FLUSHDB
        log_message "Redis 캐시 정리 완료"
    fi
    
    # nginx 캐시 정리
    if [ -d "/var/cache/nginx" ]; then
        rm -rf /var/cache/nginx/*
        log_message "nginx 캐시 정리 완료"
    fi
    
    # 임시 파일 정리
    find /tmp -name "nginx*" -mtime +1 -delete 2>/dev/null
    log_message "임시 파일 정리 완료"
}

# 모니터링 설정 확인
check_monitoring() {
    log_message "모니터링 설정 확인"
    
    # 로그 분석 스크립트 확인
    if [ -f "$SCRIPT_DIR/log_analyzer.sh" ]; then
        log_message "로그 분석 스크립트: 존재함"
    else
        log_message "로그 분석 스크립트: 누락됨"
    fi
    
    # 모니터링 서비스 상태 확인
    if systemctl is-active --quiet nginx-defense-monitor; then
        log_message "모니터링 서비스: 실행 중"
    else
        log_message "모니터링 서비스: 중지됨"
    fi
    
    # 로그 로테이션 설정 확인
    if [ -f "/etc/logrotate.d/nginx-defense" ]; then
        log_message "로그 로테이션 설정: 존재함"
    else
        log_message "로그 로테이션 설정: 누락됨"
    fi
}

# 일일 유지보수 작업
daily_maintenance() {
    log_message "일일 유지보수 작업 시작"
    
    check_system_status
    validate_config
    optimize_performance
    check_monitoring
    
    # 매일 자정에 백업 생성
    if [ "$(date +%H)" = "00" ]; then
        create_backup
        cleanup_old_backups
    fi
    
    log_message "일일 유지보수 작업 완료"
}

# 주간 유지보수 작업
weekly_maintenance() {
    log_message "주간 유지보수 작업 시작"
    
    daily_maintenance
    check_security_updates
    
    # 주간 로그 로테이션
    if [ "$(date +%u)" = "1" ]; then # 월요일
        rotate_logs
    fi
    
    log_message "주간 유지보수 작업 완료"
}

# 메인 함수
main() {
    case "${1:-daily}" in
        "daily")
            daily_maintenance
            ;;
        "weekly")
            weekly_maintenance
            ;;
        "backup")
            create_backup
            ;;
        "rotate")
            rotate_logs
            ;;
        "status")
            check_system_status
            ;;
        "validate")
            validate_config
            ;;
        "optimize")
            optimize_performance
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        *)
            echo "사용법: $0 {daily|weekly|backup|rotate|status|validate|optimize|cleanup}"
            echo ""
            echo "  daily     - 일일 유지보수 작업"
            echo "  weekly    - 주간 유지보수 작업"
            echo "  backup    - 백업 생성"
            echo "  rotate    - 로그 로테이션"
            echo "  status    - 시스템 상태 확인"
            echo "  validate  - 설정 파일 검증"
            echo "  optimize  - 성능 최적화"
            echo "  cleanup   - 오래된 백업 정리"
            ;;
    esac
}

# 스크립트 실행
main "$@"
