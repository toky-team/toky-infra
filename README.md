# TOKY-INFRA

## Description
정기전 승부예측 서비스 `TOKY`의 인프라스트럭처 레포지토리입니다.

이벤트 기반 롤링 배포 시스템을 통해 안정적이고 확장 가능한 서비스 인프라를 제공합니다.

## Deploy

### Prod Server
toky-back 레포에서 `ci-build-push.yml` 스크립트를 통해 생성된 Docker 이미지를 활용하여 운영 서버의 구축 및 배포를 담당합니다.

`repository_dispatch` 이벤트를 통해 자동으로 롤링 배포가 수행됩니다:

```bash
# 배포 플로우
1. toky-back에서 새 이미지 빌드 완료 이벤트 발생
2. GitHub Actions deploy.yml 워크플로우 트리거
3. 운영 노드에 SSH 접속
4. /opt/ops/00_run_all.sh 롤링 배포 스크립트 실행
```

#### Rolling Deploy Pipeline
```bash
/opt/ops/01_discover.sh        # 서버 디스커버리
/opt/ops/02_render_prom_targets.sh  # Prometheus 타겟 업데이트  
/opt/ops/03_reload_prom.sh     # Prometheus 설정 리로드
/opt/ops/04_rolling_restart_alb.sh  # 앱 노드 롤링 재시작
```

## Architecture

본 프로젝트는 각 노드별 역할을 분리하여 확장 가능한 구조로 설계되었습니다. 또한 로드 밸런서를 통한 트래픽 분산과 호스트 도메인 기반 라우팅을 지원합니다.

전체 인프라는 3개의 노드 타입으로 구성됩니다:

### Server Nodes

#### Data Node - 1개
- **역할**: 중앙집중식 데이터베이스 서비스 제공
- **구성**:
  - **PostgreSQL**: 메인 관계형 데이터베이스
  - **Redis**: 캐시 및 세션 저장소  
  - **MongoDB**: 문서형 데이터 저장소
- **특징**:
  - 프라이빗 IP로만 접근 가능 (보안)
  - 데이터 영속성을 위한 볼륨 마운트
  - 헬스체크를 통한 서비스 상태 모니터링

#### App Nodes - 2개 (수평 확장 가능)
- **역할**: 백엔드 API 서비스 제공
- **구성**:
  - **NestJS Application**: 메인 백엔드 서버
  - **Caddy**: 리버스 프록시 및 로드 밸런서
  - **Node Exporter**: 시스템 메트릭 수집
- **특징**:
  - 수평 확장 가능한 구조
  - 각 노드는 독립적으로 운영
  - Caddy를 통한 요청 분산
  - 헬스체크 기반 자동 복구

#### Ops Node - 1개
- **역할**: 모니터링, 관리 및 정적 파일 서비스 제공
- **구성**:
  - **Prometheus**: 메트릭 수집 및 저장
  - **Grafana**: 시각화 및 대시보드
  - **Caddy**: 정적 파일 서빙 및 도메인 기반 라우팅
- **특징**:
  - 모든 노드의 메트릭 수집
  - 웹 기반 모니터링 대시보드
  - 호스트 도메인에 따른 서비스 분기
  - 운영 스크립트 자동화

### Load Balancer Architecture

```
                    ┌─────────────────────┐
                    │   Load Balancer     │
                    │  (Domain Routing)   │
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
      ┌───▼───┐            ┌───▼───┐            ┌───▼───┐
      │App #1 │            │App #2 │            │  Ops  │
      │Node   │            │Node   │            │ Node  │
      │       │            │       │            │       │
      │API    │            │API    │            │Monitor│
      │Service│            │Service│            │Static │
      └───┬───┘            └───┬───┘            │Files  │
          │                    │                └───────┘
          └────┬───────────────┘
               │
           ┌───▼───┐
           │ Data  │
           │ Node  │
           │       │
           │  DB   │
           └───────┘
```

### Domain-Based Routing

Ops 노드의 Caddy가 호스트 도메인에 따라 서비스를 분기합니다:

- **`toky.devkor.club`**: 프론트엔드 정적 파일 서빙
- **`admin.toky.devkor.club`**: 관리자 페이지 정적 파일 서빙  
- **`monitor.toky.devkor.club`**: 
  - `/grafana/*` → Grafana 대시보드
  - `/prometheus/*` → Prometheus 메트릭

## Directory Structure

디렉토리 구조는 다음과 같습니다.

```bash
toky-infra/
├── README.md                    # 프로젝트 문서
├── env-templates/               # 환경 변수 템플릿
│   ├── app.env.template         # 앱 노드용 환경 변수 템플릿
│   ├── caddy.env.template       # Caddy 설정 템플릿
│   ├── data-node.env.template   # 데이터 노드용 환경 변수 템플릿
│   └── ops.env.sh.template      # 운영 노드용 환경 변수 템플릿
│
├── files/                       # 배포용 설정 파일들
│   ├── app/                     # 앱 노드 설정
│   │   ├── Caddyfile            # 리버스 프록시 설정
│   │   └── docker-compose.yml   # 앱 서비스 정의
│   │
│   ├── data/                    # 데이터 노드 설정  
│   │   └── docker-compose.yml   # 데이터베이스 서비스 정의
│   │
│   └── ops/                     # 운영 노드 설정
│       ├── Caddyfile            # 도메인 라우팅 및 프록시 설정
│       ├── docker-compose.yml   # 모니터링 서비스 정의
│       ├── prometheus.yml       # Prometheus 설정
│       └── scripts/             # 운영 자동화 스크립트
│           ├── 00_run_all.sh
│           ├── 01_discover.sh
│           ├── 02_render_prom_targets.sh
│           ├── 03_reload_prom.sh
│           └── 04_rolling_restart_alb.sh
│
└── .github/
    └── workflows/
        └── deploy.yml           # 배포 워크플로우
```

## Technology & Infra

Docker Compose, Caddy, Prometheus, Grafana, PostgreSQL, Redis, MongoDB, GitHub Actions

## Environment Setup

### 1. 환경 파일 설정
템플릿을 복사하여 실제 환경 파일 생성:

```bash
# 템플릿 파일들을 실제 환경 파일로 복사
cp env-templates/app.env.template app.env
cp env-templates/caddy.env.template caddy.env  
cp env-templates/data-node.env.template .env
# 운영노드는 스크립트 기반 환경변수 사용
cp env-templates/ops.env.sh.template ops.env.sh
```

### 2. 각 환경 파일 수정
각 노드에 맞는 설정값으로 수정

### 3. 보안 정보 설정
GitHub Secrets에 SSH 접속 정보 등록:
- `OPS_SSH_HOST`
- `OPS_SSH_USER`  
- `OPS_SSH_KEY`

## Monitoring

- **Prometheus**: 메트릭 수집 (`monitor.toky.devkor.club/prometheus`)
- **Grafana**: 시각화 대시보드 (`monitor.toky.devkor.club/grafana`)
- **Node Exporter**: 시스템 메트릭
- **헬스체크**: 서비스 가용성 모니터링

## Features

- ✅ **무중단 배포**: 롤링 배포를 통한 Zero-downtime 배포
- ✅ **자동 배포**: 이벤트 기반 자동 배포 시스템
- ✅ **수평 확장**: 앱 노드의 수평 확장 지원
- ✅ **모니터링**: Prometheus + Grafana 기반 모니터링
- ✅ **도메인 라우팅**: 호스트 기반 서비스 분기
- ✅ **보안**: 프라이빗 네트워크 및 인증 기반 접근 제어
