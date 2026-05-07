#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="git-rebase-sync"
readonly DEFAULT_REMOTE="origin"
readonly DEFAULT_MAIN_BRANCH="main"
readonly DEFAULT_DEV_BRANCH="dev"
readonly DEFAULT_MAX_PUSH_RETRY=5

MODE="to-dev"
REMOTE="${DEFAULT_REMOTE}"
MAIN_BRANCH="${DEFAULT_MAIN_BRANCH}"
DEV_BRANCH="${DEFAULT_DEV_BRANCH}"
MAX_PUSH_RETRY="${MAX_PUSH_RETRY:-${DEFAULT_MAX_PUSH_RETRY}}"
DRY_RUN=false
AUTO_CONFIRM=false
RETURN_TO_ORIGINAL_BRANCH=true
TARGET_BRANCH=""

ORIGINAL_BRANCH=""

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

warn() {
  printf '[%s] WARN: %s\n' "${SCRIPT_NAME}" "$*" >&2
}

die() {
  printf '[%s] ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Usage:
  ${SCRIPT_NAME} [target-branch]
  ${SCRIPT_NAME} --to-main [main-branch] [dev-branch]
  ${SCRIPT_NAME} [options]

Modes:
  default (to-dev):
    1) update dev from origin (ff-only)
    2) rebase target branch on dev
    3) fast-forward merge target -> dev
    4) push dev to origin with retry

  --to-main:
    1) update main/dev from origin (ff-only)
    2) rebase dev on main
    3) force-with-lease push dev
    4) fast-forward merge dev -> main
    5) push main to origin with retry

Options:
  --to-main                 Run dev -> main sync flow
  --to-dev                  Run target -> dev sync flow (default)
  --branch <name>           Target branch for to-dev flow
  --main-branch <name>      Main branch name (default: ${DEFAULT_MAIN_BRANCH})
  --dev-branch <name>       Dev branch name (default: ${DEFAULT_DEV_BRANCH})
  --remote <name>           Remote name (default: ${DEFAULT_REMOTE})
  --max-push-retry <num>    Push retry count (default: ${DEFAULT_MAX_PUSH_RETRY})
  --dry-run                 Print git commands without executing mutating commands
  --yes, -y                 Skip confirmation prompts
  --help, -h                Show this help

Examples:
  ${SCRIPT_NAME} feature/twice/order-new-option
  ${SCRIPT_NAME} --branch feature/twice/order-new-option
  ${SCRIPT_NAME} --to-main
  ${SCRIPT_NAME} --to-main --main-branch main --dev-branch dev --yes
USAGE
}

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '+ %q' "$1"
    shift
    for arg in "$@"; do
      printf ' %q' "${arg}"
    done
    printf '\n'
    return 0
  fi

  "$@"
}

git_cmd() {
  run_cmd git "$@"
}

ensure_inside_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Git 저장소에서 실행하세요."
}

ensure_required_command() {
  command -v "$1" >/dev/null 2>&1 || die "필수 명령어를 찾을 수 없습니다: $1"
}

require_non_empty_branch() {
  local branch="$1"
  [[ -n "${branch}" ]] || die "브랜치 이름이 비어 있습니다."
}

require_local_branch() {
  local branch="$1"
  require_non_empty_branch "${branch}"

  git show-ref --verify --quiet "refs/heads/${branch}" || die "로컬 브랜치가 없습니다: ${branch}"
}

require_remote_branch() {
  local branch="$1"
  require_non_empty_branch "${branch}"

  git ls-remote --exit-code --heads "${REMOTE}" "${branch}" >/dev/null 2>&1 || die "원격 브랜치가 없습니다: ${REMOTE}/${branch}"
}

require_clean_worktree() {
  git diff --quiet || die "작업 트리가 깨끗하지 않습니다. 커밋 또는 스태시 후 다시 실행하세요."
  git diff --cached --quiet || die "스테이징된 변경사항이 있습니다. 커밋 또는 스태시 후 다시 실행하세요."
}

require_detached_head_absent() {
  ORIGINAL_BRANCH="$(git branch --show-current)"
  [[ -n "${ORIGINAL_BRANCH}" ]] || die "detached HEAD 상태에서는 실행할 수 없습니다."
}

require_distinct_branches() {
  local branch_a="$1"
  local branch_b="$2"

  [[ "${branch_a}" != "${branch_b}" ]] || die "동일한 브랜치로는 진행할 수 없습니다: ${branch_a}"
}

validate_positive_integer() {
  local value="$1"
  [[ "${value}" =~ ^[1-9][0-9]*$ ]] || die "양의 정수만 허용됩니다: ${value}"
}

checkout_branch() {
  local branch="$1"
  git_cmd switch "${branch}"
}

update_branch_from_remote_ff_only() {
  local branch="$1"

  checkout_branch "${branch}"
  git_cmd fetch "${REMOTE}" "${branch}"
  git_cmd pull --ff-only "${REMOTE}" "${branch}"
}

confirm_or_die() {
  local message="$1"

  if [[ "${AUTO_CONFIRM}" == "true" ]]; then
    return 0
  fi

  read -r -p "[${SCRIPT_NAME}] ${message} [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      die "사용자 확인으로 중단되었습니다."
      ;;
  esac
}

push_with_retry() {
  local branch="$1"
  local merge_source_branch="${2:-}"
  local force_mode="${3:-normal}"
  local push_try=1

  while true; do
    if [[ "${force_mode}" == "force-with-lease" ]]; then
      if git_cmd push --force-with-lease "${REMOTE}" "${branch}"; then
        return 0
      fi
    else
      if git_cmd push "${REMOTE}" "${branch}"; then
        return 0
      fi
    fi

    if (( push_try >= MAX_PUSH_RETRY )); then
      die "push 재시도 한도(${MAX_PUSH_RETRY})를 초과했습니다. 수동 확인이 필요합니다."
    fi

    log "push 거절됨. ${REMOTE}/${branch} 최신을 반영 후 재시도 (${push_try}/${MAX_PUSH_RETRY})"
    git_cmd pull --rebase "${REMOTE}" "${branch}"

    if [[ -n "${merge_source_branch}" ]]; then
      git_cmd merge --ff-only "${merge_source_branch}"
    fi

    push_try=$((push_try + 1))
  done
}

restore_original_branch() {
  if [[ "${RETURN_TO_ORIGINAL_BRANCH}" != "true" ]]; then
    return 0
  fi

  if [[ -z "${ORIGINAL_BRANCH}" ]]; then
    return 0
  fi

  local current_branch
  current_branch="$(git branch --show-current || true)"

  if [[ "${current_branch}" == "${ORIGINAL_BRANCH}" ]]; then
    return 0
  fi

  if git switch "${ORIGINAL_BRANCH}" >/dev/null 2>&1; then
    log "원래 브랜치로 복귀했습니다: ${ORIGINAL_BRANCH}"
    return 0
  fi

  warn "원래 브랜치(${ORIGINAL_BRANCH})로 자동 복귀하지 못했습니다. 수동 확인이 필요합니다."
}

on_exit() {
  local exit_code="$1"

  restore_original_branch

  if (( exit_code != 0 )); then
    warn "작업이 실패했습니다. 현재 브랜치/충돌 상태를 확인하세요."
  fi
}

parse_args() {
  local positional=()

  while (($# > 0)); do
    case "$1" in
      --)
        shift
        while (($# > 0)); do
          positional+=("$1")
          shift
        done
        ;;
      --to-main)
        MODE="to-main"
        shift
        ;;
      --to-dev)
        MODE="to-dev"
        shift
        ;;
      --branch)
        [[ $# -ge 2 ]] || die "--branch 에 값이 필요합니다."
        TARGET_BRANCH="$2"
        shift 2
        ;;
      --main-branch)
        [[ $# -ge 2 ]] || die "--main-branch 에 값이 필요합니다."
        MAIN_BRANCH="$2"
        shift 2
        ;;
      --dev-branch)
        [[ $# -ge 2 ]] || die "--dev-branch 에 값이 필요합니다."
        DEV_BRANCH="$2"
        shift 2
        ;;
      --remote)
        [[ $# -ge 2 ]] || die "--remote 에 값이 필요합니다."
        REMOTE="$2"
        shift 2
        ;;
      --max-push-retry)
        [[ $# -ge 2 ]] || die "--max-push-retry 에 값이 필요합니다."
        MAX_PUSH_RETRY="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --yes|-y)
        AUTO_CONFIRM=true
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      -*)
        die "알 수 없는 옵션입니다: $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [[ "${MODE}" == "to-main" ]]; then
    if [[ ${#positional[@]} -ge 1 ]]; then
      MAIN_BRANCH="${positional[0]}"
    fi

    if [[ ${#positional[@]} -ge 2 ]]; then
      DEV_BRANCH="${positional[1]}"
    fi

    if [[ ${#positional[@]} -ge 3 ]]; then
      die "--to-main 모드 positional 인자는 최대 2개(main, dev)까지 허용됩니다."
    fi
    return 0
  fi

  if [[ ${#positional[@]} -ge 1 && -z "${TARGET_BRANCH}" ]]; then
    TARGET_BRANCH="${positional[0]}"
  fi

  if [[ ${#positional[@]} -ge 2 ]]; then
    die "to-dev 모드 positional 인자는 최대 1개(target)만 허용됩니다."
  fi
}

sync_to_dev() {
  local target_branch="${TARGET_BRANCH:-$(git branch --show-current)}"

  require_non_empty_branch "${target_branch}"
  require_distinct_branches "${target_branch}" "${DEV_BRANCH}"
  require_local_branch "${target_branch}"
  require_local_branch "${DEV_BRANCH}"
  require_remote_branch "${DEV_BRANCH}"

  log "실행 계획: ${target_branch} -> ${DEV_BRANCH} (remote: ${REMOTE})"
  confirm_or_die "${DEV_BRANCH} 브랜치를 원격에 push 합니다. 계속할까요?"

  log "1) ${DEV_BRANCH} 업데이트 (ff-only)"
  update_branch_from_remote_ff_only "${DEV_BRANCH}"

  log "2) ${target_branch} rebase ${DEV_BRANCH}"
  checkout_branch "${target_branch}"
  git_cmd rebase "${DEV_BRANCH}"

  log "3) ${DEV_BRANCH} 에 ff-only merge"
  checkout_branch "${DEV_BRANCH}"
  git_cmd merge --ff-only "${target_branch}"

  log "4) origin/${DEV_BRANCH} push (거절 시 rebase 후 재시도)"
  push_with_retry "${DEV_BRANCH}"

  log "완료: ${DEV_BRANCH} <- ${target_branch} (ff-only + push)"
}

sync_to_main() {
  require_distinct_branches "${MAIN_BRANCH}" "${DEV_BRANCH}"
  require_local_branch "${MAIN_BRANCH}"
  require_local_branch "${DEV_BRANCH}"
  require_remote_branch "${MAIN_BRANCH}"
  require_remote_branch "${DEV_BRANCH}"

  log "실행 계획: ${DEV_BRANCH} rebase ${MAIN_BRANCH}, then ${MAIN_BRANCH} <- ${DEV_BRANCH}"
  confirm_or_die "${DEV_BRANCH} 브랜치를 force-with-lease push 합니다. 계속할까요?"

  log "1) ${MAIN_BRANCH} 업데이트 (ff-only)"
  update_branch_from_remote_ff_only "${MAIN_BRANCH}"

  log "2) ${DEV_BRANCH} 업데이트 (ff-only)"
  update_branch_from_remote_ff_only "${DEV_BRANCH}"

  log "3) ${DEV_BRANCH} rebase ${MAIN_BRANCH}"
  checkout_branch "${DEV_BRANCH}"
  git_cmd rebase "${MAIN_BRANCH}"

  log "4) origin/${DEV_BRANCH} force-with-lease push"
  push_with_retry "${DEV_BRANCH}" "" "force-with-lease"

  log "5) ${MAIN_BRANCH} 에 ff-only merge"
  checkout_branch "${MAIN_BRANCH}"
  git_cmd merge --ff-only "${DEV_BRANCH}"

  log "6) origin/${MAIN_BRANCH} push (거절 시 rebase 후 재시도)"
  push_with_retry "${MAIN_BRANCH}" "${DEV_BRANCH}"

  log "완료: ${MAIN_BRANCH} <- ${DEV_BRANCH} (rebase + ff-only + push)"
}

main() {
  ensure_required_command git
  ensure_inside_git_repo
  parse_args "$@"

  validate_positive_integer "${MAX_PUSH_RETRY}"
  require_clean_worktree
  require_detached_head_absent

  trap 'on_exit "$?"' EXIT

  if [[ "${MODE}" == "to-main" ]]; then
    sync_to_main
    return 0
  fi

  sync_to_dev
}

main "$@"
