#!/bin/bash

# RHEL 전용 Apache 능동방어 시스템 설치 스크립트
# Red Hat Enterprise Linux 7/8/9 지원

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Apache 및 모듈 설치
install_apache_modules() {
    log_info "Apache 및 능동방어 모듈 설치 중..."
    
    # Apache 설치
    if ! rpm -qa | grep -q httpd; then
        sudo yum install -y httpd
    fi
    
    # ModSecurity 설치
    if [ "$(rpm -qa | grep -i mod_security)" = "" ]; then
        log_info "ModSecurity 설치 중..."
        sudo yum install -y mod_security
    else
        log_info "ModSecurity 이미 설치됨"
    fi
    
    # mod_evasive 설치 (DDoS 방어)
    if [ "$(rpm -qa | grep -i mod_evasive)" = "" ]; then
        log_info "mod_evasive 설치 중..."
        sudo yum install -y mod_evasive
    else
        log_info "mod_evasive 이미 설치됨"
    fi
    
    # mod_qos 설치 (Quality of Service)
    if [ "$(rpm -qa | grep -i mod_qos)" = "" ]; then
        log_info "mod_qos 설치 중..."
        sudo yum install -y mod_qos
    else
        log_info "mod_qos 이미 설치됨"
    fi
}

# ModSecurity 규칙 다운로드
setup_modsecurity_rules() {
    log_info "ModSecurity 규칙 설정 중..."
    
    # OWASP ModSecurity Core Rule Set 다운로드
    if [ ! -d /etc/httpd/modsecurity.d ]; then
        sudo mkdir -p /etc/httpd/modsecurity.d
    fi
    
    # ModSecurity 기본 설정
    if [ ! -f /etc/httpd/modsecurity.d/modsecurity.conf ]; then
        sudo cp /etc/httpd/conf.d/mod_security.conf /etc/httpd/modsecurity.d/
        log_info "ModSecurity 설정 파일 복사됨"
    fi
    
    # Apache 설정 파일 복사
    if [ -f apache/apache-defense.conf ]; then
        sudo cp apache/apache-defense.conf /etc/httpd/conf.d/defense-config.conf
        log_info "능동방어 설정 파일 복사됨"
    else
        log_warn "apache-defense.conf 파일을 찾을 수 없습니다"
    fi
}

# nginx 설치 (RHEL용)
install_nginx() {
    log_info "nginx 설치 중..."
    
    if ! command -v nginx &> /dev/null; then
        # RHEL용 nginx 저장소 추가
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
    
    # nginx Lua 모듈 설치
    if [ "$(rpm -qa | grep -i openresty)" = "" ]; then
        log_info "nginx Lua 모듈을 위한 openresty 확인 중..."
        # RHEL 8+는 openresty를 사용
        if [ -f /etc/os-release ]; then
            VERSION_ID=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
            if [[ "$VERSION_ID" == "8"* ]] || [[ "$VERSION_ID" == "9"* ]]; then
                sudo dnf install -y lua-resty-core
            fi
        fi
    fi
}

# Redis 설치
install_redis() {
    log_info "Redis 설치 중..."
    
    if ! command -v redis-cli &> /dev/null; then
        # RHEL 7/8용 Redis 설치
        if grep -q "7\." /etc/redhat-release; then
            # RHEL 7은 EPEL에서 설치
            sudo yum install -y redis
        else
            # RHEL 8+는 기본 저장소에서
            sudo dnf install -y redis
        fi
    else
        log_info "Redis 이미 설치됨"
    fi
    
    # Redis 시작 및 활성화
    sudo systemctl enable redis
    sudo systemctl start redis
    log_info "Redis 서비스 시작됨"
}

# 방화벽 설정
setup_firewall() {
    log_info "방화벽 설정 중..."
    
    if command -v firewall-cmd &> /dev/null; then
        # firewalld 사용 (RHEL 7+)
        sudo firewall-cmd --permanent --add-service=http
        sudo firewall-cmd --permanent --add-service=https
        sudo firewall-cmd --reload
        log_info "firewall-cmd 설정 완료"
    elif command -v iptables &> /dev/null; then
        # iptables 사용 (레거시)
        sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
        sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        sudo service iptables save
        log_info "iptables 설정 완료"
    fi
}

# 서비스 시작
start_services() {
    log_info "서비스 시작 중..."
    
    # Apache 시작
    sudo systemctl enable httpd
    sudo systemctl start httpd
    log_info "Apache 시작됨"
    
    # nginx 시작
    sudo systemctl enable nginx
    sudo systemctl start nginx
    log_info "nginx 시작됨"
    
    # Redis 시작
    sudo systemctl enable redis
    sudo systemctl start redis
    log_info "Redis 시작됨"
    
    # 서비스 상태 확인
    log_info "서비스 상태 확인:"
    sudo systemctl status httpd --no-pager -l
    sudo systemctl status nginx --no-pager -l
    sudo systemctl status redis --no-pager -l
}

# SELinux 설정 (RHEL 필수)
setup_selinux() {
    log_info "SELinux 설정 중..."
    
    # Apache가 네트워크 접근 허용
    sudo setsebool -P httpd_can_network_connect 1
    sudo setsebool -P httpd_can_network_relay 1
    
    # nginx가 네트워크 접근 허용 (nginx는 기본적으로 허용됨)
    
    log_info "SELinux 설정 완료"
}

# 로그 디렉토리 생성
setup_logs() {
    log_info "로그 디렉토리 생성 중..."
    
    # Apache 로그
    sudo mkdir -p /var/log/httpd/defense
    sudo mkdir -p /var/log/httpd/audit
    sudo chown -R apache:apache /var/log/httpd/
    
    # nginx 로그는 기본 위치 사용
    sudo mkdir -p /var/log/nginx/defense
    sudo chown -R nginx:nginx /var/log/nginx/
    
    log_info "로그 디렉토리 생성 완료"
}

# 설치 검증
verify_installation() {
    log_info "설치 검증 중..."
    
    # Apache 테스트
    if sudo systemctl is-active --quiet httpd; then
        log_info "✓ Apache 활성"
    else
        log_error "✗ Apache 비활성"
        return 1
    fi
    
    # nginx 테스트
    if sudo systemctl is-active --quiet nginx; then
        log_info "✓ nginx 활성"
    else
        log_error "✗ nginx 비활성"
        return 1
    fi
    
    # Redis 테스트
    if redis-cli ping | grep -q PONG; then
        log_info "✓ Redis 응답"
    else
        log_error "✗ Redis 응답 없음"
        return 1
    fi
    
    log_info "설치 검증 완료"
}

# 메인 실행
main() {
    echo "=========================================="
    echo "RHEL 능동방어 시스템 설치"
    echo "=========================================="
    echo ""
    
    check_rhel
    enable_epel
    install_apache_modules
    setup_modsecurity_rules
    install_nginx
    install_redis
    setup_firewall
    setup_selinux
    setup_logs
    start_services
    verify_installation
    
    echo ""
    echo "=========================================="
    echo "설치 완료!"
    echo "=========================================="
    echo ""
    echo "다음 명령어로 상태 확인:"
    echo "  sudo systemctl status httpd"
    echo "  sudo systemctl status nginx"
    echo "  sudo tail -f /var/log/httpd/security.log"
    echo "  sudo tail -f /var/log/nginx/security.log"
    echo ""
    echo "관리 인터페이스: http://your-server:8080/admin"
    echo ""
}

# 실행
main "$@"
