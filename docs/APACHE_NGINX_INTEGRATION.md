# Apache + nginx 통합 능동방어 가이드

## 아키텍처 개요

```
                    ┌─────────────────┐
                    │   Load Balancer │
                    │    (nginx)      │
                    └────────┬────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
        ┌───────▼───────┐         ┌───────▼───────┐
        │  nginx        │         │  Apache       │
        │  (Worker 1)   │         │  (Worker 2)   │
        └───────┬───────┘         └───────┬───────┘
                │                         │
        ┌───────▼───────┐         ┌───────▼───────┐
        │   백엔드      │         │   백엔드      │
        │   서버 풀     │         │   서버 풀     │
        └──────────────┘         └──────────────┘
```

## 왜 둘 다 사용하는가?

### 1. 성능 최적화
- **nginx**: 정적 파일, 프록시 (빠름)
- **Apache**: 동적 컨텐츠, 모듈 기능 (다양함)

### 2. 고가용성
- 한 서버가 장애나도 다른 서버가 처리
- 무중단 운영 가능

### 3. 보안 강화
- 이중 방어 레이어
- 서로 다른 취약점 패턴

## 구현 방법

### 방법 1: nginx를 프론트엔드 (권장)

```nginx
# nginx.conf
upstream backend {
    server 127.0.0.1:8080; # Apache
    server 127.0.0.1:8081 backup; # nginx 백업
}

server {
    listen 80;
    
    location / {
        # nginx가 첫 방어
        access_by_lua_block {
            local defense = require "defense"
            defense.check_request()
        }
        
        # Apache로 프록시
        proxy_pass http://backend;
    }
}
```

### 방법 2: Load Balancer로 분산

```nginx
# 로드밸런서 설정
upstream web_servers {
    least_conn; # 최소 연결 우선
    
    server 10.0.0.1:80 weight=3; # nginx (3배 더 많이)
    server 10.0.0.2:80 weight=1; # Apache
}

server {
    listen 80;
    
    location / {
        # 부하 분산
        proxy_pass http://web_servers;
        
        # 각 서버에 대해 능동방어
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## 파일 구조

```
active-defense-sys/
├── nginx-defense.conf          # nginx 설정
├── apache/
│   ├── apache-defense.conf      # Apache 설정
│   └── setup-apache-defense.sh  # Apache 설치 스크립트
├── lua/                          # 공통 Lua 스크립트
│   ├── defense.lua              # 기본 방어 로직
│   └── advanced_defense.lua    # 고급 방어 전략
└── docs/                         # 문서
    ├── APACHE_NGINX_COMPARISON.md
    └── INTEGRATION_GUIDE.md
```

## 배포 전략

### 1. 단계별 배포

```bash
# 1단계: nginx 먼저
sudo systemctl start nginx
sudo systemctl enable nginx

# 2단계: Apache 백엔드로
sudo systemctl start apache2
sudo systemctl enable apache2

# 3단계: 로드 밸런싱
sudo systemctl reload nginx
```

### 2. 무중단 마이그레이션

```bash
# 기존 Apache에 추가로 nginx 설치
sudo apt install nginx

# nginx로 트래픽 점진 이전
# 1. 10% 트래픽만 nginx
# 2. 50% 트래픽
# 3. 100% 트래픽

# 트래픽 분배 조정 (가중치)
upstream backend {
    server nginx weight=9;
    server apache weight=1;
}
```

## 성능 비교

### nginx 장점
- 더 빠른 정적 파일 서비스
- 더 낮은 메모리 사용
- 더 좋은 동시 연결 처리
- 444 상태코드 완전 지원

### Apache 장점
- 더 많은 모듈
- 더 강력한 ModSecurity
- 더 세밀한 제어
- 더 넓은 커뮤니티

### 함께 사용 시
- **최고 성능** (nginx의 빠름 + Apache의 기능)
- **최고 보안** (이중 방어)
- **최고 가용성** (장애 대비)

## 모니터링

### 통합 로그 수집

```bash
# nginx 로그
tail -f /var/log/nginx/security.log

# Apache 로그
tail -f /var/log/apache2/security.log

# 통합 모니터링
sudo tee /usr/local/bin/monitor-servers.sh << 'EOF'
#!/bin/bash

while true; do
    clear
    echo "=== 능동방어 시스템 모니터링 ==="
    echo ""
    echo "nginx 차단 수:"
    grep "blocked=1" /var/log/nginx/security.log | wc -l
    
    echo "Apache 차단 수:"
    grep "blocked" /var/log/apache2/security.log | wc -l
    
    sleep 5
done
EOF

sudo chmod +x /usr/local/bin/monitor-servers.sh
```

## 결론

**권장 구성**:
```
nginx (프론트) → Apache (백엔드) → 애플리케이션
```

**이유**:
1. nginx가 첫 방어 (빠름, 444 지원)
2. Apache가 추가 방어 (모듈 기능)
3. 최고의 성능과 보안

이렇게 하면 **두 웹서버의 장점**을 모두 활용할 수 있습니다!
