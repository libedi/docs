---
inclusion: always
---

# 태스크 검증과 리뷰 절차

스크립트는 `scripts/review/`에 있다. 검증 명령(gradle)을 직접 실행하지 말고 항상 `verify-and-snapshot.sh`를 거친다. 스냅샷은 덮어쓰지 않고 번호가 붙는다(red-1, done-1, red-2, done-2 …). 리뷰 범위와 회차는 `review-status.sh <target>` 출력을 기준으로 한다.

이 문서는 Spec 세션의 모든 에이전트가 읽는다. 자기 역할의 절만 따른다.

| 역할 | 하는 일 | 하지 않는 일 |
| --- | --- | --- |
| 메인(오케스트레이터) | 태스크 위임, 리뷰어 호출, findings 파일을 읽고 갈래 나누기, 사람에게 묻기 | 코드·문서를 직접 고치지 않는다 |
| 태스크 에이전트 | 태스크 구현, 스냅샷, 지적 수정 | 리뷰어를 직접 부르지 않는다 |
| 스펙 에이전트 | 사람이 정한 범위에서 tasks.md·design.md 수정 | 리뷰 지적만 보고 스펙을 고치지 않는다 |
| task-reviewer, feature-reviewer | 스냅샷과 스펙을 읽고 findings 기록 | 고치지 않는다 |

## 태스크 에이전트: 태스크마다

1. 시작: `scripts/review/review-begin.sh <task>`
2. TDD 대상 태스크 (red → green → refactor)
   - 테스트를 쓰고 실패를 확인할 때: `scripts/review/verify-and-snapshot.sh <task> red :<module>:test [--tests '<새 테스트>']`
     - exit 0(Red 확인)이어야 구현으로 넘어간다. exit 3이면 테스트가 새 동작을 검증하지 않는 것이니 테스트를 다시 쓴다.
     - 테스트를 나눠 쓰며 red를 여러 번 확인해도 된다. 모두 남는다.
   - green·refactor 후 완료 조건: `scripts/review/verify-and-snapshot.sh <task> done :<module>:test`
3. TDD 비대상 태스크(인터페이스, VO): `scripts/review/verify-and-snapshot.sh <task> done :<module>:compileJava`
4. 완료 보고에는 마지막 `verify-and-snapshot.sh`의 출력 한 줄을 그대로 붙인다.

## 태스크 에이전트: 지적을 고칠 때

메인이 넘긴 findings 파일을 직접 읽는다. 메인의 요약이 아니라 파일의 `evidence`, `why`, `next`를 따른다.

1. 지적한 문제를 재현하는 테스트를 먼저 쓴다(로직 문제). 테스트 기대값을 되돌리는 경우(TR-2)는 되돌린 상태가 재현 테스트다.
2. `verify-and-snapshot.sh <target> red :<module>:test`
   - exit 3(재현 실패)이면 고치지 말고 멈춘다. "재현 실패"와 재현 테스트 경로를 보고한다.
3. 고친 뒤 원래 완료 조건으로 `done`을 다시 실행한다. feature 단계의 수정이면 JaCoCo 태스크와 smoke test를 다시 실행한다(아래 feature 마지막 2~3단계).
4. 지적에 동의하지 않으면 고치지 말고 근거를 보고한다.
5. `origin: pre-existing` 지적은 고치지 않는다.

## 메인: 태스크마다

1. 태스크를 태스크 에이전트에 위임한다.
2. 완료 보고를 받으면 `task-reviewer`에 task, type(`tdd`/`non-tdd`), spec 경로를 넘겨 리뷰를 요청한다.
3. 결과는 리뷰어의 설명이 아니라 리뷰어가 알려준 `findings-<n>.json` 파일을 read 도구로 읽어 처리한다.
4. findings 처리 (현재 도입 단계: `steering/review-stage.md`의 단계를 따른다. 기본은 1단계)
   - **1단계(리포트만)**: 고치지 않는다. 지적 목록만 모아 두고 다음 태스크로 간다. `TR-0`(검증 미통과)은 예외로, 태스크를 다시 위임한다.
   - **2단계 이후**: 차단 대상으로 지정된 check의 지적만 아래 갈래로 보낸다. 나머지는 1단계처럼 모은다.
     - `blocker`/`major` + `origin: introduced` + `fix_scope: local` → 태스크 에이전트에 findings 파일 경로를 넘겨 수정을 위임한다. 수정 후 리뷰어를 다시 부른다(리뷰어가 수정분만 본다).
     - `fix_scope: task` → 사람에게 묻는다. 사람이 정하면 스펙 에이전트에 tasks.md 수정을 위임하고, 추가된 태스크를 태스크 에이전트에 위임한다.
     - `question` → 사람에게 묻는다.
     - `minor`, `origin: pre-existing` → 고치지 않고 목록만 모은다.
   - 태스크 에이전트가 "재현 실패"나 반박을 보고하면 고치지 않고 사람에게 넘긴다.
   - 재리뷰는 2회까지다(3회차까지). 그 뒤에도 남은 blocker/major, 그리고 `carried`에서 `unresolved`로 남은 지적은 사람에게 넘기고 멈춘다.

## feature 마지막

1. 마지막 개발 태스크가 끝나면 태스크 에이전트가 `scripts/review/review-begin.sh feature`를 실행한다.
2. JaCoCo 태스크: `scripts/review/verify-and-snapshot.sh feature gate <jacoco 태스크>`
3. smoke test 태스크: `scripts/review/verify-and-snapshot.sh feature done build`
4. 메인이 `feature-reviewer`에 spec, MODULE_SPEC, SpotBugs XML 경로를 넘긴다.
5. findings 처리 규칙은 태스크와 같다. 수정이 들어가면 2~3단계를 다시 실행한 뒤 재리뷰한다. FR-4 승격 후보는 MODULE_SPEC에 쓰지 말고 사람에게 목록으로 보고한다.

## 최종 확인과 커밋

1. 최종 확인 HTML을 만든다. 코드 변경 설명은 기억이 아니라 `git diff refs/worktree/review/feature/start <최신 feature done>`으로 만든다. 다음을 반드시 넣는다.
   - 승인 대상 스냅샷 id (`review-status.sh feature`의 `review_to`)
   - 모든 회차의 지적 목록(대상, 회차, index, check, severity, origin)과 판정 요청: fixed / wrong / intentional / minor / harmful
   - FR-1 추적표의 빈칸, FR-4 승격 후보, `pre-existing` 백로그 후보
2. 사람이 답하면 태스크 에이전트가 판정을 기록하고 승인을 표시한다.
   - `scripts/review/record-resolution.sh <target> <round> <index> <resolution> [메모]`
   - `scripts/review/review-approve.sh mark <승인 스냅샷>`
3. 문서 업데이트 태스크(백로그, 가이드, MODULE_SPEC)를 진행한다.
4. 커밋 직전: `scripts/review/review-approve.sh check <문서 경로들>`. exit 1이면 커밋하지 말고 사람에게 알린다.
5. 커밋 후: `node scripts/review/review-export.mjs <지표 파일>` → `scripts/review/review-cleanup.sh`

## 편집 규칙

compileJava가 spotlessApply를 실행하므로, 검증 명령 뒤에는 소스가 다시 포맷되어 있을 수 있다. 검증 명령을 실행한 뒤 파일을 고칠 때는 그 파일을 다시 읽고 편집한다.
