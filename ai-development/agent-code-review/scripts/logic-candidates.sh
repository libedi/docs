#!/usr/bin/env bash
# TDD 비대상 태스크(인터페이스·VO)에 들어온 로직 후보를 결정론적으로 뽑는다.
# 판정은 하지 않는다. 후보 목록만 리뷰 에이전트에게 넘긴다.
#
#   logic-candidates.sh <task-id> [main-source-glob]
#
# 기본 대상은 src/main 아래 Java 파일. 멀티모듈이면 '*/src/main/**/*.java' 처럼 넘긴다.
set -euo pipefail

task=${1:?task-id 필요}
glob=${2:-'*src/main/**/*.java'}

cd "$(git rev-parse --show-toplevel)"

from="refs/worktree/review/$task/start"
to="refs/worktree/review/$task/done"

# 추가된 줄 중 분기·검증·반복·계산의 흔적
# (awk마다 \b 지원이 달라서 단어 경계를 문자 클래스로 직접 표현한다)
kw='(if|else|switch|case|for|while|throw|try|catch)'
pattern="(^|[^A-Za-z0-9_])$kw([^A-Za-z0-9_]|\$)|[?][^:]*:|[.](filter|map|reduce|sorted)[(]|BigDecimal|RoundingMode|Math[.]"

git diff --unified=0 "$from" "$to" -- "$glob" |
  awk -v pat="$pattern" '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^@@/ { split($3, a, ","); line = substr(a[1], 2); next }
    /^\+/ { code = substr($0, 2); if (code ~ pat) print file ":" line ": " code; line++ }
  '
