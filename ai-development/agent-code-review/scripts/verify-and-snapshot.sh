#!/usr/bin/env bash
# 검증 명령 실행과 스냅샷을 한 번에 수행한다. 에이전트가 순서를 지키는 데 기대지 않기 위한 스크립트.
#
#   verify-and-snapshot.sh <target> <phase> <gradle-args>...
#
#   예) verify-and-snapshot.sh T3 red  :settlement:test --tests '*DiscountPolicyTest'  # 실패해야 정상
#       verify-and-snapshot.sh T3 done :settlement:test                                # 태스크 완료 조건
#       verify-and-snapshot.sh T4 done :settlement:compileJava                         # TDD 비대상 태스크
#       verify-and-snapshot.sh feature gate jacocoTestReport                           # JaCoCo 태스크 (회차에 안 들어감)
#       verify-and-snapshot.sh feature done build                                      # smoke test = feature 스냅샷
#
# 스냅샷은 덮어쓰지 않고 번호가 붙는다(red-1, red-2, done-1, done-2 ...).
#   - done 검증이 실패하면 fail-n으로 남는다. done-n은 통과한 검증만이다.
#   - red, done 외의 phase(예: gate)는 증거로만 남고 리뷰 회차에 들어가지 않는다.
#   - 한 태스크 안에서 red를 여러 번 확인해도 모두 남는다.
#   - 리뷰 지적을 고칠 때의 red도 따로 남는다. 이 red가 실패하지 않으면(exit 3) 지적한 버그가 재현되지 않은 것이다.
#   - done-n의 n이 리뷰 회차다. 2회차부터는 done-(n-1)→done-n 차이만 리뷰한다.
#
# compileJava가 spotlessApply에 의존하므로, 스냅샷은 항상 포맷이 적용된 뒤의 상태다.
# (단, 문법 오류로 spotlessApply 자체가 실패하면 포맷 전 상태가 기록된다)
#
# 결과는 git 디렉터리 안(워크트리별 경로)에 남는다. 작업 트리를 더럽히지 않는다.
#   <git-path>/review/<target>/<label>.result         exit code, red 판정, 스냅샷 id, 순번
#   <git-path>/review/<target>/<label>-test-results/  테스트 결과 XML 사본 (test 태스크 하나일 때)
#
# 종료 코드
#   red  : 테스트가 실패하면 0 (Red 확인), 통과하면 3 (Red가 아님 / 재현 실패)
#   그 외 : gradle 종료 코드 그대로
#   4    : 스냅샷 실패
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

target=${1:?target(태스크 ID 또는 feature) 필요}
phase=${2:?phase 필요}
shift 2
[[ $# -gt 0 ]] || { echo "gradle 인자 필요" >&2; exit 2; }
args=("$@")

cd "$(git rev-parse --show-toplevel)"

./gradlew "${args[@]}"
rc=$?

# 검증에 실패한 done은 done-n이 아니라 fail-n으로 남긴다. 리뷰 회차(done-n)는 통과한 검증만 센다.
snap_phase=$phase
[[ $phase == done && $rc -ne 0 ]] && snap_phase=fail
mode=""
[[ $snap_phase != done ]] && mode=nolast   # 다음 태스크의 기준(_last)은 통과한 done만 된다

tree=$(worktree_tree) || exit 4
label=$(next_label "$target" "$snap_phase") || exit 4
commit=$(store_snapshot "$target" "$label" "$tree" HEAD "$mode") || exit 4

verdict=""
if [[ $phase == red ]]; then
  if [[ $rc -ne 0 ]]; then verdict=confirmed; else verdict=not-red; fi
fi
write_result "$target" "$label" "$phase" "$rc" "$commit" "$verdict" "${args[*]}"

# 테스트 태스크가 하나면(:a:b:test, 필터 인자는 무관) 결과 XML 사본 보존
dir=$(review_dir "$target")
test_tasks=()
for a in "${args[@]}"; do [[ $a == *:test || $a == test ]] && test_tasks+=("$a"); done
if [[ ${#test_tasks[@]} -eq 1 ]]; then
  mod=${test_tasks[0]%test}
  mod=${mod%:}
  mod=${mod#:}
  mod=${mod//://}
  src="${mod:+$mod/}build/test-results/test"
  [[ -d $src ]] && cp -r "$src" "$dir/$label-test-results"
fi

if [[ $phase == red ]]; then
  if [[ $verdict == confirmed ]]; then
    echo "RED 확인: ${args[*]} 실패 (exit $rc), 스냅샷 $target/$label 기록"
    exit 0
  fi
  echo "RED 아님: 테스트가 이미 통과합니다 (스냅샷 $target/$label). 새 테스트가 새 동작을 검증하는지, 리뷰 지적이 재현되는지 확인하세요." >&2
  exit 3
fi

echo "$phase 기록: 스냅샷 $target/$label (exit $rc)"
exit $rc
