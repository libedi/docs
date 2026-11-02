#!/usr/bin/env bash
# feature 커밋 후 리뷰용 ref와 기록을 지운다. 워크트리를 지우면 함께 사라지지만,
# 같은 워크트리에서 다음 feature를 시작한다면 이 스크립트로 정리한다.
#
#   review-cleanup.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git for-each-ref --format='%(refname)' refs/worktree/review/ |
  while read -r ref; do git update-ref -d "$ref"; done

rm -rf "$(git rev-parse --git-path review)"
echo "리뷰 ref와 기록을 정리했습니다"
