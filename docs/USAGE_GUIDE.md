# 🛡️ 능동방어 시스템 사용 가이드

## 개요

이 시스템은 **웹서버와 백엔드 애플리케이션 사이**에 배치되어 공격을 차단하고 정상 트래픽만 통과시킵니다.

## 아키텍처

```
         인터넷
           ↓
    [Load Balancer]
           ↓
┌──────────────────┐
│  능동방어 시스템   │ ← 여기에 설치!
│  (nginx/Apache)  │
│  + Lua 스크립트   │
│  + Redis         │
└────────┬─────────┘
         ↓
   [Backend 서버]
   (실제 애플리케이션)
```

## 설치 위치

### 옵션 1: 프론트엔드 프로XY 서버 (권장)

```
Public Internet
      ↓
[능동방어 시스템] ← nginx/Apache (포트 80)
      ↓
[내부 네트워크]
      ↓
[Backend 서버] ← 실제 애플리케이션 (포트 3000)
```

- 공격을 먼저 차단
- 백엔드 서버는 보호됨
- 대역폭 비용 절감

### 옵션 2: 백엔드 서버에 직접 설치

```
Public Internet
      ↓
[능동방어 시스템 + Backend] ← 같은 서버에 설치
      ↓
[애플리케이션 처리]
```

- 단일 서버 운영 가능
- 추가 서버 불필요

## 실제 사용 시나리오

### 시나리오 1: 전자상거래 사이트

**상황**: 5000 TPS 정상 거래 처리

1. **문제**: DDOS 방어 시스템이 정상 거래까지 차단
2. **해결**: 웹 관리 인터페이스에서 거래용 IP를 화이트리스트 추가
3. **결과**: 정상 거래는 통과, 공격만 차단

```
정상 거래 IP (5000 TPS) → 화이트리스트 → 통과 ✅
악성 공격 IP → 차단 → 연결 종료 (444) ❌
```

### 시나리오 2: API 서버 보호

**상황**: 외부에서 API 호출, 공격도 동시에 발생

1. **Rate Limiting**: 초당 100개 요청 제한
2. **IP 차단**: 공격 IP 자동 차단
3. **화이트리스트**: 허가된 API 클라이언트 IP 등록

```
허가된 API 클라이언트 → 화이트리스트 → 통과 ✅
무단 접근 시도 → Rate Limit 초과 → 차단 ❌
Bot 공격 → 즉시 차단 (444) ❌
```

## 설치 절차

### 1. 서버 준비 (RHEL 7/8/9)

```bash
# RHEL 서버에 SSH 접속
ssh user@your-server.com

# 시스템 업데이트
sudo yum update -y
```

### 2. 시스템 설치

```bash
# 소스 다운로드
git clone https://github.com/supersignal/active-defense-sys.git
cd active-defense-sys

# 설치 스크립트 실행
chmod +x install.sh
sudo ./install.sh
```

설치 중 선택 사항:
- `1` 선택 → Apache (mod_security 사용)
- `2` 선택 → nginx (Lua 스크립트 사용)

### 3. 설정 적용

#### nginx 선택 시

```bash
# nginx 설정 파일 복사
sudo cp nginx-defense.conf /etc/nginx/nginx.conf

# Lua 스크립트 복사
sudo mkdir -p /etc/nginx/lua
sudo cp lua/*.lua /etc/nginx/lua/

# nginx 재시작
sudo systemctl restart nginx
sudo systemctl status nginx
```

#### Apache 선택 시

```bash
# Apache 설정 파일 복사
sudo cp apache/apache-defense.conf /etc/httpd/conf.d/

# Apache 재시작
sudo systemctl restart httpd
sudo systemctl status httpd
```

### 4. 관리 인터페이스 설정

```bash
# 관리 인터페이스 디렉토리 생성
sudo mkdir -p /var/www/admin
sudo cp admin/index.html /var/www/admin/

# 방화벽 설정 (관리 인터페이스 포트)
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

# nginx에서 관리 인터페이스 연결 설정 필요
```

## 실제 사용 예시

### 1. 웹 브라우저로 접속

```
http://your-server:8080/admin
```

### 2. 정상 거래 IP 화이트리스트 추가

화이트리스트 탭에서:
- IP 주소: `203.0.113.45` (정상 거래 IP)
- 추가 사유: `정상 거래 (5000 TPS)`
- 만료 시간: `1일` 선택
- 추가 버튼 클릭

### 3. 임계치 조정

임계치 설정 탭에서:
- Rate Limiting: `5000 req/s` (정상 거래 허용)
- DDOS 판단: `10000 req/s` (DDOS와 정상 거래 구분)
- 저장 버튼 클릭

### 4. 공격 IP 차단 확인

차단된 IP 탭에서:
- 차단된 IP 목록 확인
- 필요시 수동 차단 해제

### 5. 실시간 모니터링

대시보드에서:
- 총 요청 수: 실시간 집계
- 차단된 요청: 공격 차단 수
- 활성 공격: 현재 공격 상태

## 주의사항

### 1. 백엔드 서버 연결

nginx 또는 Apache가 백엔드 서버를 프록XY해야 합니다.

nginx 설정 예시:
```nginx
proxy_pass http://127.0.0.1:3000;  # 실제 애플리케이션 포트
```

### 2. 방화벽 설정

```bash
# HTTP 포트 열기
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

# 관리 인터페이스 포트 열기
sudo firewall-cmd --permanent --add-port=8080/tcp

# Redis 포트 (내부만)
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="127.0.0.1" port port="6379" protocol="tcp" accept'

sudo firewall-cmd --reload
```

### 3. Redis 서비스 시작

```bash
sudo systemctl enable redis
sudo systemctl start redis
sudo systemctl status redis
```

## 모니터링 명령어

```bash
# 차단된 IP 수 확인
redis-cli KEYS "blocked:*" | wc -l

# 화이트리스트 IP 확인
redis-cli SMEMBERS "whitelist"

# 임계치 확인
redis-cli GET "threshold:rate_limit"

# 통계 확인
redis-cli GET "stats:total_requests"
redis-cli GET "stats:blocked_requests"

# 실시간 로그 모니터링
sudo tail -f /var/log/nginx/security.log
sudo tail -f /var/log/httpd/security.log
```

## 트러블슈팅

### 문제: 백엔드 서버에 연결되지 않음

```bash
# 프록XY 설정 확인
sudo nginx -t  # 또는
sudo apachectl configtest

# 백엔드 서버 상태 확인
curl http://127.0.0.1:3000
```

### 문제: 관리 인터페이스 접속 불가

```bash
# 방화벽 확인
sudo firewall-cmd --list-ports

# 서비스 상태 확인
sudo systemctl status nginx
sudo systemctl status httpd
```

### 문제: Redis 연결 실패

```bash
# Redis 상태 확인
sudo systemctl status redis

# Redis 재시작
sudo systemctl restart redis

# 연결 테스트
redis-cli ping
```

## 성능 최적화

### nginx 성능 튜닝

```nginx
# worker 프로세스 수
worker_processes auto;

# 연결 수 제한
worker_connections 2048;

# 최대 연결 수
worker_rlimit_nofile 65535;
```

### Apache 성능 튜닝

```apache
# MPM 설정
StartServers 8
MinSpareServers 5
MaxSpareServers 20
MaxRequestWorkers 400
```

## 보안 권장사항

1. **관리 인터페이스 접근 제한**
   - IP 화이트리스트 설정
   - Basic Auth 사용

2. **Redis 보안**
   - localhost만 허용
   - 인증 설정

3. **정기 업데이트**
   - 패키지 업데이트
   - 보안 패치 적용

## 요약

이 시스템은:
- **RHEL 서버에 설치**
- **웹서버 프록XY 앞단에 배치**
- **웹 인터페이스로 관리**
- **정상 트래픽과 공격을 구분**
- **비용 효율적으로 대역폭 보호**
