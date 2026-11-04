#!/usr/bin/env bash
# 리뷰 에이전트가 파일 쓰기 권한 없이 결과를 남기는 유일한 통로.
#
#   record-findings.sh <target> [reviewer-tag] <<'EOF'
#   { "target": "T3", "round": 1, "findings": [ ... ] }
#   EOF
#   record-findings.sh <target> --blocked <<'EOF'      # review-status가 ready=no일 때 (TR-0/FR-0)
#   { "target": "T3", "findings": [ { "check": "TR-0", ... } ] }
#   EOF
#
# 파일 이름은 현재 회차(done 스냅샷 수)로 정한다: findings-<round>.json
# reviewer-tag를 주면 findings-<round>.<tag>.json 으로 따로 남는다. 다른 모델로 같은 스냅샷을
# 비교 리뷰할 때 쓰며, 수정 루프는 태그 없는 파일만 읽는다.
# 같은 회차의 파일이 이미 있으면 덮어쓰지 않고 실패한다.
# --blocked는 리뷰하지 못한 기록이라 회차와 무관하게 blocked-<k>.json으로 쌓인다.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

target=${1:?target 필요}
tag=${2:-}
blocked=""
if [[ $tag == --blocked ]]; then blocked=yes; tag=""; fi
[[ -z $tag || $tag =~ ^[A-Za-z0-9_-]+$ ]] || { echo "reviewer-tag는 영문·숫자·_·- 만 씁니다" >&2; exit 2; }

cd "$(git rev-parse --show-toplevel)"

dir=$(review_dir "$target")
mkdir -p "$dir"

if [[ -n $blocked ]]; then
  k=1
  while [[ -e $dir/blocked-$k.json ]]; do k=$((k + 1)); done
  out="$dir/blocked-$k.json"
else
  round=$(current_round "$target")
  [[ $round -gt 0 ]] || { echo "done 스냅샷이 없습니다: $target (리뷰할 수 없으면 --blocked로 기록)" >&2; exit 2; }
  out="$dir/findings-$round${tag:+.$tag}.json"
  [[ -e $out ]] && { echo "이미 기록된 회차입니다: $out" >&2; exit 2; }
fi

cat > "$out.tmp"

if command -v jq > /dev/null 2>&1; then
  if ! jq -e '
      (.findings | type == "array") and
      all(.findings[];
        has("check") and has("severity") and has("origin") and has("evidence") and
        (.severity | IN("blocker","major","minor","question")) and
        (.origin | IN("introduced","pre-existing")))' "$out.tmp" > /dev/null; then
    rm -f "$out.tmp"
    echo "형식 오류: findings 배열의 각 항목에 check, severity(blocker|major|minor|question), origin(introduced|pre-existing), evidence가 있어야 합니다" >&2
    exit 2
  fi
fi

mv "$out.tmp" "$out"
echo "$out"
