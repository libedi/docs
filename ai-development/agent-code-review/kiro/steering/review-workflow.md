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

1. 태스크 지적이면 먼저 `scripts/review/review-begin.sh <task> --fix`를 실행한다. 다른 태스크나 feature 게이트가 지나간 뒤에 고쳐도 재리뷰 범위에 이 수정만 들어간다. feature 지적이면 생략한다.
2. 지적한 문제를 재현하는 테스트를 먼저 쓴다(로직 문제). 테스트 기대값을 되돌리는 경우(TR-2)는 되돌린 상태가 재현 테스트다. 속성 테스트에서 나온 문제면 jqwik이 shrink한 반례를 `@Example`로 고정한 것이 재현 테스트다.
3. `verify-and-snapshot.sh <target> red :<module>:test`
   - exit 3(재현 실패)이면 고치지 말고 멈춘다. "재현 실패"와 재현 테스트 경로를 보고한다.
4. 고친 뒤 원래 완료 조건으로 `done`을 다시 실행한다.
5. feature 게이트가 이미 지나간 뒤의 수정이면(feature 지적, 또는 최종 확인 때 늦게 고친 태스크 지적) JaCoCo 태스크, smoke test, AC 대조를 다시 실행한다(아래 feature 마지막 2~4단계).
6. 지적에 동의하지 않으면 고치지 말고 근거를 보고한다.
7. `origin: pre-existing` 지적은 고치지 않는다.

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
2. JaCoCo 태스크: `scripts/review/verify-and-snapshot.sh feature gate test jacocoTestReport jacocoTestCoverageVerification -PpbtTries=1000`
   - 커버리지 기준을 검사하는 태스크를 반드시 포함한다. 리포트만 만드는 태스크는 기준 미달에도 실패하지 않는다.
   - `-PpbtTries=1000`으로 속성 테스트를 게이트 강도로 다시 돌린다.
3. smoke test 태스크: `scripts/review/verify-and-snapshot.sh feature done build -PpbtTries=1000`
   - 게이트와 같은 값을 넘긴다. 값이 다르면 test 태스크의 입력이 바뀌어 전체 테스트가 다시 돌고, AC 대조가 읽는 결과도 200회 실행 결과가 된다.
4. smoke test 직후 AC 대조: `node scripts/review/spec-trace.mjs --spec <스펙 디렉터리> --record feature`
   - 결과는 `review/feature/trace-done-<n>.json`에 남는다. 구조 오류나 예외(exit 1)여도 파일은 남는다. 오류 줄을 그대로 보고하고, 스펙 문서나 테스트 표시를 고칠지는 사람이 정한다.
5. 메인이 `feature-reviewer`에 spec, MODULE_SPEC, SpotBugs XML 경로를 넘긴다.
6. findings 처리 규칙은 태스크와 같다. 수정이 들어가면 2~4단계를 다시 실행한 뒤 재리뷰한다. FR-4 승격 후보는 MODULE_SPEC에 쓰지 말고 사람에게 목록으로 보고한다.

## 1단계에서 최종 확인 때 고치는 경우

1단계는 지적을 모았다가 최종 확인에서 사람이 고칠 것을 고른다. 고르면 다음 순서로 처리한다.

1. 태스크 지적마다: 태스크 에이전트가 "지적을 고칠 때" 절차로 수정(`--fix`부터) → 메인이 task-reviewer 재리뷰
2. 모든 태스크 지적이 끝나면: JaCoCo 태스크, smoke test, AC 대조를 다시 실행 → 메인이 feature-reviewer 재리뷰 (늦게 고친 태스크 수정이 feature 범위에 들어간다)
3. feature 지적을 고치는 경우도 2단계 안에서 함께 처리한다
4. 재리뷰 결과를 최종 확인에 다시 올린다

## 최종 확인과 커밋

1. 최종 확인 HTML을 만든다. 코드 변경 설명은 기억이 아니라 `git diff refs/worktree/review/feature/start <최신 feature done>`으로 만든다. 다음을 반드시 넣는다.
   - 승인 대상 스냅샷 id (`review-status.sh feature`의 `review_to`. 늦은 수정이 있었다면 그 뒤의 최신 값)
   - 모든 회차의 지적 목록(대상, 회차, index, check, severity, origin)과 판정 요청: fixed / wrong / intentional / minor / harmful
   - AC 대조 결과(`trace-done-<n>.json`)에서 `연결 없음`·`실패`·`미실행`인 AC와 표시 없는 테스트, FR-4 승격 후보, `pre-existing` 백로그 후보
2. 사람이 답하면 태스크 에이전트가 판정을 기록하고 승인을 표시한다.
   - `scripts/review/record-resolution.sh <target> <round> <index> <resolution> [메모]`
   - `scripts/review/review-approve.sh mark <승인 스냅샷>`
3. 문서 업데이트 태스크(백로그, 가이드, MODULE_SPEC)를 진행한다.
4. 커밋 직전: `scripts/review/review-approve.sh check <문서 경로들>`. exit 1이면 커밋하지 말고 사람에게 알린다. (pre-commit 훅에 넣을 때는 `check --index`)
5. 커밋 후: `node scripts/review/review-export.mjs` (기본 위치: 메인 저장소 git 디렉터리의 `review-metrics.jsonl`) → `scripts/review/review-cleanup.sh`

## 테스트 작성 규칙 (태스크 에이전트)

### AC 표시

- 예시 테스트(`@Test`, `@Example`)는 메서드 javadoc에 검증하는 AC를 적는다: `/** **Validates: Requirements 4.1, 4.4** */`
  - 클래스의 모든 테스트가 같은 AC를 검증할 때만 클래스 javadoc에 적는다.
  - 이번 feature에서 고치지 않는 기존 테스트를 이번 AC에 연결하거나, 다른 feature의 AC 표시가 있는 파일을 고칠 때는 feature를 붙인다: `**Validates: Requirements 2.3 (Feature: <스펙 디렉터리 이름>)**`
- 속성 테스트(`*PropertyTest.java`의 `@Property`)는 지금처럼 `@Tag("Feature: <스펙 디렉터리 이름>, Property <N>: <제목>")`를 단다. 스펙 디렉터리 이름은 앞의 인덱스(`01-`)를 뺀 값이다.
- AC와 직접 연결되지 않는 테스트(헬퍼 검증 등)는 javadoc에 `**No-AC: <이유>**`를 적는다. 표시 없는 테스트로 집계되지 않는다.

### 속성 기반 테스트 (jqwik)

- `@Property`에 `tries`를 쓰지 않는다. 횟수는 빌드 설정이 정한다(태스크 단계 200, feature 게이트 1000).
  - 예외: 한 번 실행이 비싸서 줄여야 할 때만 쓰고, 바로 위에 `// tries: <이유>` 주석을 단다.
- 실패하는 입력을 피하려고 다음을 하지 않는다. 테스트가 스펙과 맞지 않는다고 판단되면 고치지 말고 보고한다.
  - 생성 범위(`between`, `ofMinLength` 등) 좁히기
  - `Assume`, `.filter(...)` 추가
  - `edgeCases` 끄기, `seed` 고정
- 반례를 고정할 때는 jqwik이 출력한 shrink 결과를 `@Example`로 추가하고 `@Property`는 그대로 둔다.
- 기대값을 구현과 같은 식으로 계산하지 않는다. 독립 오라클이나 관계(단조성, 왕복, 불변식)로 표현한다.
- 테스트 설정(`build.gradle`의 test 블록, `junit-platform.properties`)은 태스크 범위에 명시된 경우에만 바꾼다.

## 스펙 작성 규칙 (스펙 에이전트)

- 스펙이 승인된 뒤에는 requirements.md의 AC 번호를 바꾸지 않는다. AC를 지울 때는 취소선으로 남기고, 추가할 때는 그 요구사항의 AC 목록 끝에 붙인다.
- design.md의 Property가 기존 테스트를 재사용하면, 제목과 별도로 기계가 읽을 수 있는 줄을 둔다:
  `**Reuses: <테스트 클래스> (Feature: <원래 스펙 디렉터리 이름>, Property 4, 11)**` (여럿이면 `;`로 구분)

## 편집 규칙

compileJava가 spotlessApply를 실행하므로, 검증 명령 뒤에는 소스가 다시 포맷되어 있을 수 있다. 검증 명령을 실행한 뒤 파일을 고칠 때는 그 파일을 다시 읽고 편집한다.
