---
inclusion: always
---

# 태스크 검증과 리뷰 절차

스크립트는 `scripts/review/`에 있다. 검증 명령(gradle)을 직접 실행하지 말고 항상 `verify-and-snapshot.sh`를 거친다.

## 태스크마다

1. 시작: `scripts/review/review-begin.sh <task>`
2. TDD 대상 태스크
   - 테스트 작성 후: `scripts/review/verify-and-snapshot.sh <task> red :<module>:test`
     - exit 0(Red 확인)이어야 구현으로 넘어간다. exit 3이면 테스트가 새 동작을 검증하지 않는 것이니 테스트를 다시 쓴다.
   - 구현 후: `scripts/review/verify-and-snapshot.sh <task> done :<module>:test`
3. TDD 비대상 태스크(인터페이스, VO): `scripts/review/verify-and-snapshot.sh <task> done :<module>:compileJava`
4. `task-reviewer` 서브에이전트에 task, type(`tdd`/`non-tdd`), spec 경로를 넘겨 리뷰를 요청한다.
5. 결과는 서브에이전트의 응답이 아니라 `$(git rev-parse --git-path review/<task>)/findings-<n>.json`의 가장 최근 파일을 읽어 처리한다.

## findings 처리

- `blocker`, `major`: 고친다. 로직을 고칠 때는 실패하는 테스트를 먼저 추가하거나 되돌린 뒤 구현을 고친다. 수정 후 2단계의 done을 다시 실행하고 다시 리뷰받는다.
- `question`: 고치지 말고 사람에게 묻는다.
- `minor`: 고치지 않고 태스크 완료 보고에 목록만 남긴다.
- 지적에 동의하지 않으면 고치지 말고, 근거를 적어 사람에게 넘긴다.
- 같은 태스크의 재리뷰는 2회까지다. 그 뒤에도 남은 blocker/major는 사람에게 넘기고 멈춘다.

## feature 마지막

1. smoke test 태스크: `scripts/review/verify-and-snapshot.sh feature done build`
2. `feature-reviewer` 서브에이전트에 spec, MODULE_SPEC, SpotBugs·JaCoCo XML 경로를 넘긴다.
3. findings 처리 규칙은 위와 같다. FR-4 승격 후보는 MODULE_SPEC에 직접 쓰지 말고 사람에게 목록으로 보고한다.

## 편집 규칙

compileJava가 spotlessApply를 실행하므로, 검증 명령 뒤에는 소스가 다시 포맷되어 있을 수 있다. 검증 명령을 실행한 뒤 파일을 고칠 때는 그 파일을 다시 읽고 편집한다.
