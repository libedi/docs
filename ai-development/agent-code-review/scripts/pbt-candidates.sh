#!/usr/bin/env bash
# 속성 기반 테스트(jqwik)를 약하게 만드는 변경의 후보를 결정론적으로 뽑는다.
# 판정은 하지 않는다. 후보 목록만 리뷰어에게 넘긴다 (TR-1, TR-2).
#
#   pbt-candidates.sh <target> [test-source-glob]
#
# 범위는 review-status.sh와 같다 (이번 회차의 review_from → review_to, 그 안의 red).
#   1) red 이후 테스트 변경 (TR-2 후보): 각 red → review_to 사이에서 아래 패턴이 들어오거나 빠지거나 바뀐 줄
#   2) 이번 범위에 새로 들어온 약화 설정 (TR-1 후보): review_from → review_to 사이에 추가된 줄 중
#      설정·가정·필터만 (생성 범위는 새 테스트라면 당연히 있으므로 1)에서 바뀐 경우만 본다)
#   3) 테스트 설정 파일 변경: build.gradle(.kts), junit-platform.properties, jqwik.properties
#
# 패턴: tries, seed, edgeCases, maxDiscardRatio, shrinking, generation, afterFailure,
#       Assume / assumeThat, .filter(, 생성 범위(between, lessOrEqual, greaterOrEqual, ofMinLength,
#       ofMaxLength, ofSize, ofMinSize, ofMaxSize, withMaxDepth, numeric 범위 어노테이션), @Disabled
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

target=${1:?target 필요}
glob=${2:-'*src/test/**/*.java'}

cd "$(git rev-parse --show-toplevel)"

status=$("$here/review-status.sh" "$target")
from=$(sed -n 's/^review_from=//p' <<< "$status")
to=$(sed -n 's/^review_to=//p' <<< "$status")
reds=$(sed -n 's/^reds=//p' <<< "$status")
[[ -n $from && -n $to ]] || { echo "리뷰 범위가 없습니다: $target (done 스냅샷 필요)" >&2; exit 2; }

pat='tries[[:space:]]*=|seed[[:space:]]*=|edgeCases[[:space:]]*=|maxDiscardRatio|shrinking[[:space:]]*=|generation[[:space:]]*=|afterFailure[[:space:]]*=|Assume[.]|assumeThat|[.]filter[(]|between[(]|lessOrEqual[(]|greaterOrEqual[(]|ofMinLength[(]|ofMaxLength[(]|ofSize[(]|ofMinSize[(]|ofMaxSize[(]|withMaxDepth[(]|@(IntRange|LongRange|ShortRange|ByteRange|DoubleRange|FloatRange|BigRange|CharRange|StringLength|Size|NotEmpty|Positive|Negative)\b|@Disabled'

# 2)에서 쓰는 패턴: 생성 범위를 뺀 설정·가정·필터
pat_added='tries[[:space:]]*=|seed[[:space:]]*=|edgeCases[[:space:]]*=|maxDiscardRatio|shrinking[[:space:]]*=|generation[[:space:]]*=|afterFailure[[:space:]]*=|Assume[.]|assumeThat|[.]filter[(]|@Disabled'

# git diff 출력에서 패턴에 맞는 +/- 줄을 "파일:줄: [+|-] 코드"로
scan() {
  local mode=$1; shift   # all: +/- 모두 (전체 패턴), added: + 만 (설정·가정·필터 패턴)
  local p=$pat
  [[ $mode == added ]] && p=$pat_added
  git diff --unified=0 "$@" -- "$glob" |
    awk -v pat="$p" -v mode="$mode" '
      /^--- a\// { old = substr($0, 7); next }
      /^\+\+\+ b\// { file = substr($0, 7); next }
      /^\+\+\+ \/dev\/null/ { file = old; next }
      /^@@/ {
        split($2, o, ","); ol = substr(o[1], 2)
        split($3, n, ","); nl = substr(n[1], 2)
        next
      }
      /^-/ { code = substr($0, 2); if (mode == "all" && code ~ pat) print old ":" ol ": [-] " code; ol++; next }
      /^\+/ { code = substr($0, 2); if (code ~ pat) print file ":" nl ": [+] " code; nl++; next }
    '
}

found=0
echo "target=$target"
echo "range=$from -> $to"

echo "## red 이후 테스트 변경 (TR-2 후보)"
if [[ -z $reds ]]; then
  echo "(범위 안에 red 스냅샷 없음)"
else
  for red in $reds; do
    out=$(scan all "$red" "$to")
    if [[ -n $out ]]; then echo "### ${red##*/} -> ${to##*/}"; echo "$out"; found=1; fi
  done
fi

echo "## 이번 범위에 새로 들어온 약화 설정 (TR-1 후보)"
out=$(scan added "$from" "$to")
if [[ -n $out ]]; then echo "$out"; found=1; else echo "(없음)"; fi

echo "## 테스트 설정 파일 변경"
cfg=$(git diff --name-status "$from" "$to" -- '*build.gradle' '*build.gradle.kts' '*junit-platform.properties' '*jqwik.properties')
if [[ -n $cfg ]]; then echo "$cfg"; found=1; else echo "(없음)"; fi

echo "candidates=$([[ $found == 1 ]] && echo yes || echo no)"
