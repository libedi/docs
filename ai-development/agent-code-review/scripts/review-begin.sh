#!/usr/bin/env bash
# 태스크 시작 기준점을 기록한다. 작업 트리를 새로 찍지 않고 직전 스냅샷을 재사용한다.
#
#   review-begin.sh <task-id>
#
# start(Tn) = 직전 태스크의 마지막 스냅샷, 없으면 HEAD.
# 둘 다 spotlessApply가 끝난 상태라서 포맷 노이즈가 diff에 섞이지 않는다.
# (HEAD는 pre-commit 훅이, 직전 스냅샷은 compileJava가 포맷을 보장)
set -euo pipefail

task=${1:?task-id 필요}

cd "$(git rev-parse --show-toplevel)"

base=$(git rev-parse -q --verify refs/worktree/review/_last || git rev-parse HEAD)
git update-ref "refs/worktree/review/$task/start" "$base"

echo "$task/start = $base"
