# grsync

`dev/main` 브랜치 동기화를 안전하게 자동화하는 스크립트를 제공합니다.

## 스크립트 위치

- `scripts/git-rebase-sync.sh`

## 설치 방법

### 1) 저장소 준비

```bash
git clone <repo-url>
cd grsync
```

### 2) 실행 권한 확인

```bash
chmod +x scripts/git-rebase-sync.sh
```

### 3) Git/브랜치 확인

```bash
git --version
git branch -a
```

필수 조건:
- `git` 명령어가 설치되어 있어야 합니다.
- 원격(`origin`)에 동기화 대상 브랜치가 있어야 합니다.
- 작업 트리가 깨끗해야 합니다.

## 사용 방법

### `grsync` 명령으로 등록해서 사용하기 (권장)

매번 `scripts/git-rebase-sync.sh`를 입력하지 않으려면 심볼릭 링크를 만들어 `grsync`로 실행할 수 있습니다.

1) 사용자 실행 경로 준비

```bash
mkdir -p "$HOME/.local/bin"
```

2) `grsync` 링크 생성

```bash
ln -sf "$(pwd)/scripts/git-rebase-sync.sh" "$HOME/.local/bin/grsync"
```

`$(pwd)`는 "현재 터미널이 위치한 폴더의 절대경로"를 의미합니다. 따라서 이 명령은 현재 `grsync` 폴더 안의 스크립트를 `grsync` 명령으로 연결합니다.

3) `PATH` 등록 (`zsh`, 1회)

```bash
grep -q 'HOME/.local/bin' "$HOME/.zshrc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
source "$HOME/.zshrc"
```

4) 동작 확인

```bash
grsync --help
```

`zsh`가 아닌 쉘을 쓰는 경우에는 해당 쉘 프로필 파일(`~/.bashrc` 등)에 동일한 `PATH` 설정을 추가하면 됩니다.

### 도움말

```bash
scripts/git-rebase-sync.sh --help
```

### 기본 모드: 작업 브랜치 -> dev 동기화

현재 브랜치를 `dev`에 fast-forward 가능한 형태로 반영하고 `origin/dev`까지 push합니다.

```bash
scripts/git-rebase-sync.sh
```

특정 브랜치를 명시해서 실행할 수도 있습니다.

```bash
scripts/git-rebase-sync.sh feature/twice/order-new-option
# 또는
scripts/git-rebase-sync.sh --branch feature/twice/order-new-option
```

실행 흐름:
1. `dev`를 원격 기준으로 `ff-only` 업데이트
2. 대상 브랜치를 `dev` 기준으로 `rebase`
3. `dev`에 `--ff-only` 머지
4. `origin/dev` push (거절 시 rebase 후 재시도)

### 메인 반영 모드: dev -> main 동기화

`dev`를 `main` 기준으로 rebase한 뒤 `main`에 fast-forward merge하여 배포용 히스토리를 정리합니다.

```bash
scripts/git-rebase-sync.sh --to-main
```

브랜치 이름이 다르면 명시할 수 있습니다.

```bash
scripts/git-rebase-sync.sh --to-main --main-branch main --dev-branch dev
```

실행 흐름:
1. `main`, `dev`를 원격 기준으로 `ff-only` 업데이트
2. `dev`를 `main` 위로 rebase
3. `origin/dev`에 `--force-with-lease` push
4. `main`에 `--ff-only` merge
5. `origin/main` push (거절 시 rebase 후 재시도)

## 주요 옵션

- `--to-main`: `dev -> main` 동기화 모드 실행
- `--to-dev`: `target -> dev` 동기화 모드 실행(기본값)
- `--branch <name>`: `to-dev` 모드의 대상 브랜치 지정
- `--main-branch <name>`: 메인 브랜치 이름 지정
- `--dev-branch <name>`: 개발 브랜치 이름 지정
- `--remote <name>`: 원격 이름 지정(기본 `origin`)
- `--max-push-retry <num>`: push 재시도 횟수 지정
- `--dry-run`: 실제 변경 없이 실행 명령만 출력
- `--yes`, `-y`: 확인 프롬프트 건너뛰기

## 추천 실행 예시

변경 전 시뮬레이션:

```bash
scripts/git-rebase-sync.sh --dry-run --branch feature/twice/order-new-option
```

CI/자동화 환경(프롬프트 없이):

```bash
scripts/git-rebase-sync.sh --yes --branch feature/twice/order-new-option
```

커스텀 원격 사용:

```bash
scripts/git-rebase-sync.sh --remote upstream --branch feature/twice/order-new-option
```

## 안전장치

- 작업 트리 dirty 상태면 즉시 중단합니다.
- detached HEAD 상태면 중단합니다.
- 로컬/원격 브랜치 존재 여부를 검증합니다.
- 작업 종료 시 원래 브랜치로 복귀를 시도합니다.
- 실패 시 경고 메시지를 남기고 수동 점검이 가능하도록 중단합니다.

## 자주 발생하는 오류와 해결

- `원격 브랜치가 없습니다: origin/main`
  - 원격 브랜치명이 다를 수 있습니다.
  - `--main-branch`, `--dev-branch`, `--remote` 옵션으로 실제 이름을 맞춰 실행하세요.
- `작업 트리가 깨끗하지 않습니다`
  - `git status` 확인 후 커밋 또는 스태시하세요.
- `push 재시도 한도(...)를 초과했습니다`
  - 동시 반영 충돌 가능성이 큽니다.
  - 원격 최신 이력을 확인하고 수동으로 rebase/merge 후 다시 실행하세요.

## 운영 권장 순서

1. `--dry-run`으로 명령 흐름 확인
2. 팀과 대상 브랜치/타이밍 공유
3. 실제 실행(`--yes`는 자동화에서만 사용 권장)
4. 실행 후 `git log --oneline --graph --decorate -20`으로 이력 확인
