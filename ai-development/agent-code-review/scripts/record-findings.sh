#!/usr/bin/env bash
# 리뷰 에이전트가 파일 쓰기 권한 없이 결과를 남기는 유일한 통로.
#
#   record-findings.sh <task-id|feature> <<'EOF'
#   { "target": "T3", "findings": [ ... ] }
#   EOF
#
# 회차마다 findings-1.json, findings-2.json ... 으로 쌓인다.
# 메인 에이전트는 리뷰 에이전트의 응답 텍스트가 아니라 이 파일을 읽는다.
set -euo pipefail

target=${1:?task-id 또는 feature 필요}

cd "$(git rev-parse --show-toplevel)"

dir=$(git rev-parse --git-path "review/$target")
mkdir -p "$dir"

n=1
while [[ -e "$dir/findings-$n.json" ]]; do n=$((n + 1)); done
out="$dir/findings-$n.json"

cat > "$out.tmp"

if command -v jq > /dev/null 2>&1; then
  if ! jq -e '.findings | type == "array"' "$out.tmp" > /dev/null; then
    rm -f "$out.tmp"
    echo "형식 오류: 최상위에 findings 배열이 있어야 합니다" >&2
    exit 2
  fi
fi

mv "$out.tmp" "$out"
echo "$out"
