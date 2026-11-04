#!/usr/bin/env bash
# 리뷰어 평가(회귀 테스트) 사례 하나를 리뷰 가능한 스냅샷으로 만든다.
# 작업 트리와 실제 인덱스는 건드리지 않는다. 패치는 임시 인덱스에만 적용한다.
#
#   eval-setup.sh <case-dir>
#
# 사례 디렉터리 구성
#   case.env           base=<커밋>  kind=task|feature  type=tdd|non-tdd(task만)  spec=<스펙 디렉터리>
#   NN-<phase>.patch   base 위에 순서대로 적용할 패치. phase는 base, red, done, gates 중 하나
#                        base  → start 기준점 (스펙 문서 추가 등, 리뷰 대상이 아닌 준비)
#                        red   → red-n 스냅샷 (테스트가 실패하는 상태로 기록)
#                        done  → done-n 스냅샷 (검증 통과로 기록)
#                        gates → feature 전용. gates 기준점 (마지막 태스크가 끝난 상태)
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

# 이전 기록 정리 (정확히 이 대상만)
git for-each-ref --format='%(refname)' "$review_ns/$target/" | while read -r ref; do git update-ref -d "$ref"; done
rm -rf "$(review_dir "$target")"

idx=$(git rev-parse --git-path "review-eval-index")
trap 'rm -f "$idx"' EXIT
GIT_INDEX_FILE="$idx" git read-tree "$base"
git update-ref "$(review_ref "$target" start)" "$base"
[[ $kind == feature ]] && git update-ref "$(review_ref "$target" gates)" "$base"

shopt -s nullglob
patches=("$case_dir"/[0-9][0-9]-*.patch)
[[ ${#patches[@]} -gt 0 ]] || { echo "패치가 없습니다: $case_dir" >&2; exit 2; }

for p in "${patches[@]}"; do
  phase=$(basename "$p" .patch); phase=${phase#[0-9][0-9]-}
  GIT_INDEX_FILE="$idx" git apply --cached "$p"
  tree=$(GIT_INDEX_FILE="$idx" git write-tree)
  case $phase in
    base|gates)
      commit=$(git commit-tree "$tree" -p "$base" -m "review eval: $target/$phase")
      ref_name=$([[ $phase == base ]] && echo start || echo gates)
      git update-ref "$(review_ref "$target" "$ref_name")" "$commit"
      echo "$target/$ref_name = $commit"
      ;;
    red|done)
      label=$(next_label "$target" "$phase")
      commit=$(store_snapshot "$target" "$label" "$tree" "$base" nolast)
      if [[ $phase == red ]]; then
        write_result "$target" "$label" red 1 "$commit" confirmed "eval synthetic"
      else
        write_result "$target" "$label" done 0 "$commit" "" "eval synthetic"
      fi
      echo "$target/$label = $commit"
      ;;
    *) echo "알 수 없는 phase: $phase ($p)" >&2; exit 2 ;;
  esac
done

echo "---"
echo "reviewer=$([[ $kind == feature ]] && echo feature-reviewer || echo task-reviewer)"
echo "target=$target"
[[ -n $type ]] && echo "type=$type"
[[ -n $spec ]] && echo "spec=$(realpath --relative-to="$root" "$case_dir/$spec")"
