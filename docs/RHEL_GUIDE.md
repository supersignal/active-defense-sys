# RHEL 능동방어 시스템 가이드

## 시스템 요구사항

- Red Hat Enterprise Linux 7/8/9
- 최소 2GB RAM
- 최소 10GB 디스크 공간
- root 또는 sudo 권한

## 설치 방법

### 1. 저장소 준비

```bash
# EPEL 저장소 활성화 (RHEL 7)
sudo yum install -y epel-release

# RHEL 8+는 기본 저장소 사용
```

### 2. 설치 스크립트 실행

```bash
chmod +x install-rhel.sh
sudo ./install-rhel.sh
```

### 3. 수동 설치 (선택사항)

#### Apache 모듈 설치

```bash
# RHEL 7
sudo yum install -y httpd mod_security mod_evasive mod_qos

# RHEL 8/9
sudo dnf install -y httpd mod_security mod_evasive mod_qos
```

#### nginx 설치

```bash
# nginx 공식 저장소 추가
sudo tee /etc/yum.repos.d/nginx.repo << 'EOF'
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/rhel/$releasever/$basearch/
gpgcheck=0
enabled=1
EOF

# nginx 설치
sudo yum install -y nginx

# Lua 모듈 (openresty)
sudo yum install -y lua-resty-core
```

#### Redis 설치

```bash
# RHEL 7
sudo yum install -y redis

# RHEL 8/9
sudo dnf install -y redis

# 서비스 시작
sudo systemctl enable redis
sudo systemctl start redis
```

## RHEL 특화 설정

### SELinux 설정

```bash
# Apache 네트워크 접근 허용
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_can_network_relay 1

# 포트 허용
sudo semanage port -a -t http_port_t -p tcp 8080
```

### 방화벽 설정 (firewalld)

```bash
# HTTP/HTTPS 허용
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# 또는 특정 포트만
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

### 방화벽 설정 (iptables) - 레거시

```bash
# HTTP
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT

# HTTPS
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Redis (내부만)
sudo iptables -A INPUT -p tcp -s 127.0.0.1 --dport 6379 -j ACCEPT

# 규칙 저장
sudo service iptables save
```

## 서비스 관리

### Apache

```bash
# 시작
sudo systemctl start httpd

# 중지
sudo systemctl stop httpd

# 재시작
sudo systemctl restart httpd

# 상태 확인
sudo systemctl status httpd

# 부팅 시 자동 시작
sudo systemctl enable httpd
```

### nginx

```bash
# 시작
sudo systemctl start nginx

# 중지
sudo systemctl stop nginx

# 재시작
sudo systemctl restart nginx

# 상태 확인
sudo systemctl status nginx

# 부팅 시 자동 시작
sudo systemctl enable nginx
```

### Redis

```bash
# 시작
sudo systemctl start redis

# 중지
sudo systemctl stop redis

# 재시작
sudo systemctl restart redis

# 상태 확인
sudo systemctl status redis

# 부팅 시 자동 시작
sudo systemctl enable redis
```

## 설정 파일 위치

```
/etc/httpd/
├── conf/
│   ├── httpd.conf          # Apache 메인 설정
│   └── modules.conf        # 모듈 설정
├── conf.d/
│   ├── mod_security.conf    # ModSecurity
│   ├── mod_evasive.conf    # mod_evasive
│   ├── mod_qos.conf        # mod_qos
│   └── defense-config.conf # 능동방어 설정
└── logs/                   # 로그 파일

/etc/nginx/
├── nginx.conf              # nginx 메인 설정
├── conf.d/
│   └── defense.conf       # 능동방어 설정
└── lua/                    # Lua 스크립트

/etc/redis.conf              # Redis 설정
```

## 문제 해결

### SELinux 문제

```bash
# SELinux 상태 확인
getenforce

# 임시 비활성화 (권장하지 않음)
sudo setenforce 0

# 영구 비활성화
sudo vim /etc/selinux/config
# SELINUX=disabled

# 또는 허용 정책 추가
sudo setsebool -P httpd_can_network_connect 1
```

### 포트 충돌

```bash
# 포트 사용 확인
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :8080

# PID 확인 후 종료
sudo kill -9 <PID>
```

### 로그 확인

```bash
# Apache 로그
sudo tail -f /var/log/httpd/error_log
sudo tail -f /var/log/httpd/access_log

# nginx 로그
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log

# Redis 로그
sudo tail -f /var/log/redis/redis.log
```

## 성능 튜닝 (RHEL)

### Apache 성능

```bash
# /etc/httpd/conf/httpd.conf 편집
vim /etc/httpd/conf/httpd.conf

# MPM 설정
<IfModule prefork.c>
    StartServers        8
    MinSpareServers     5
    MaxSpareServers     20
    MaxRequestWorkers    256
    MaxConnectionsPerChild  10000
</IfModule>
```

### nginx 성능

```bash
# /etc/nginx/nginx.conf 편집
vim /etc/nginx/nginx.conf

# Worker 설정
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 2048;
    use epoll;
}
```

### 커널 파라미터

```bash
# /etc/sysctl.conf 편집
sudo vim /etc/sysctl.conf

# 추가
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.ip_local_port_range = 1024 65535

# 적용
sudo sysctl -p
```

## 모니터링

### 실시간 모니터링

```bash
# Apache 상태
watch -n 1 'ps aux | grep httpd | wc -l'

# nginx 상태
watch -n 1 'ps aux | grep nginx | wc -l'

# 트래픽 모니터링
iftop
nload
```

### 로그 분석

```bash
# 차단된 IP 수
sudo grep "blocked" /var/log/httpd/security.log | wc -l

# 공격 시도 수
sudo grep "attack" /var/log/nginx/security.log | wc -l

# 실시간 로그 모니터링
sudo tail -f /var/log/httpd/security.log
sudo tail -f /var/log/nginx/security.log
```

## 업데이트

```bash
# 시스템 업데이트
sudo yum update

# Apache 업데이트
sudo yum update httpd mod_security

# nginx 업데이트
sudo yum update nginx

# Redis 업데이트
sudo yum update redis
```

## 백업 및 복구

```bash
# 설정 백업
sudo tar -czf defense-backup-$(date +%Y%m%d).tar.gz \
    /etc/httpd \
    /etc/nginx \
    /etc/redis.conf \
    /etc/nginx/lua

# 복구
sudo tar -xzf defense-backup-YYYYMMDD.tar.gz -C /
```
