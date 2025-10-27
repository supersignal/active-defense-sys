#!/bin/bash

# 능동방어 시스템 설치 스크립트
# Apache 또는 nginx 선택 가능 (RHEL 7/8/9 전용)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# RHEL 버전 확인
check_rhel() {
    log_info "RHEL 버전 확인 중..."
    
    if [ -f /etc/redhat-release ]; then
        RHEL_VERSION=$(cat /etc/redhat-release)
        echo "RHEL 버전: $RHEL_VERSION"
        
        if grep -q "Red Hat Enterprise Linux" /etc/redhat-release; then
            log_info "RHEL 시스템 확인됨"
        else
            log_error "이 스크립트는 RHEL용입니다"
            exit 1
        fi
    else
        log_error "/etc/redhat-release 파일을 찾을 수 없습니다"
        exit 1
    fi
}

# EPEL 저장소 활성화
enable_epel() {
    log_info "EPEL 저장소 활성화 중..."
    
    if [ "$(rpm -qa | grep -i epel)" = "" ]; then
        if command -v dnf &> /dev/null; then
            sudo dnf install -y epel-release
        elif command -v yum &> /dev/null; then
            sudo yum install -y epel-release
        fi
    else
        log_info "EPEL 이미 설치됨"
    fi
}

# 웹서버 선택
select_web_server() {
    echo ""
    echo "=========================================="
    echo "웹서버 선택"
    echo "=========================================="
    echo ""
    echo "1) Apache (mod_security)"
    echo "2) nginx (Lua 스크립트)"
    echo ""
    read -p "선택하세요 (1 또는 2): " choice
    
    case $choice in
        1)
            WEB_SERVER="apache"
            log_info "Apache 선택됨"
            ;;
        2)
            WEB_SERVER="nginx"
            log_info "nginx 선택됨"
            ;;
        *)
            log_error "잘못된 선택입니다"
            exit 1
            ;;
    esac
}

# Apache 설치
install_apache() {
    log_info "Apache 및 능동방어 모듈 설치 중..."
    
    # Apache 설치
    if ! rpm -qa | grep -q httpd; then
        sudo yum install -y httpd
    fi
    
    # ModSecurity 설치
    if [ "$(rpm -qa | grep -i mod_security)" = "" ]; then
        log_info "ModSecurity 설치 중..."
        sudo yum install -y mod_security
    fi
    
    # mod_evasive 설치 (DDoS 방어)
    if [ "$(rpm -qa | grep -i mod_evasive)" = "" ]; then
        log_info "mod_evasive 설치 중..."
        sudo yum install -y mod_evasive
    fi
    
    # mod_qos 설치
    if [ "$(rpm -qa | grep -i mod_qos)" = "" ]; then
        log_info "mod_qos 설치 중..."
        sudo yum install -y mod_qos
    fi
    
    log_info "Apache 설치 완료"
}

# Apache 설정
setup_apache() {
    log_info "Apache 능동방어 설정 중..."
    
    # 설정 파일 복사
    sudo cp apache/apache-defense.conf /etc/httpd/conf.d/defense-config.conf
    
    # ModSecurity 활성화
    sudo a2enmod security2 evasive qos
    
    # 로그 디렉토리 생성
    sudo mkdir -p /var/log/httpd/defense
    sudo mkdir -p /var/log/httpd/audit
    sudo chown -R apache:apache /var/log/httpd/
    
    log_info "Apache 설정 완료"
}

# nginx 설치
install_nginx() {
    log_info "nginx 설치 중..."
    
    if ! command -v nginx &> /dev/null; then
        # nginx 저장소 추가
        sudo tee /etc/yum.repos.d/nginx.repo << 'EOF'
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/rhel/$releasever/$basearch/
gpgcheck=0
enabled=1
EOF
        
        sudo yum install -y nginx
        log_info "nginx 설치 완료"
    else
        log_info "nginx 이미 설치됨"
    fi
}

# nginx 설정
setup_nginx() {
    log_info "nginx 능동방어 설정 중..."
    
    # 설정 파일 복사
    if [ -f nginx-defense.conf ]; then
        sudo cp nginx-defense.conf /etc/nginx/nginx.conf
    fi
    
    # Lua 스크립트 복사
    sudo mkdir -p /etc/nginx/lua
    if [ -f lua/defense.lua ]; then
        sudo cp lua/defense.lua /etc/nginx/lua/
    fi
    if [ -f lua/advanced_defense.lua ]; then
        sudo cp lua/advanced_defense.lua /etc/nginx/lua/
    fi
    if [ -f lua/admin_api.lua ]; then
        sudo cp lua/admin_api.lua /etc/nginx/lua/
    fi
    
    # 로그 디렉토리 생성
    sudo mkdir -p /var/log/nginx/defense
    sudo chown -R nginx:nginx /var/log/nginx/
    
    log_info "nginx 설정 완료"
}

# Redis 설치 (공통)
install_redis() {
    log_info "Redis 설치 중..."
    
    if ! command -v redis-cli &> /dev/null; then
        if grep -q "7\." /etc/redhat-release; then
            sudo yum install -y redis
        else
            sudo dnf install -y redis
        fi
    fi
    
    # Redis 시작 및 활성화
    sudo systemctl enable redis
    sudo systemctl start redis
    
    # 연결 테스트
    if redis-cli ping | grep -q PONG; then
        log_info "Redis 설치 및 시작 완료"
    else
        log_warn "Redis 응답 없음"
    fi
}

# 방화벽 설정
setup_firewall() {
    log_info "방화벽 설정 중..."
    
    if command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --permanent --add-service=http
        sudo firewall-cmd --permanent --add-service=https
        sudo firewall-cmd --reload
        log_info "firewalld 설정 완료"
    elif command -v iptables &> /dev/null; then
        sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        sudo service iptables save
        log_info "iptables 설정 완료"
    fi
}

# SELinux 설정
setup_selinux() {
    log_info "SELinux 설정 중..."
    
    if [ "$WEB_SERVER" = "apache" ]; then
        sudo setsebool -P httpd_can_network_connect 1
        sudo setsebool -P httpd_can_network_relay 1
    fi
    
    log_info "SELinux 설정 완료"
}

# 관리 인터페이스 설정
setup_admin_interface() {
    log_info "관리 인터페이스 설정 중..."
    
    # 관리 인터페이스 디렉토리
    sudo mkdir -p /var/www/admin
    if [ -f admin/index.html ]; then
        sudo cp admin/index.html /var/www/admin/
    fi
    
    log_info "관리 인터페이스 설정 완료"
}

# 서비스 시작
start_services() {
    log_info "서비스 시작 중..."
    
    # 선택된 웹서버 시작
    if [ "$WEB_SERVER" = "apache" ]; then
        sudo systemctl enable httpd
        sudo systemctl start httpd
        log_info "Apache 시작됨"
    elif [ "$WEB_SERVER" = "nginx" ]; then
        sudo systemctl enable nginx
        sudo systemctl start nginx
        log_info "nginx 시작됨"
    fi
    
    # Redis 시작
    sudo systemctl enable redis
    sudo systemctl start redis
    log_info "Redis 시작됨"
}

# 설치 검증
verify_installation() {
    log_info "설치 검증 중..."
    
    local success=true
    
    if [ "$WEB_SERVER" = "apache" ]; then
        if sudo systemctl is-active --quiet httpd; then
            log_info "✓ Apache 활성"
        else
            log_error "✗ Apache 비활성"
            success=false
        fi
    elif [ "$WEB_SERVER" = "nginx" ]; then
        if sudo systemctl is-active --quiet nginx; then
            log_info "✓ nginx 활성"
        else
            log_error "✗ nginx 비활성"
            success=false
        fi
    fi
    
    if redis-cli ping | grep -q PONG; then
        log_info "✓ Redis 응답"
    else
        log_error "✗ Redis 응답 없음"
        success=false
    fi
    
    if [ "$success" = true ]; then
        log_info "설치 검증 완료"
        return 0
    else
        log_error "설치 검증 실패"
        return 1
    fi
}

# 메인 실행
main() {
    echo "=========================================="
    echo "능동방어 시스템 설치 (RHEL)"
    echo "=========================================="
    echo ""
    
    check_rhel
    enable_epel
    select_web_server
    
    if [ "$WEB_SERVER" = "apache" ]; then
        install_apache
        setup_apache
    elif [ "$WEB_SERVER" = "nginx" ]; then
        install_nginx
        setup_nginx
    fi
    
    install_redis
    setup_firewall
    setup_selinux
    setup_admin_interface
    start_services
    
    if verify_installation; then
        echo ""
        echo "=========================================="
        echo "설치 완료!"
        echo "=========================================="
        echo ""
        echo "선택된 웹서버: $WEB_SERVER"
        echo ""
        echo "다음 명령어로 상태 확인:"
        if [ "$WEB_SERVER" = "apache" ]; then
            echo "  sudo systemctl status httpd"
            echo "  sudo tail -f /var/log/httpd/security.log"
        else
            echo "  sudo systemctl status nginx"
            echo "  sudo tail -f /var/log/nginx/security.log"
        fi
        echo ""
        echo "관리 인터페이스: http://your-server:8080/admin"
        echo ""
    else
        log_error "설치 검증 실패"
        exit 1
    fi
}

# 실행
main "$@"
