#!/usr/bin/env bash
# 현재 작업 트리 상태를 커밋 없이 ref로 기록한다.
#
#   review-snapshot.sh <task-id> <phase>
#
# - pre-commit 훅이 돌지 않는다 (git commit 대신 commit-tree 사용)
# - 브랜치 로그에 남지 않는다 (refs/worktree/review/* 에만 기록)
# - 실제 staging 상태를 건드리지 않는다 (임시 인덱스 사용)
# - untracked 신규 파일도 포함한다 (.gitignore는 지킴)
# - refs/worktree/* 는 워크트리별 ref라서 병렬 워크트리끼리 충돌하지 않는다
#
# 보통 직접 부르지 않고 verify-and-snapshot.sh 가 호출한다.
set -euo pipefail

task=${1:?task-id 필요}
phase=${2:?phase 필요}

cd "$(git rev-parse --show-toplevel)"

idx=$(git rev-parse --git-path review-index)
trap 'rm -f "$idx"' EXIT

# 실제 인덱스를 복사해 stat 캐시를 재사용한다 (빈 인덱스에서 시작하면 전체 파일을 다시 해시함)
cp "$(git rev-parse --git-path index)" "$idx"
GIT_INDEX_FILE="$idx" git add -A
tree=$(GIT_INDEX_FILE="$idx" git write-tree)

commit=$(git commit-tree "$tree" -p HEAD -m "review snapshot: $task/$phase")
git update-ref "refs/worktree/review/$task/$phase" "$commit"
git update-ref refs/worktree/review/_last "$commit"

echo "$commit"
