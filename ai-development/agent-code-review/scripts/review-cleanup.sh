#!/usr/bin/env bash
# 리뷰용 ref와 기록을 지운다. 워크트리를 지우면 함께 사라지지만,
# 같은 워크트리에서 다음 feature를 시작한다면 이 스크립트로 정리한다.
# 지우기 전에 review-export.mjs로 지적·판정 기록을 남긴다.
#
#   review-cleanup.sh            모든 리뷰 ref와 기록 (feature 커밋 후)
#   review-cleanup.sh <prefix>   이름이 prefix로 시작하는 대상만 (예: eval-)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

prefix=${1:-}

cd "$(git rev-parse --show-toplevel)"

if [[ -z $prefix ]]; then
  git for-each-ref --format='%(refname)' "$review_ns/" |
    while read -r ref; do git update-ref -d "$ref"; done
  rm -rf "$(git rev-parse --git-path review)"
  echo "리뷰 ref와 기록을 모두 정리했습니다"
else
  [[ $prefix =~ ^[A-Za-z0-9_-]+$ ]] || { echo "prefix는 영문·숫자·_·- 만 씁니다" >&2; exit 2; }
  git for-each-ref --format='%(refname)' "$review_ns/" |
    while read -r ref; do
      if [[ ${ref#"$review_ns/"} == "$prefix"* ]]; then git update-ref -d "$ref"; fi
    done
  base=$(git rev-parse --git-path review)
  for d in "$base/$prefix"*; do
    if [[ -e $d ]]; then rm -rf "$d"; fi
  done
  echo "$prefix* 리뷰 ref와 기록을 정리했습니다"
fi
