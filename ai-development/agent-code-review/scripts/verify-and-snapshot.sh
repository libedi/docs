#!/usr/bin/env bash
# 검증 명령 실행과 스냅샷을 한 번에 수행한다. 에이전트가 순서를 지키는 데 기대지 않기 위한 스크립트.
#
#   verify-and-snapshot.sh <task-id> <phase> <gradle-task>...
#
#   예) verify-and-snapshot.sh T3 red  :settlement:test          # 실패해야 정상
#       verify-and-snapshot.sh T3 done :settlement:test          # 성공해야 정상
#       verify-and-snapshot.sh T4 done :settlement:compileJava   # TDD 비대상 태스크
#       verify-and-snapshot.sh feature done build                # smoke test 단계
#
# compileJava가 spotlessApply에 의존하므로, 스냅샷은 항상 포맷이 적용된 뒤의 상태다.
# (단, 문법 오류로 spotlessApply 자체가 실패하면 포맷 전 상태가 기록된다)
#
# 결과는 git 디렉터리 안(워크트리별 경로)에 남는다. 작업 트리를 더럽히지 않는다.
#   <git-path>/review/<task>/<phase>.result        exit code, 스냅샷 id 등
#   <git-path>/review/<task>/<phase>-test-results/ 테스트 결과 XML 사본 (단일 :모듈:test 일 때)
#
# 종료 코드
#   red  : 테스트가 실패하면 0 (Red 확인), 통과하면 3 (Red가 아님)
#   그 외 : gradle 종료 코드 그대로
set -uo pipefail

task=${1:?task-id 필요}
phase=${2:?phase 필요}
shift 2
[[ $# -gt 0 ]] || { echo "gradle 태스크 필요" >&2; exit 2; }
tasks=("$@")
here=$(cd "$(dirname "$0")" && pwd)

cd "$(git rev-parse --show-toplevel)"

./gradlew "${tasks[@]}"
rc=$?

commit=$("$here/review-snapshot.sh" "$task" "$phase") || exit 4

dir=$(git rev-parse --git-path "review/$task")
mkdir -p "$dir"
{
  echo "phase=$phase"
  echo "gradle_tasks=${tasks[*]}"
  echo "exit_code=$rc"
  echo "snapshot=$commit"
  echo "at=$(date -Iseconds)"
} > "$dir/$phase.result"

# 단일 :a:b:test → a/b/build/test-results/test 사본 보존
if [[ ${#tasks[@]} -eq 1 && ${tasks[0]} == *:test ]]; then
  mod=${tasks[0]%:test}
  mod=${mod#:}
  mod=${mod//://}
  src="${mod:+$mod/}build/test-results/test"
  rm -rf "$dir/$phase-test-results"
  [[ -d $src ]] && cp -r "$src" "$dir/$phase-test-results"
fi

if [[ $phase == red ]]; then
  if [[ $rc -ne 0 ]]; then
    echo "RED 확인: ${tasks[*]} 실패 (exit $rc), 스냅샷 $task/red 기록"
    exit 0
  fi
  echo "RED 아님: 테스트가 이미 통과합니다. 테스트가 새 동작을 검증하는지 확인하세요." >&2
  exit 3
fi

exit $rc
