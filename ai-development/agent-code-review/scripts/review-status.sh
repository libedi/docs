#!/usr/bin/env bash
# 리뷰 대상의 스냅샷·결과·회차를 요약하고, 이번 회차에 리뷰할 범위를 알려준다.
# 리뷰어와 메인 에이전트가 ref 이름을 직접 조립하지 않도록 이 출력을 기준으로 삼는다.
#
#   review-status.sh <target>
#
# 출력 (key=value)
#   round=<n>                 기록된 done 수. 이번 리뷰가 n회차
#   review_from / review_to   이번 회차의 리뷰 범위 (1회차: start→done-1, 2회차부터: fixbase-n 또는 done-(n-1)→done-n)
#   reds=<ref ...>            1회차: 태스크 안의 red 전부 / 2회차부터: 직전 done 이후의 red(수정 루프의 red)
#   previous_findings=<path>  직전 회차 findings (2회차부터)
#   gates=<ref>               feature 전용. 게이트 단계 변경의 기준
#   ready=yes|no              리뷰해도 되는지 (최신 done이 통과했고, 그 뒤에 실패한 검증이 없고, 가장 최근 gate가 통과했는가)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

target=${1:?target 필요}

cd "$(git rev-parse --show-toplevel)"
dir=$(review_dir "$target")

echo "target=$target"
for name in start gates; do
  ref=$(review_ref "$target" "$name")
  git show-ref --verify -q "$ref" && echo "$name=$ref"
done
ref=$(review_ref "$target" "fixbase-$(current_round "$target")")
git show-ref --verify -q "$ref" && echo "fixbase=$ref"

# 스냅샷 기록을 순번대로
declare -A seq_of=() exit_of=()
if [[ -d $dir ]]; then
  while IFS= read -r f; do
    label=$(result_value "$f" label)
    seq=$(result_value "$f" seq)
    seq_of[$label]=$seq
    exit_of[$label]=$(result_value "$f" exit_code)
    printf 'snapshot seq=%s label=%s exit=%s%s\n' "$seq" "$label" "$(result_value "$f" exit_code)" \
      "$(v=$(result_value "$f" red); [[ -n $v ]] && echo " red=$v")"
  done < <(for f in "$dir"/*.result; do [[ -e $f ]] && echo "$(result_value "$f" seq) $f"; done | sort -n | cut -d' ' -f2-)
  for f in "$dir"/findings-*.json; do [[ -e $f ]] && echo "findings=$f"; done
fi

round=$(current_round "$target")
echo "round=$round"
[[ $round -eq 0 ]] && { echo "ready=no"; exit 0; }

read -r from to < <(review_range "$target")
echo "review_from=$from"
echo "review_to=$to"

latest_seq=${seq_of[done-$round]:-0}
prev_seq=0
[[ $round -gt 1 ]] && prev_seq=${seq_of[done-$((round - 1))]:-0}
reds=()
for label in "${!seq_of[@]}"; do
  [[ $label == red-* ]] || continue
  s=${seq_of[$label]}
  if (( s > prev_seq && s < latest_seq )); then reds+=("$(review_ref "$target" "$label")"); fi
done
echo "reds=${reds[*]:-}"

if [[ $round -gt 1 && -e $dir/findings-$((round - 1)).json ]]; then
  echo "previous_findings=$dir/findings-$((round - 1)).json"
fi

# 가장 최근 done 이후에 실패한 검증(fail-n, 실패한 gate-n 등. red 제외)이 있으면 리뷰하지 않는다 (fail-closed)
latest_fail=0
for label in "${!seq_of[@]}"; do
  [[ $label == red-* || ${exit_of[$label]} == 0 ]] && continue
  if (( ${seq_of[$label]} > latest_fail )); then latest_fail=${seq_of[$label]}; fi
done
# gate가 있으면 가장 최근 gate가 통과해야 한다 (gate 실패 후 다시 돌리지 않고 smoke로 넘어간 경우)
latest_gate_seq=0 latest_gate_exit=0
for label in "${!seq_of[@]}"; do
  [[ $label == gate-* ]] || continue
  if (( ${seq_of[$label]} > latest_gate_seq )); then
    latest_gate_seq=${seq_of[$label]}
    latest_gate_exit=${exit_of[$label]}
  fi
done
rc=$(result_value "$dir/done-$round.result" exit_code 2>/dev/null || true)
if [[ $rc == 0 ]] && (( latest_fail < latest_seq )) && [[ $latest_gate_exit == 0 ]]; then
  echo "ready=yes"
else
  [[ $latest_gate_exit != 0 ]] && echo "reason=가장 최근 gate가 실패함"
  echo "ready=no"
fi
