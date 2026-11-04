#!/usr/bin/env bash
# 리뷰어 평가(회귀 테스트) 사례 하나를 리뷰 가능한 스냅샷으로 만든다.
# 작업 트리와 실제 인덱스는 건드리지 않는다. 패치는 임시 인덱스에만 적용한다.
#
#   eval-setup.sh <case-dir>
#
# 사례 디렉터리 구성
#   case.env           base=<커밋>  kind=task|feature  type=tdd|non-tdd(task만)
#                      spec=<스펙 디렉터리>  module_spec=<MODULE_SPEC 경로>(feature만, 선택)  (경로는 사례 디렉터리 기준)
#   NN-<phase>.patch   phase는 base, red, done, gates 중 하나. NN 순서로 처리한다.
#                        base  → (선택, 맨 앞) start 상태를 만드는 준비 패치. base 커밋 기준
#                        red   → red-n 스냅샷 (테스트가 실패하는 상태로 기록)
#                        done  → done-n 스냅샷 (검증 통과로 기록)
#                        gates → feature 전용. gates 기준점 (마지막 개발 태스크가 끝난 상태)
#                      base를 뺀 모든 패치는 start 상태 기준이다(앞 패치에 이어 붙이지 않는다).
#                      start 상태는 base 패치가 있으면 base + base 패치, 없으면 base 커밋이다.
#                      만드는 법: git diff <start 상태> <그 단계의 상태> > NN-<phase>.patch
#   expected.json      정답. {"findings":[{"check":"TR-2","file":"DiscountPolicyTest.java","line":42}]}
#                      버그가 없는 사례는 {"findings":[]}
#
# 대상 이름은 eval-<사례 디렉터리 이름>이다. 같은 대상의 이전 기록은 지우고 새로 만든다.
# 평가용 스냅샷은 _last를 건드리지 않지만, 진행 중인 feature와 섞이지 않게 별도 워크트리에서 돌리기를 권한다.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=review-lib.sh
. "$here/review-lib.sh"

case_dir=$(cd "${1:?case-dir 필요}" && pwd)
name=$(basename "$case_dir")
target="eval-$name"

cd "$(git rev-parse --show-toplevel)"
root=$(pwd)

meta() { sed -n "s/^$1=//p" "$case_dir/case.env" | head -n 1; }
b=$(meta base)
base=$(git rev-parse --verify "${b:-HEAD}^{commit}")
kind=$(meta kind); kind=${kind:-task}
type=$(meta type)
spec=$(meta spec)
module_spec=$(meta module_spec)

# 저장소 기준 상대 경로 (GNU realpath 없이)
rel() {
  local p
  p=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  case $p in "$root"/*) echo "${p#"$root"/}" ;; *) echo "$p" ;; esac
}

# 이전 기록 정리 (정확히 이 대상만)
git for-each-ref --format='%(refname)' "$review_ns/$target/" | while read -r ref; do git update-ref -d "$ref"; done
rm -rf "$(review_dir "$target")"

idx=$(git rev-parse --git-path "review-eval-index")
trap 'rm -f "$idx"' EXIT

shopt -s nullglob
patches=("$case_dir"/[0-9][0-9]-*.patch)
[[ ${#patches[@]} -gt 0 ]] || { echo "패치가 없습니다: $case_dir" >&2; exit 2; }

# start 상태: base 커밋, 또는 맨 앞의 base 패치를 적용한 상태
start_commit=$base
first=$(basename "${patches[0]}" .patch); first=${first#[0-9][0-9]-}
if [[ $first == base ]]; then
  GIT_INDEX_FILE="$idx" git read-tree "$base"
  GIT_INDEX_FILE="$idx" git apply --cached "${patches[0]}"
  start_commit=$(git commit-tree "$(GIT_INDEX_FILE="$idx" git write-tree)" -p "$base" -m "review eval: $target/start")
  patches=("${patches[@]:1}")
fi
git update-ref "$(review_ref "$target" start)" "$start_commit"
echo "$target/start = $start_commit"
[[ $kind == feature ]] && git update-ref "$(review_ref "$target" gates)" "$start_commit"

for p in "${patches[@]}"; do
  phase=$(basename "$p" .patch); phase=${phase#[0-9][0-9]-}
  # 모든 패치는 start 상태 기준. 앞 패치의 결과를 지우고 적용한다
  GIT_INDEX_FILE="$idx" git read-tree "$start_commit"
  GIT_INDEX_FILE="$idx" git apply --cached "$p"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  case $phase in
    gates)
      [[ $kind == feature ]] || { echo "gates 패치는 kind=feature에서만 씁니다: $p" >&2; exit 2; }
      commit=$(git commit-tree "$tree" -p "$start_commit" -m "review eval: $target/gates")
      git update-ref "$(review_ref "$target" gates)" "$commit"
      echo "$target/gates = $commit"
      ;;
    red|done)
      label=$(next_label "$target" "$phase")
      commit=$(store_snapshot "$target" "$label" "$tree" "$start_commit" nolast)
      if [[ $phase == red ]]; then
        write_result "$target" "$label" red 1 "$commit" confirmed "eval synthetic"
      else
        write_result "$target" "$label" done 0 "$commit" "" "eval synthetic"
      fi
      echo "$target/$label = $commit"
      ;;
    base) echo "base 패치는 맨 앞에만 둡니다: $p" >&2; exit 2 ;;
    *) echo "알 수 없는 phase: $phase ($p)" >&2; exit 2 ;;
  esac
done

echo "---"
echo "reviewer=$([[ $kind == feature ]] && echo feature-reviewer || echo task-reviewer)"
echo "target=$target"
[[ -n $type ]] && echo "type=$type"
[[ -n $spec ]] && echo "spec=$(rel "$case_dir/$spec")"
[[ -n $module_spec ]] && echo "module_spec=$(rel "$case_dir/$module_spec")"
exit 0
