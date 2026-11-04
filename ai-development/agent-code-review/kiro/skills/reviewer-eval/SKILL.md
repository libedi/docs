---
name: reviewer-eval
description: 리뷰 에이전트(task-reviewer, feature-reviewer)를 정답이 있는 사례 묶음으로 회귀 테스트한다. 리뷰어의 모델, 에이전트 정의, 리뷰 steering을 바꾸거나 Kiro 버전을 올릴 때, 또는 두 모델을 비교할 때 사용한다.
---

# 리뷰어 회귀 테스트

리뷰어가 틀린 지적을 얼마나 하는지는 실제 feature의 판정(resolution)으로 알 수 있지만, 진짜 버그를 얼마나 놓치는지는 그것만으로 알 수 없다. 이 스킬은 버그를 일부러 심은 사례와 버그가 없는 사례로 리뷰어를 채점해서, 바꾼 뒤가 바꾸기 전보다 나은지 숫자로 판정한다.

채점은 스크립트가 한다. 이 스킬에서 에이전트가 하는 일은 순서대로 실행하고 리뷰어를 부르는 것뿐이다. 사례 내용을 보고 리뷰어에게 힌트를 주지 않는다.

## 언제 돌리나

- 리뷰어 모델을 바꿀 때, 또는 다른 모델과 비교할 때
- `task-reviewer.md`, `feature-reviewer.md`, `review-workflow.md`를 고칠 때
- 사내 Kiro 버전을 올릴 때
- 실제 feature에서 리뷰어가 놓친 버그를 사람이 발견해서 사례를 추가했을 때

## 준비

- 사례 디렉터리: `scripts/review/eval/cases/` (사례 하나가 디렉터리 하나)
- 기준 결과: `scripts/review/eval/baseline.json` (현재 채택된 리뷰어 구성의 점수)
- 진행 중인 feature와 섞이지 않게 별도 워크트리에서 실행한다. 평가용 스냅샷은 `eval-` 접두사를 쓰고 `_last`를 건드리지 않는다.

## 절차

1. 사례마다 스냅샷을 만든다.
   ```bash
   scripts/review/eval-setup.sh scripts/review/eval/cases/<사례>
   ```
   출력의 `reviewer`, `target`, `type`, `spec`을 그대로 쓴다.
2. 출력에 적힌 리뷰어를 부른다. 다른 리뷰어 구성을 시험할 때는 그 구성의 에이전트를 부르고 `tag`를 함께 넘긴다(예: `glm`, `prompt-v3`).
   - task-reviewer: `task=<target>`, `type=<type>`, `spec=<spec>`, (선택) `tag`
   - feature-reviewer: `spec=<spec>`, `module_spec=<사례 안 경로>`, (선택) `tag`
   - 사례 이름, expected.json, 이 스킬의 내용을 리뷰어에게 넘기지 않는다.
3. 모든 사례가 끝나면 채점한다.
   ```bash
   node scripts/review/eval-score.mjs --cases scripts/review/eval/cases [--tag <tag>] \
     --baseline scripts/review/eval/baseline.json --out /tmp/reviewer-eval.json
   ```
4. 결과를 보고한다: 사례별 발견·오탐, 합계 recall, 버그 없는 사례 중 오탐 발생 수, 기준 대비 변화, 판정.
   - "판정: 개선"일 때만 바꾼 구성을 채택하자고 제안한다. 채택이 결정되면 `--out` 결과로 baseline.json을 바꾼다.
   - 오탐으로 집계된 지적이 실제 문제로 보이면 그 사례의 expected.json을 고칠지 사람에게 묻는다. 직접 고치지 않는다.
5. 정리: `scripts/review/review-cleanup.sh eval-`

## 사례 만드는 법

사례는 사람이 만들고 리뷰한다. 완료된 feature에서 가져오는 것이 가장 쉽다.

```
cases/tr2-expect-changed/
  case.env          base=<feature 시작 전 커밋>  kind=task  type=tdd  spec=spec
  spec/             requirements.md, design.md, tasks.md (그 feature의 스펙)
  01-red.patch      base → 테스트만 작성된 상태
  02-done.patch     base → 구현 완료 상태 (여기에 버그를 심는다)
  expected.json     {"findings":[{"check":"TR-2","file":"settlement/src/test/java/.../DiscountPolicyTest.java","line":42}]}
```

- 패치는 모두 base 기준이다(앞 패치에 이어 붙이지 않는다). `git diff <base> <상태>`로 만든다.
- feature 사례는 `kind=feature`로 두고 `NN-gates.patch`(마지막 개발 태스크까지)와 `NN-done.patch`(게이트 이후)를 쓴다.
- 버그 없는 사례도 전체의 1/3쯤 둔다. 같은 feature에서 버그를 심지 않은 버전을 쓰면 된다. 이 사례의 오탐이 "따르면 해로운 지적"의 후보다.
- 심을 버그의 예
  - TR-1: 단언을 `isNotNull()`로 약화, 기대값을 구현과 같은 공식으로 계산
  - TR-2: red 이후 기대값 변경, `@Disabled` 추가, "이상"을 "초과"로
  - TR-3: AC에 없는 등급 할인 추가
  - TR-4: VO에 금액 계산 로직 추가
  - FR-2: 청크 트랜잭션 안에서 외부 알림 호출, 단순 INSERT Writer(재실행 시 중복), 예외를 삼키는 catch
  - FR-3: 게이트 단계에서 단언 없는 테스트 추가
  - FR-4: MODULE_SPEC은 원 단위 절사인데 `RoundingMode.HALF_UP`

## 지켜야 할 것

- 실패한 사례 하나에 맞춰 리뷰어 지시문을 고치지 않는다. 고친 뒤 전체 점수로 판정한다.
- 실제로 놓친 버그는 사례로 계속 추가한다. 사례가 고정되면 시험지만 잘 푸는 리뷰어가 된다.
- 사례 디렉터리와 baseline.json은 저장소에 커밋해 팀이 같은 기준을 쓴다.
