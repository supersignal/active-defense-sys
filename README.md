# 🛡️ nginx/Apache 능동방어 시스템 (RHEL 전용)

Red Hat Enterprise Linux 기반 능동방어 시스템입니다.

## 🚀 주요 기능

- **대역폭 효율적 방어**: 444를 활용한 즉시 연결 종료
- **이중 방어**: nginx + Apache 동시 지원
- **RHEL 최적화**: Red Hat 특화 설정
- **실시간 모니터링**: 위협 분석 및 로깅
- **적응형 Rate Limiting**: IP 평판 기반

## 📋 시스템 요구사항

- Red Hat Enterprise Linux 7/8/9
- 최소 2GB RAM
- 최소 10GB 디스크 공간
- root 또는 sudo 권한

## 🛠️ 설치

### 빠른 설치

```bash
# 설치 스크립트 실행
chmod +x install.sh
sudo ./install.sh

# 설치 중 웹서버 선택:
# 1) Apache (mod_security 기반)
# 2) nginx (Lua 스크립트 기반)
```

### 수동 설치

```bash
# EPEL 저장소 활성화
sudo yum install -y epel-release

# Apache 및 모듈 설치
sudo yum install -y httpd mod_security mod_evasive mod_qos

# nginx 설치
sudo tee /etc/yum.repos.d/nginx.repo << 'EOF'
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/rhel/$releasever/$basearch/
gpgcheck=0
enabled=1
EOF

sudo yum install -y nginx

# Redis 설치
sudo yum install -y redis
sudo systemctl enable redis
sudo systemctl start redis

# 설정 파일 복사
sudo cp apache/apache-defense.conf /etc/httpd/conf.d/
sudo cp nginx-defense.conf /etc/nginx/

# 서비스 시작
sudo systemctl enable httpd nginx
sudo systemctl start httpd nginx
```

## ⚙️ 설정

### Apache 설정

```bash
# ModSecurity 활성화
sudo vim /etc/httpd/conf.d/mod_security.conf

# 능동방어 설정 확인
sudo vim /etc/httpd/conf.d/defense-config.conf

# Apache 재시작
sudo systemctl restart httpd
```

### nginx 설정

```bash
# 메인 설정 확인
sudo vim /etc/nginx/nginx-defense.conf

# 능동방어 설정 확인
sudo vim /etc/nginx/lua/defense.lua

# nginx 재시작
sudo systemctl restart nginx
```

## 🔥 방화벽 설정 (firewalld)

```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## 🔒 SELinux 설정

```bash
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_can_network_relay 1
```

## 📊 모니터링

### 실시간 로그

```bash
# Apache 로그
sudo tail -f /var/log/httpd/security.log

# nginx 로그
sudo tail -f /var/log/nginx/security.log

# 통합 모니터링
sudo /usr/local/bin/monitor-servers.sh
```

### 통계 확인

```bash
# 차단된 IP 수
sudo grep "blocked" /var/log/httpd/security.log | wc -l

# 공격 시도 수
sudo grep "attack" /var/log/nginx/security.log | wc -l
```

## 🏗️ 아키텍처

### 선택 가능한 웹서버

```
설치 시 선택:
1) Apache (mod_security 기반)
2) nginx (Lua 스크립트 기반)

┌─────────────────────────────────┐
│     선택된 웹서버 (둘 중 하나)   │
│  ┌─────────┐   또는   ┌───────┐ │
│  │ Apache  │          │nginx │ │
│  └────┬────┘          └───┬───┘ │
│       │                  │     │
│  ┌────▼──────────────────▼───┐  │
│  │     공통 방어 로직        │  │
│  │ (threat_detection.lua)   │  │
│  └─────────┬────────────────┘  │
│            │                   │
│       ┌────▼───────────┐       │
│       │  백엔드 서버    │       │
│       └────────────────┘       │
└─────────────────────────────────┘
```

## 📁 파일 구조

```
active-defense-sys/
├── install-rhel.sh              # RHEL 설치 스크립트
├── nginx-defense.conf            # nginx 설정
├── apache/
│   ├── apache-defense.conf      # Apache 설정
│   └── setup-apache-defense.sh  # Apache 설치
├── lua/                          # Lua 스크립트
│   ├── defense.lua              # 기본 방어
│   └── advanced_defense.lua    # 고급 전략
├── scripts/                      # 유틸리티
│   ├── automation.sh            # 자동화
│   └── log_analyzer.sh          # 로그 분석
└── docs/                         # 문서
    ├── RHEL_GUIDE.md            # RHEL 가이드
    └── BANDWIDTH_EFFICIENCY.md  # 대역폭 전략
```

## 🛡️ 방어 전략

### 1. 444 사용 (대역폭 소비 제로)
```nginx
ngx.status = 444
ngx.exit(444)
```

### 2. 타임아웃 전략
```nginx
ngx.sleep(10)  # 공격자 리소스 소모
ngx.status = 503
```

### 3. Honey Token
```nginx
# 가짜 취약 페이지 제공
ngx.say('<html>Fake Login</html>')
```

### 4. Shadow Ban
```nginx
ngx.sleep(60)  # 계속 대기시키기
ngx.status = 504
```

## 📈 성능 비교

```
기존 방식 (403 차단):
- 대역폭: 100 KB/sec
- 월 비용: ~$50-100

개선 방식 (444 사용):
- 대역폭: 거의 제로
- 월 비용: ~$1-5

절감: 95% 이상 비용 절감
```

## 🔧 문제 해결

### SELinux 문제
```bash
sudo setsebool -P httpd_can_network_connect 1
```

### 포트 충돌
```bash
sudo netstat -tlnp | grep :80
sudo kill -9 <PID>
```

### 로그 확인
```bash
sudo tail -f /var/log/httpd/error_log
sudo tail -f /var/log/nginx/error.log
```

## 📚 문서

- [RHEL 가이드](docs/RHEL_GUIDE.md)
- [대역폭 효율 전략](docs/BANDWIDTH_EFFICIENCY.md)
- [Apache/nginx 통합](docs/APACHE_NGINX_INTEGRATION.md)

## 🔄 업데이트

```bash
# 최신 코드 받기
git pull origin master

# 설정 업데이트
sudo cp nginx-defense.conf /etc/nginx/
sudo cp apache/apache-defense.conf /etc/httpd/conf.d/

# 서비스 재시작
sudo systemctl restart nginx httpd
```

## 📞 지원

이슈 발생 시 [GitHub Issues](https://github.com/supersignal/active-defense-sys/issues)에 문의하세요.

## 📜 라이선스

MIT License

## 🙏 기여

Pull Request 환영합니다!