#!/usr/bin/env bash
# 리뷰 스크립트들이 함께 쓰는 함수. 직접 실행하지 않고 source 한다.
# bash 4 이상이 필요하다 (연관 배열). GNU 전용 옵션은 쓰지 않는다.
#
# 스냅샷 규칙: 같은 이름을 덮어쓰지 않고 번호를 붙인다.
#   refs/worktree/review/<target>/start      태스크 시작 기준 (feature는 HEAD)
#   refs/worktree/review/<target>/gates      feature 전용. 마지막 태스크의 마지막 스냅샷
#   refs/worktree/review/<target>/red-<n>    red 확인 시점 (태스크 안의 red, 수정 루프의 red)
#   refs/worktree/review/<target>/done-<n>   검증 통과 시점. n이 곧 리뷰 회차
#   refs/worktree/review/<target>/fail-<n>   done 검증이 실패한 시점 (증거로만 남기고 회차에 넣지 않는다)
#   refs/worktree/review/<target>/gate-<n>   feature 게이트(JaCoCo 기준 검사) 시점. 가장 최근 것이 통과해야 리뷰한다
#   refs/worktree/review/<target>/fixbase-<n> 태스크 지적을 고치기 시작한 시점의 _last. n회차 리뷰 범위의 시작
#                                            (다른 태스크가 지나간 뒤 늦게 고쳐도 그 변경이 범위에 섞이지 않게 한다)
#   refs/worktree/review/_last               가장 최근 done 스냅샷 (다음 태스크의 start). red는 갱신하지 않는다
#
# 기록은 워크트리별 git 디렉터리 아래 review/<target>/ 에 남는다.
#   <label>.result        phase, 종료 코드, 스냅샷 id, 순번(seq)
#   findings-<n>[.<tag>].json   n회차 리뷰 결과 (tag는 비교용 보조 리뷰어)
#   resolutions.jsonl     사람이 판정한 결과

if (( BASH_VERSINFO[0] < 4 )); then
  echo "bash 4 이상이 필요합니다 (현재 $BASH_VERSION)" >&2
  exit 2
fi

review_ns=refs/worktree/review

# ISO 8601 시각 (GNU·BSD date 모두 동작)
now_iso() {
  date +%Y-%m-%dT%H:%M:%S%z
}

review_dir() {
  git rev-parse --git-path "review/$1"
}

review_ref() {
  echo "$review_ns/$1/$2"
}

# 같은 phase의 다음 번호 라벨 (red-1, red-2, ...)
next_label() {
  local target=$1 phase=$2 n=1
  while git show-ref --verify -q "$(review_ref "$target" "$phase-$n")"; do
    n=$((n + 1))
  done
  echo "$phase-$n"
}

# 지금까지 기록된 done 스냅샷 수 = 현재 리뷰 회차
current_round() {
  local target=$1 n=0
  while git show-ref --verify -q "$(review_ref "$target" "done-$((n + 1))")"; do
    n=$((n + 1))
  done
  echo "$n"
}

# 현재 작업 트리 전체(신규 파일 포함, .gitignore 준수)를 tree 객체로 만든다.
# 실제 인덱스의 사본을 쓰므로 staging 상태를 건드리지 않는다.
worktree_tree() {
  local idx
  idx=$(git rev-parse --git-path review-index)
  cp "$(git rev-parse --git-path index)" "$idx"
  GIT_INDEX_FILE="$idx" git add -A
  GIT_INDEX_FILE="$idx" git write-tree
  rm -f "$idx"
}

# tree를 커밋 객체로 만들어 ref에 기록한다. pre-commit 훅은 돌지 않는다(commit-tree).
# 다섯 번째 인자로 nolast를 주면 _last를 건드리지 않는다 (red 스냅샷, 리뷰어 평가용 스냅샷).
store_snapshot() {
  local target=$1 label=$2 tree=$3 parent=$4 mode=${5:-} commit
  commit=$(git commit-tree "$tree" -p "$parent" -m "review snapshot: $target/$label")
  git update-ref "$(review_ref "$target" "$label")" "$commit"
  [[ $mode == nolast ]] || git update-ref "$review_ns/_last" "$commit"
  echo "$commit"
}

# <label>.result 기록. seq는 대상 안에서 스냅샷이 찍힌 순서
write_result() {
  local target=$1 label=$2 phase=$3 rc=$4 commit=$5 verdict=$6 detail=$7 dir seq
  dir=$(review_dir "$target")
  mkdir -p "$dir"
  seq=$(($(find "$dir" -maxdepth 1 -name '*.result' | wc -l) + 1))
  {
    echo "label=$label"
    echo "phase=$phase"
    echo "seq=$seq"
    echo "exit_code=$rc"
    [[ -n $verdict ]] && echo "red=$verdict"
    echo "snapshot=$commit"
    echo "detail=$detail"
    echo "at=$(now_iso)"
  } > "$dir/$label.result"
}

# result 파일에서 값 하나 읽기
result_value() {
  local file=$1 key=$2
  sed -n "s/^$key=//p" "$file" | head -n 1
}

# 리뷰 범위. 1회차는 start→done-1, 2회차부터는 수정분만
#   fixbase-n이 있으면 fixbase-n→done-n (늦게 고친 경우에도 이 수정만)
#   없으면 done-(n-1)→done-n (바로 고친 경우, feature)
review_range() {
  local target=$1 round fixbase
  round=$(current_round "$target")
  if [[ $round -eq 0 ]]; then
    return 1
  elif [[ $round -eq 1 ]]; then
    echo "$(review_ref "$target" start) $(review_ref "$target" done-1)"
  else
    fixbase=$(review_ref "$target" "fixbase-$round")
    if git show-ref --verify -q "$fixbase"; then
      echo "$fixbase $(review_ref "$target" "done-$round")"
    else
      echo "$(review_ref "$target" "done-$((round - 1))") $(review_ref "$target" "done-$round")"
    fi
  fi
}
