# 여러 웹서버 배포 전략

## 시나리오 1: Load Balancer 앞단에 설치 (권장)

```
인터넷
  ↓
[Load Balancer] (nginx/Apache)
  ↓
[능동방어 시스템] ← 여기 1대만 설치!
  ↓
┌──────────────────────┐
│  Backend 서버군      │
│  ┌────┬────┬────┐   │
│  │서버1│서버2│서버3│  │
│  └────┴────┴────┘   │
└──────────────────────┘
```

**장점**:
- 1대만 설치하면 모든 트래픽 처리
- 공격을 먼저 차단
- 백엔드 서버는 안전

## 시나리오 2: 각 웹서버에 개별 설치

```
인터넷
  ↓
┌────────────────────┐
│  웹서버 1           │
│  + 능동방어 시스템   │
└────────┬───────────┘
         │
┌────────▼───────────┐
│  웹서버 2           │
│  + 능동방어 시스템   │
└────────┬───────────┘
         │
┌────────▼───────────┐
│  웹서버 3           │
│  + 능동방어 시스템   │
└────────────────────┘
```

**장점**:
- 각 서버 독립 보호
- 한 서버 장애 시 영향 적음

**단점**:
- 모든 서버에 설치 필요
- 관리 복잡

## 시나리오 3: 분산 시스템 (Redis 공유)

여러 서버가 같은 Redis를 사용하여 정보 공유:

```bash
# 모든 서버가 같은 Redis 사용
Redis Server: 192.168.1.100:6379

웹서버 1 → 192.168.1.100:6379
웹서버 2 → 192.168.1.100:6379
웹서버 3 → 192.168.1.100:6379
```

**장점**:
- 한 서버에서 차단하면 모든 서버에 적용
- 화이트리스트 동기화
- 실시간 정보 공유

## 권장 구성

### 구성 1: 프론트엔드 전용 서버 (가장 효율적)

```
Public Internet
      ↓
[Load Balancer]
      ↓
[능동방어 전용 서버] ← 1대만 설치 (nginx/Apache)
      ↓
[내부 네트워크]
      ↓
┌────────────┬──────────┬──────────┐
│  Backend 1 │ Backend 2│ Backend 3│
└────────────┴──────────┴──────────┘
```

설치 방법:
```bash
# 프론트엔드 서버 1대에 설치
ssh frontend-server
cd active-defense-sys
sudo ./install.sh
# nginx 선택 (또는 Apache)
```

백엔드 서버들(2, 3)은 설치 불필요.

### 구성 2: 분산 설치 (각 서버에 설치)

모든 웹서버에 설치하되, **같은 Redis 서버 공유**:

#### 단계 1: 중앙 Redis 서버 설정

```bash
# redis-server.conf 편집
vim /etc/redis.conf

# 모든 IP 허용 (내부 네트워크만)
bind 192.168.1.100
protected-mode no
```

#### 단계 2: 각 웹서버 설치

```bash
# 웹서버 1
ssh webserver1
git clone https://github.com/supersignal/active-defense-sys.git
cd active-defense-sys
sudo ./install.sh

# Redis 연결 설정 변경
vim lua/defense.lua
# Redis IP를 중앙 서버로 변경
# red:connect("192.168.1.100", 6379)  # 중앙 Redis 서버
```

```bash
# 웹서버 2, 3도 동일하게 설치
ssh webserver2
# 위와 동일
```

## 빠른 설정 (모든 서버에 적용)

### Step 1: 한 서버에 설치

```bash
# 마스터 서버에서
ssh master-server
git clone https://github.com/supersignal/active-defense-sys.git
cd active-defense-sys
sudo ./install.sh
# nginx 또는 Apache 선택
```

### Step 2: 설정 파일 다른 서버에 복사

```bash
# 설정 파일 생성
sudo cp nginx-defense.conf /etc/nginx/nginx.conf
sudo cp -r lua /etc/nginx/

# 다른 서버들에 배포
sudo scp /etc/nginx/nginx.conf webserver2:/etc/nginx/
sudo scp /etc/nginx/nginx.conf webserver3:/etc/nginx/
sudo scp -r /etc/nginx/lua webserver2:/etc/nginx/
sudo scp -r /etc/nginx/lua webserver3:/etc/nginx/
```

### Step 3: Redis 공유 설정

모든 서버가 같은 Redis 서버를 가리키도록:

```bash
# 각 서버에서
sudo vim /etc/nginx/lua/defense.lua

# Redis 연결 IP 변경
red:connect("192.168.1.100", 6379)  # 중앙 Redis 서버
```

## 현재 시스템 구조 파악

시스템이 어떻게 구성되어 있는지 알려주세요:

1. **몇 대의 웹서버**가 있나요?
2. **Load Balancer**가 있나요?
3. **백엔드 서버**는 분리되어 있나요?
4. **네트워크 구조**는 어떻게 되나요?

이 정보를 알려주시면 최적의 설치 방법을 제안해드릴 수 있습니다.
