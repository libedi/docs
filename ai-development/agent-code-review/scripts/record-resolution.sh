#!/usr/bin/env bash
# 사람이 내린 판정을 지적 단위로 기록한다. HTML 최종 확인에서 받은 답을 옮길 때 쓴다.
#
#   record-resolution.sh <target> <round> <index> <resolution> [note...]
#
#   resolution
#     fixed        지적이 맞았고 고쳤다
#     wrong        리뷰어가 틀렸다                     → 리뷰어 지시문을 고칠 신호
#     intentional  일부러 그렇게 했다 (리뷰어가 사정을 몰랐다) → 스펙·MODULE_SPEC에 그 사정을 적을 신호
#     minor        맞지만 사소하다                     → 심각도 기준을 조정할 신호
#     harmful      따랐다면 코드가 나빠졌다              → 가장 위험한 유형, 따로 집계
#
# 결과는 review/<target>/resolutions.jsonl 에 한 줄씩 쌓인다. 같은 지적을 다시 판정하면 마지막 줄이 이긴다.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

target=${1:?target 필요}
round=${2:?round 필요}
index=${3:?findings 배열의 index 필요 (0부터)}
resolution=${4:?resolution 필요}
shift 4
note="$*"

[[ $round =~ ^[0-9]+$ && $index =~ ^[0-9]+$ ]] || { echo "round와 index는 숫자입니다" >&2; exit 2; }
case $resolution in
  fixed|wrong|intentional|minor|harmful) ;;
  *) echo "resolution은 fixed|wrong|intentional|minor|harmful 중 하나입니다" >&2; exit 2 ;;
esac

cd "$(git rev-parse --show-toplevel)"
dir=$(review_dir "$target")
[[ -e $dir/findings-$round.json ]] || { echo "findings-$round.json 이 없습니다: $target" >&2; exit 2; }

esc=${note//\\/\\\\}
esc=${esc//\"/\\\"}
esc=$(printf '%s' "$esc" | tr -d '\000-\037')
printf '{"target":"%s","round":%s,"index":%s,"resolution":"%s","note":"%s","at":"%s"}\n' \
  "$target" "$round" "$index" "$resolution" "$esc" "$(date -Iseconds)" >> "$dir/resolutions.jsonl"
echo "$target 회차 $round #$index → $resolution"
