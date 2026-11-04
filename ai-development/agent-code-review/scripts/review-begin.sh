#!/usr/bin/env bash
# 리뷰 대상의 시작 기준점을 기록한다. 작업 트리를 새로 찍지 않고 기존 스냅샷이나 HEAD를 재사용한다.
#
#   review-begin.sh <task-id>       start = 직전 태스크의 마지막 스냅샷, 없으면 HEAD
#   review-begin.sh feature         start = HEAD (feature 전체 변경의 기준)
#                                   gates = 마지막 태스크의 마지막 스냅샷 (게이트 단계 변경의 기준)
#   review-begin.sh <task-id> --fix fixbase-<다음 회차> = 지금의 _last
#                                   태스크 지적을 고치기 시작할 때 부른다. 다른 태스크나 feature 게이트가
#                                   지나간 뒤에 고쳐도 재리뷰 범위에 이 수정만 들어간다.
#                                   feature는 그 뒤의 모든 변경이 재리뷰 대상이므로 --fix를 쓰지 않는다.
#
# feature는 마지막 개발 태스크가 끝나고 게이트(JaCoCo, smoke) 태스크를 시작하기 전에 부른다.
# 기준점들은 모두 spotlessApply가 끝난 상태라서 포맷 노이즈가 diff에 섞이지 않는다.
# (HEAD는 pre-commit 훅이, 스냅샷은 compileJava가 포맷을 보장)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

target=${1:?task-id 또는 feature 필요}
mode=${2:-}

cd "$(git rev-parse --show-toplevel)"

last=$(git rev-parse -q --verify "$review_ns/_last" || git rev-parse HEAD)

if [[ $mode == --fix ]]; then
  [[ $target == feature ]] && { echo "feature는 --fix 없이 done-(n-1)부터 봅니다" >&2; exit 2; }
  round=$(current_round "$target")
  [[ $round -gt 0 ]] || { echo "아직 done 스냅샷이 없습니다: $target" >&2; exit 2; }
  next=$((round + 1))
  git update-ref "$(review_ref "$target" "fixbase-$next")" "$last"
  echo "$target/fixbase-$next = $last (수정 후 $next회차 리뷰의 시작점)"
  exit 0
elif [[ -n $mode ]]; then
  echo "알 수 없는 옵션: $mode" >&2; exit 2
fi

if [[ $target == feature ]]; then
  head=$(git rev-parse HEAD)
  git update-ref "$(review_ref feature start)" "$head"
  git update-ref "$(review_ref feature gates)" "$last"
  echo "feature/start = $head (HEAD)"
  echo "feature/gates = $last"
else
  git update-ref "$(review_ref "$target" start)" "$last"
  echo "$target/start = $last"
fi
