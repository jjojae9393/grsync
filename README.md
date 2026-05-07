# grsync

`grsync`는 `dev/main` 기반 rebase, ff-only merge, push를 일관된 절차로 자동화하는 Git CLI입니다.

핵심 목적:
- 브랜치 통합 전에 히스토리를 선형화(rebase)
- ff-only 정책으로 merge 안정성 유지
- 팀 내 통합 절차를 동일한 명령으로 표준화

## 설치 방법 (npm)

필수 조건:
- `git`
- Node.js 18+
- npm

### 1) npm Registry에서 전역 설치

```bash
npm install -g grsync-cli
```

### 2) 저장소에서 직접 전역 설치

```bash
git clone <repo-url>
cd grsync
npm install -g .
```

### 3) 개발 링크 설치

```bash
git clone <repo-url>
cd grsync
npm link
```

설치 확인:

```bash
grsync --help
```

제거:

```bash
npm uninstall -g grsync-cli
```

## 프로젝트 자동 등록

`grsync`를 Git 프로젝트에서 처음 실행하면, 해당 프로젝트에 로컬 설정을 자동 등록합니다.

- 저장 위치: `.git/grsync/config`
- 특징: Git 추적 대상이 아니므로 작업 트리를 더럽히지 않음
- 포함 값: `remote`, `main branch`, `dev branch`

초기화(강제 재생성):

```bash
grsync --init
```

현재 설정 확인:

```bash
grsync --show-config
```

## 기본 사용

### 도움말

```bash
grsync --help
```

### to-dev (기본 모드)

현재 브랜치(또는 지정 브랜치)를 `dev`에 rebase/ff-only 반영 후 push합니다.

```bash
grsync
# 또는
grsync -b feature/user-auth
```

### to-main 모드

`dev`를 `main` 기준으로 rebase한 뒤 `main`에 ff-only 반영합니다.

```bash
grsync --to-main -m main -d dev
```

### squash 반영

작업 브랜치 커밋을 1개로 합친 뒤 `dev`에 반영합니다.

```bash
grsync -b feature/user-auth --squash -c "feat: integrate user auth"
```

## 주요 옵션

- `--to-main`: `dev -> main` 동기화 모드
- `--to-dev`: `target -> dev` 동기화 모드 (기본값)
- `--branch <name>`, `-b <name>`: 대상 브랜치
- `--main-branch <name>`, `-m <name>`: 메인 브랜치
- `--dev-branch <name>`, `-d <name>`: 개발 브랜치
- `--remote <name>`, `-r <name>`: 원격 이름
- `--squash`: to-dev에서 대상 커밋 squash
- `--commit <text>`, `-c <text>`: squash 커밋 메시지
- `--max-push-retry <num>`: push 재시도 횟수
- `--dry-run`: 변경 없이 명령만 출력
- `--yes`, `-y`: 확인 프롬프트 생략
- `--init`: 프로젝트 로컬 설정 강제 초기화
- `--show-config`: 현재 프로젝트 적용 설정 출력

## 권장 명령 순서

1. 모드: `--to-main` / `--to-dev`
2. 브랜치: `-b`, `-m`, `-d`
3. 동작: `--squash`, `-c`
4. 제어: `-r`, `--dry-run`, `-y`

예시:

```bash
grsync --to-dev -b feature/test --squash -c "feat: merge feature test" --dry-run
grsync --to-main -m main -d dev -y
```

## 오류 대응

- `원격 브랜치가 없습니다`
  - `-r`, `-m`, `-d` 옵션 또는 `grsync --init`으로 설정 재생성
- `작업 트리가 깨끗하지 않습니다`
  - 커밋/스태시 후 재실행
- `push 재시도 한도 초과`
  - 원격 최신 이력 확인 후 수동 rebase/merge
