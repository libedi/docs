#!/usr/bin/env bash
# 사람이 승인한 스냅샷과 실제로 커밋할 내용이 같은지 확인한다.
# 승인 후에 에이전트가 코드를 더 고쳤다면 승인은 의미가 없다.
#
#   review-approve.sh mark <ref|commit>                      HTML 최종 확인에서 승인한 스냅샷을 기록
#   review-approve.sh check [--index] [exclude-pathspec...]  승인 스냅샷과 비교
#
#   예) review-approve.sh mark refs/worktree/review/feature/done-2
#       review-approve.sh check docs/ '*MODULE_SPEC*.md' .kiro/            # 커밋 전, staging 전
#       review-approve.sh check --index docs/ '*MODULE_SPEC*.md' .kiro/    # pre-commit 훅 안
#
# check는 문서 업데이트 태스크가 바꾸는 경로(MODULE_SPEC, 가이드, 백로그)를 빼고 비교한다.
# 기본은 작업 트리 전체(신규 파일 포함)를 임시 인덱스로 찍어 비교한다.
# --index는 실제로 커밋될 인덱스를 비교한다. 부분 staging이 있을 수 있는 pre-commit 훅에서 쓴다.
# 종료 코드: 0 같음, 1 다름(다른 파일 목록 출력), 2 승인 기록 없음
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

cmd=${1:?mark 또는 check}
shift

cd "$(git rev-parse --show-toplevel)"
approved_ref="$review_ns/approved"

case $cmd in
  mark)
    target=$(git rev-parse --verify "${1:?승인할 ref 필요}^{commit}")
    git update-ref "$approved_ref" "$target"
    echo "승인 스냅샷: $target"
    ;;
  check)
    approved=$(git rev-parse -q --verify "$approved_ref") || { echo "승인 기록이 없습니다 (review-approve.sh mark)" >&2; exit 2; }
    if [[ ${1:-} == --index ]]; then
      shift
      tree=$(git write-tree)
      what="인덱스"
    else
      tree=$(worktree_tree)
      what="작업 트리"
    fi
    specs=(.)
    for p in "$@"; do specs+=(":(exclude)$p"); done
    if git diff --quiet "$approved" "$tree" -- "${specs[@]}"; then
      echo "$what가 승인한 스냅샷과 같습니다 (제외: ${*:-없음})"
    else
      echo "승인 이후 바뀐 파일이 있습니다 ($what 기준):" >&2
      git diff --name-status "$approved" "$tree" -- "${specs[@]}" >&2
      exit 1
    fi
    ;;
  *) echo "mark 또는 check" >&2; exit 2 ;;
esac
