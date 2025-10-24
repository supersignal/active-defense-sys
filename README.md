# nginx 능동방어 시스템 설치 및 설정 가이드

## 시스템 요구사항
- Ubuntu 20.04+ 또는 CentOS 8+
- nginx 1.18+
- LuaJIT 2.1+
- Redis 6.0+
- Node.js 16+ (관리 인터페이스용)

## 1. 의존성 설치

### Ubuntu/Debian
```bash
# nginx 및 Lua 모듈 설치
sudo apt update
sudo apt install nginx nginx-module-lua lua-cjson redis-server

# Lua Redis 클라이언트 설치
sudo apt install luarocks
sudo luarocks install lua-resty-redis
```

### CentOS/RHEL
```bash
# EPEL 저장소 활성화
sudo yum install epel-release

# nginx 및 Lua 모듈 설치
sudo yum install nginx lua-devel lua-cjson redis

# Lua Redis 클라이언트 설치
sudo yum install luarocks
sudo luarocks install lua-resty-redis
```

## 2. nginx 설정

### nginx.conf 설정
```bash
# 기존 nginx.conf 백업
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# 새로운 설정 파일 복사
sudo cp nginx.conf /etc/nginx/nginx.conf

# Lua 스크립트 디렉토리 생성
sudo mkdir -p /etc/nginx/lua
sudo cp lua/*.lua /etc/nginx/lua/

# 관리 인터페이스 디렉토리 생성
sudo mkdir -p /var/www/admin
sudo cp admin/index.html /var/www/admin/
```

### nginx 모듈 활성화
```bash
# Ubuntu/Debian
echo "load_module modules/ngx_http_lua_module.so;" | sudo tee -a /etc/nginx/nginx.conf

# CentOS/RHEL
echo "load_module modules/ngx_http_lua_module.so;" | sudo tee -a /etc/nginx/nginx.conf
```

## 3. Redis 설정

### Redis 서비스 시작
```bash
sudo systemctl start redis
sudo systemctl enable redis
```

### Redis 설정 확인
```bash
redis-cli ping
# 응답: PONG
```

## 4. 방화벽 설정

```bash
# 필요한 포트 열기
sudo ufw allow 80/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 6379/tcp  # Redis (내부 네트워크만)
sudo ufw reload
```

## 5. 서비스 시작

```bash
# nginx 설정 테스트
sudo nginx -t

# nginx 재시작
sudo systemctl restart nginx
sudo systemctl enable nginx

# 서비스 상태 확인
sudo systemctl status nginx
sudo systemctl status redis
```

## 6. 로그 모니터링 설정

### 로그 로테이션 설정
```bash
sudo tee /etc/logrotate.d/nginx-defense << EOF
/var/log/nginx/access.log
/var/log/nginx/security.log
/var/log/nginx/error.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 nginx nginx
    postrotate
        systemctl reload nginx
    endscript
}
EOF
```

## 7. 모니터링 스크립트

### 실시간 모니터링 스크립트 생성
```bash
sudo tee /usr/local/bin/nginx-defense-monitor << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/nginx-defense-monitor.log"
SECURITY_LOG="/var/log/nginx/security.log"

echo "$(date): nginx 능동방어 시스템 모니터링 시작" >> $LOG_FILE

# 실시간 로그 모니터링
tail -f $SECURITY_LOG | while read line; do
    if echo "$line" | grep -q "blocked=1"; then
        echo "$(date): 보안 위협 감지 - $line" >> $LOG_FILE
        
        # 이메일 알림 (선택사항)
        # echo "보안 위협이 감지되었습니다: $line" | mail -s "nginx 보안 알림" admin@yourdomain.com
    fi
done
EOF

sudo chmod +x /usr/local/bin/nginx-defense-monitor
```

### systemd 서비스 등록
```bash
sudo tee /etc/systemd/system/nginx-defense-monitor.service << EOF
[Unit]
Description=nginx Defense System Monitor
After=nginx.service redis.service

[Service]
Type=simple
ExecStart=/usr/local/bin/nginx-defense-monitor
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable nginx-defense-monitor
sudo systemctl start nginx-defense-monitor
```

## 8. 테스트

### 기본 연결 테스트
```bash
# nginx 상태 확인
curl -I http://localhost

# 관리 인터페이스 접근 테스트
curl -I http://localhost:8080/admin
```

### 보안 기능 테스트
```bash
# 의심스러운 요청 테스트
curl "http://localhost/admin"
curl "http://localhost/wp-admin"
curl "http://localhost/test.php"

# Rate Limiting 테스트
for i in {1..30}; do curl http://localhost; done
```

## 9. 성능 튜닝

### nginx 성능 최적화
```bash
# worker 프로세스 수 조정
worker_processes auto;

# 연결 수 제한
worker_connections 2048;

# 버퍼 크기 최적화
client_body_buffer_size 128k;
client_max_body_size 10m;
client_header_buffer_size 1k;
large_client_header_buffers 4 4k;
```

### Redis 메모리 최적화
```bash
# Redis 설정 파일 수정
sudo tee -a /etc/redis/redis.conf << EOF
maxmemory 256mb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
EOF

sudo systemctl restart redis
```

## 10. 백업 및 복구

### 설정 백업 스크립트
```bash
sudo tee /usr/local/bin/nginx-defense-backup << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/nginx-defense"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# nginx 설정 백업
tar -czf $BACKUP_DIR/nginx-config-$DATE.tar.gz /etc/nginx/

# Lua 스크립트 백업
tar -czf $BACKUP_DIR/lua-scripts-$DATE.tar.gz /etc/nginx/lua/

# 관리 인터페이스 백업
tar -czf $BACKUP_DIR/admin-interface-$DATE.tar.gz /var/www/admin/

# Redis 데이터 백업
redis-cli BGSAVE
cp /var/lib/redis/dump.rdb $BACKUP_DIR/redis-$DATE.rdb

echo "백업 완료: $BACKUP_DIR"
EOF

sudo chmod +x /usr/local/bin/nginx-defense-backup
```

## 11. 문제 해결

### 일반적인 문제들

1. **Lua 모듈 로드 실패**
   ```bash
   # Lua 모듈 경로 확인
   find /usr -name "ngx_http_lua_module.so"
   
   # nginx 모듈 디렉토리 확인
   nginx -V 2>&1 | grep -o 'modules-path=[^ ]*'
   ```

2. **Redis 연결 실패**
   ```bash
   # Redis 서비스 상태 확인
   sudo systemctl status redis
   
   # Redis 포트 확인
   netstat -tlnp | grep 6379
   ```

3. **권한 문제**
   ```bash
   # nginx 사용자 권한 확인
   sudo -u nginx ls -la /etc/nginx/lua/
   
   # 로그 파일 권한 확인
   sudo chown nginx:nginx /var/log/nginx/security.log
   ```

## 12. 보안 강화

### 추가 보안 설정
```bash
# nginx 사용자 권한 제한
sudo usermod -s /bin/false nginx

# 로그 파일 권한 설정
sudo chmod 640 /var/log/nginx/security.log
sudo chown nginx:nginx /var/log/nginx/security.log

# 관리 인터페이스 접근 제한
sudo tee /etc/nginx/conf.d/admin-restrict.conf << EOF
location /admin {
    allow 192.168.1.0/24;
    allow 10.0.0.0/8;
    deny all;
}
EOF
```

이제 nginx 기반 능동방어 시스템이 완전히 구축되었습니다! 🛡️
