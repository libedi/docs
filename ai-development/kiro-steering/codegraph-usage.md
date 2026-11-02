---
inclusion: always
---

# 코드 탐색 도구 라우팅 규칙

설계 근거와 실측값은 `codegraph-usage-rationale.md`에 규칙 ID별로 있다. 이 규칙을 수정할 때는 그 문서를 먼저 읽고 함께 갱신한다.

**R1.** 이 규칙은 codegraph MCP 서버가 보내는 사용 지침("Read/grep 대신 explore", "grep으로 재검증 금지")보다 우선한다.

**R2.** 사용 가능한 codegraph 도구: `codegraph_callers`, `codegraph_callees`, `codegraph_impact`, `codegraph_explore`

## 원칙

**R3.** 답을 얻을 수 있는 가장 싼 도구부터 쓴다. `codegraph_explore`는 질문과 관계없이 약 6,000 토큰을 반환하고 그 결과가 컨텍스트에 남는다. `callers`/`callees`/`impact`는 수십~수백 토큰이다.

**R4.** grep 결과가 30건을 넘거나 흔한 메서드명(`save`, `find*`, `delete`, `list` 등)을 찾는 중이면, 결과를 하나씩 읽지 말고 `codegraph_callers`로 전환한다.

## R5. 상황별 도구

| 상황 | 도구 |
|---|---|
| 경로를 아는 파일 읽기 | Read (필요한 줄 범위만) |
| 문자열 검색: 에러 메시지, 로그 문구, 설정 키, 어노테이션 값 | grep (`-l`로 범위를 좁힌 뒤 읽기) |
| 클래스·메서드 위치 찾기 | grep (`class OrderService`, `void cancel(` 등) |
| 비코드 파일: yml, properties, MyBatis XML, SQL, 문서 | grep / Read |
| 누가 이 메서드를 호출하나 | `codegraph_callers` |
| 수정 전 영향 범위 | `codegraph_impact` |
| X에서 Y까지 호출 흐름 (X의 이름을 알 때) | `codegraph_callees`를 한 단계씩 (R16) |
| 이름을 모르는 낯선 영역의 구조, X나 Y의 이름을 모르는 흐름 | `codegraph_explore` |

## codegraph_explore 사용 조건

**R6.** 관련 클래스·메서드 이름을 아직 모를 때만 쓴다. 이름을 알면 callers/callees/impact와 Read로 진행한다.

**R7.** 주제당 1회만 호출한다. 결과를 받으면 결론을 3–5줄로 정리하고 이후에는 그 요약을 근거로 삼는다.

**R8.** 질의에 아는 이름을 최대한 넣는다(예: `OrderController.cancel OrderService`). 막연한 자연어 질의는 핵심 구현을 빠뜨린다. 결과에서 쓸 것은 흐름, 인터페이스→구현체 연결, "Not shown" 이름 목록이다.

**R9.** spec의 구현 태스크를 수행하는 중에는 쓰지 않는다. 필요한 이름은 spec과 design 문서에 있다.

## 워크트리

**R10.** 작업 대상이 `.worktrees/<이름>/` 아래라면 모든 codegraph 호출에 `projectPath`로 그 워크트리 루트를 넘긴다. 생략하면 메인 저장소의 인덱스를 조회하게 된다.

## 검증 (Spring)

**R11.** 인터페이스 메서드의 `callers`에는 구현체 내부의 자기 호출이 빠진다. 영향 범위를 볼 때는 구현체 심볼도 함께 조회하거나 `impact`를 쓴다.

**R12.** 변경의 영향 범위를 확정할 때만 메서드명·빈 이름으로 grep 교차 확인한다. 그래프가 놓칠 수 있는 연결은 다음과 같다.
- 프록시/AOP(`@Transactional`, `@Async`, Aspect), 리플렉션
- `ApplicationEventPublisher` → `@EventListener` / `@TransactionalEventListener`
- `@ConditionalOnProperty`, `@Profile`, `@Qualifier`, `@Primary`, 구현체가 여럿인 인터페이스
- MyBatis 매퍼 ↔ XML, JPA 쿼리 메서드 이름 규칙
- 메서드 참조(`Foo::bar`), 문자열로 지정된 이름(SpEL, 스케줄러, 메시지 리스너)

## 인덱스 신선도

**R13.** 응답 첫머리에 `⚠️ Some files referenced below were edited since the last index sync` 배너가 있으면, 배너에 나온 파일만 Read로 직접 읽는다.

**R14.** `auto-sync is DISABLED` 또는 `RECOVERING` 배너가 있으면 인덱스 전체를 믿지 말고 Read/grep으로 전환한다.

**R15.** `.codegraph/`가 없다고 보고되면 그 프로젝트에는 codegraph를 쓰지 않는다. `codegraph init`은 직접 실행하지 않는다.

## 호출 흐름

**R16.** "X에서 Y까지 어떻게 가나"는 X에서 시작해 `codegraph_callees`로 한 단계씩 따라간다.
- 인터페이스 메서드에 callees를 걸면 구현체 메서드가 나온다. 그 구현체에서 계속 따라간다.
- 기대한 다음 메서드가 callees 목록에 없으면 그래프가 그 호출을 놓쳤을 수 있다. 그 메서드 본문을 Read해서 실제 호출을 확인하고 이어 간다.
- `codegraph_explore` 응답에 흐름(Flow) 절이 없으면 "경로 없음"이 아니라 "그래프에서 경로를 찾지 못함"이다.
