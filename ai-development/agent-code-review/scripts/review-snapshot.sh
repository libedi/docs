#!/usr/bin/env bash
# 현재 작업 트리 상태를 커밋 없이 ref로 기록한다. 같은 이름을 덮어쓰지 않고 번호를 붙인다.
#
#   review-snapshot.sh <target> <phase>      → 출력: <label> <commit>  (예: red-2 1a2b3c...)
#
# - pre-commit 훅이 돌지 않는다 (git commit 대신 commit-tree 사용)
# - 브랜치 로그에 남지 않는다 (refs/worktree/review/* 에만 기록)
# - 실제 staging 상태를 건드리지 않는다 (임시 인덱스 사용)
# - untracked 신규 파일도 포함한다 (.gitignore는 지킴)
# - refs/worktree/* 는 워크트리별 ref라서 병렬 워크트리끼리 충돌하지 않는다
#
# 보통 직접 부르지 않고 verify-and-snapshot.sh 가 호출한다.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

target=${1:?target(태스크 ID 또는 feature) 필요}
phase=${2:?phase 필요}

cd "$(git rev-parse --show-toplevel)"

tree=$(worktree_tree)
label=$(next_label "$target" "$phase")
mode=""
[[ $phase == red ]] && mode=nolast
commit=$(store_snapshot "$target" "$label" "$tree" HEAD "$mode")
echo "$label $commit"
