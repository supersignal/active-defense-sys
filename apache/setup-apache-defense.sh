#!/bin/bash

# Apache 능동방어 시스템 구현 가이드

# 1. 필요한 모듈 설치
install_modules() {
    echo "Apache 능동방어 모듈 설치 중..."
    
    # Ubuntu/Debian
    if command -v apt &> /dev/null; then
        sudo apt update
        sudo apt install -y libapache2-mod-security2 libapache2-mod-evasive libapache2-mod-qos
        
        # mod_lua 설치 (Lua 스크립트 지원)
        sudo apt install -y libapache2-mod-lua
    
    # CentOS/RHEL
    elif command -v yum &> /dev/null; then
        sudo yum install -y mod_security mod_evasive mod_qos
    fi
    
    echo "모듈 설치 완료!"
}

# 2. ModSecurity 설정 활성화
setup_modsecurity() {
    echo "ModSecurity 설정 중..."
    
    # ModSecurity 설정 복사
    sudo cp apache/apache-defense.conf /etc/apache2/sites-available/defense-config.conf
    
    # ModSecurity 규칙 활성화
    sudo a2enmod security2
    sudo a2enmod evasive
    sudo a2enmod qos
    sudo a2enmod lua
    
    # 설정 파일 링크
    sudo ln -s /etc/apache2/sites-available/defense-config.conf /etc/apache2/sites-enabled/
    
    echo "ModSecurity 설정 완료!"
}

# 3. Apache 재시작
restart_apache() {
    echo "Apache 재시작 중..."
    
    # 설정 테스트
    sudo apache2ctl configtest
    
    if [ $? -eq 0 ]; then
        sudo systemctl restart apache2
        echo "Apache 재시작 완료!"
    else
        echo "설정 오류가 있습니다!"
        exit 1
    fi
}

# 4. 로그 모니터링 설정
setup_monitoring() {
    echo "모니터링 설정 중..."
    
    # 로그 디렉토리 생성
    sudo mkdir -p /var/log/apache2/audit
    sudo mkdir -p /var/log/apache2/defense
    
    # logrotate 설정
    sudo tee /etc/logrotate.d/apache-defense << EOF
/var/log/apache2/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        systemctl reload apache2
    endscript
}
EOF
    
    echo "모니터링 설정 완료!"
}

# 5. 능동방어 스크립트
active_defense_scripts() {
    echo "능동방어 스크립트 생성 중..."
    
    # Honey Token 핸들러
    sudo tee /usr/local/bin/honey-trap-handler.sh << 'EOF'
#!/bin/bash
# Honey Token 핸들러

IP=$1
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "$DATE: Honey token triggered by $IP" >> /var/log/apache2/honey-trap.log

# 악성 IP로 마킹
redis-cli SET "malicious_ip:$IP" "honey_trap" EX 3600

# 이메일 알림 (선택사항)
# echo "Honey token triggered by $IP" | mail -s "Security Alert" admin@yourdomain.com
EOF
    
    sudo chmod +x /usr/local/bin/honey-trap-handler.sh
    
    # DDoS 공격 알림
    sudo tee /usr/local/bin/dos-notify.sh << 'EOF'
#!/bin/bash
# DDoS 공격 알림

IP=$1
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "$DATE: DDoS attack detected from $IP" >> /var/log/apache2/dos-attacks.log

# 악성 IP 차단
sudo iptables -A INPUT -s $IP -j DROP

# 이메일 알림
echo "DDoS attack from $IP" | mail -s "DDoS Alert" admin@yourdomain.com
EOF
    
    sudo chmod +x /usr/local/bin/dos-notify.sh
    
    echo "능동방어 스크립트 생성 완료!"
}

# 6. Apache vs nginx 비교
compare_apache_nginx() {
    cat << 'EOF'

Apache vs nginx 능동방어 비교:

┌─────────────────────────────────────────────────────────┐
│ 기능                    │ Apache      │ nginx        │
├─────────────────────────────────────────────────────────┤
│ 모듈 기반 방어          │ mod_security│ Lua 스크립트 │
│ DDoS 방어              │ mod_evasive │ limit_req    │
│ Rate Limiting          │ mod_qos     │ limit_req    │
│ Lua 스크립트           │ mod_lua     │ lua-nginx    │
│ 444 상태코드 지원      │ 제한적      │ 완전 지원    │
│ 메모리 사용량          │ 높음        │ 낮음         │
│ 동시 연결 처리         │ 중간        │ 뛰어남       │
│ 설정 복잡도            │ 높음        │ 낮음         │
│ 커뮤니티 지원          │ 강함        │ 강함         │
└─────────────────────────────────────────────────────────┘

추천:
- Apache: 모듈 기반 방어, 다양한 기능
- nginx: 성능, 444 지원, 단순한 설정
- 둘 다 사용: Load Balancer로 분산

EOF
}

# 메인 실행
main() {
    echo "=== Apache 능동방어 시스템 설치 ==="
    
    install_modules
    setup_modsecurity
    active_defense_scripts
    setup_monitoring
    restart_apache
    
    echo "=== 설치 완료 ==="
    echo ""
    echo "다음 명령어로 상태를 확인하세요:"
    echo "  sudo systemctl status apache2"
    echo "  sudo tail -f /var/log/apache2/security.log"
    echo ""
    
    compare_apache_nginx
}

# 스크립트 실행
main "$@"
