# 🛡️ 능동방어 시스템 (RHEL 전용)

Red Hat Enterprise Linux 기반 능동방어 시스템입니다.

## 🚀 주요 기능

- **Apache 또는 nginx 선택 가능**: 설치 시 웹서버 선택
- **대역폭 효율적 방어**: 444를 활용한 즉시 연결 종료로 비용 절감
- **화이트리스트 관리**: 정상 거래 IP 예외 처리 (예: 5000 TPS)
- **동적 임계치 조정**: 실시간 보안 정책 변경
- **웹 관리 인터페이스**: IP 차단/해제, 화이트리스트, 임계치 설정
- **실시간 모니터링**: 보안 통계 및 공격 분석

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

설치 스크립트가 자동으로:
- EPEL 저장소 활성화
- 선택한 웹서버 설치
- Redis 설치 및 설정
- 능동방어 설정 적용
- 방화벽 및 SELinux 설정

## 🔧 설정

### 방화벽 설정

```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

### SELinux 설정

```bash
sudo setsebool -P httpd_can_network_connect 1
sudo setsebool -P httpd_can_network_relay 1
```

## 📊 관리 인터페이스

웹 브라우저에서 접속:

```
http://your-server:8080/admin
```

### 기능

- **차단된 IP 관리**: 차단/해제, 차단 사유 확인
- **화이트리스트**: 정상 거래 IP 등록 (5000 TPS 예외 처리)
- **임계치 설정**: Rate Limiting, 위협 점수, DDOS 판단 기준 조정
- **실시간 통계**: 총 요청 수, 차단 횟수, 활성 공격
- **보안 로그**: 실시간 공격 시도 모니터링

## 🏗️ 아키텍처

```
┌─────────────────────────────────┐
│     선택된 웹서버 (둘 중 하나)   │
│  ┌─────────┐   또는   ┌───────┐ │
│  │ Apache  │          │nginx │ │
│  │(mod_sec)│          │(Lua) │ │
│  └────┬────┘          └───┬───┘ │
│       │                  │     │
│  ┌────▼──────────────────▼───┐  │
│  │     공통 방어 로직        │  │
│  │ (threat_detection.lua)   │  │
│  └─────────┬────────────────┘  │
│            │                   │
│       ┌────▼───────────┐       │
│       │  Redis Cache   │       │
│       └────────────────┘       │
└─────────────────────────────────┘
```

## 📁 파일 구조

```
active-defense-sys/
├── install.sh                  # 통합 설치 스크립트
├── nginx-defense.conf          # nginx 설정
├── admin/
│   └── index.html              # 웹 관리 인터페이스
├── apache/
│   ├── apache-defense.conf     # Apache 설정
│   └── setup-apache-defense.sh # Apache 설치
├── lua/                        # nginx Lua 스크립트
│   ├── defense.lua             # 기본 방어
│   └── advanced_defense.lua    # 고급 전략
├── common/                     # 공통 로직
│   └── threat_detection.lua    # 위협 감지
├── api/                        # API 엔드포인트
│   └── admin_api_server.lua    # 관리 API
└── scripts/                    # 유틸리티
    ├── automation.sh           # 자동화
    └── log_analyzer.sh         # 로그 분석
```

## 🛡️ 방어 전략

### 1. 대역폭 효율적 차단 (444)

HTTP 응답 없이 즉시 연결 종료 → 대역폭 소비 제로

### 2. 타임아웃 전략

공격자를 대기시켜 리소스 소모

### 3. Honey Token

가짜 취약 페이지 제공으로 공격 정보 수집

### 4. Shadow Ban

차단 사실을 숨겨 계속 요청 유도

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
# Apache
sudo tail -f /var/log/httpd/security.log

# nginx
sudo tail -f /var/log/nginx/security.log
```

## 📚 문서

- [RHEL 가이드](docs/RHEL_GUIDE.md)
- [대역폭 효율 전략](docs/BANDWIDTH_EFFICIENCY.md)

## 🔄 업데이트

```bash
git pull origin master
sudo systemctl restart nginx httpd
```

## 📞 지원

[GitHub Issues](https://github.com/supersignal/active-defense-sys/issues)

## 📜 라이선스

MIT License