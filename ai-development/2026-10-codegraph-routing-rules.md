# codegraph MCP 코드 탐색 라우팅 규칙과 설계 근거

> 그래프는 관계를 물을 때만 쓰고, 나머지는 grep·Read가 맡는다

- 작성일: 2026-10-31
- 상태: 초안 (사내 Kiro 환경 검증 전)
- 대상: Kiro(IDE·CLI) + codegraph MCP 서버, Java/Spring 프로젝트, 메인 저장소 안 `.worktrees/` 구조
- 기준 버전: codegraph 1.6.2

## 목차

- [TL;DR](#tldr)
- [1. 배경](#1-배경)
- [2. 실측 결과](#2-실측-결과)
- [3. 설계 결정](#3-설계-결정)
- [4. 규칙과 근거 파일](#4-규칙과-근거-파일)
- [5. 미검증 사항](#5-미검증-사항)
- [6. 측정 환경](#6-측정-환경)
- [변경 이력](#변경-이력)

## TL;DR

- **`codegraph_explore`는 질문과 관계없이 매번 약 6,200 토큰을 반환합니다.** 같은 질문에 `callers`는 약 40 토큰, `impact`는 약 145 토큰이었습니다. graph 인덱싱 자체보다 "큰 응답 하나만 주는 도구 설계"가 컨텍스트 낭비의 원인입니다.
- **도구는 `explore`, `callers`, `callees`, `impact` 4개로 고정하고, 언제 무엇을 쓸지는 steering 규칙으로 제한합니다.** 도구 세트를 메인 저장소와 워크트리에 다르게 주는 방식은 `.worktrees/` 구조에서 MCP 프로세스가 1개만 떠서 불가능합니다.
- **`explore`는 이름을 모르는 낯선 영역을 처음 파악할 때만, 주제당 1회 씁니다.** 이름을 알면 좁은 도구가 컨텍스트를 3.5배 덜 씁니다. 다만 이름을 모를 때는 왕복을 줄이는 `explore`가 유리해서 끄지는 않습니다.
- **"X에서 Y까지" 흐름 질문은 `callees`로 한 단계씩 따라갑니다.** 같은 질문에 `callees`는 약 350 토큰으로 끊긴 지점까지 정확히 보여 줬고, `explore`는 약 6,200 토큰을 쓰고도 경로를 찾지 못했다는 사실이 드러나지 않았습니다.
- **워크트리 작업에서는 `projectPath`를 반드시 넘겨야 합니다.** 생략하면 메인 저장소의 인덱스를 조회해 현재 브랜치와 다른 코드를 근거로 판단하게 됩니다.
- **그래프는 평범한 메서드 호출도 놓칠 수 있습니다.** `jwtTokenUtil.generateToken()` 호출 2곳이 그래프에 없었습니다. 영향 범위를 확정할 때는 grep 교차 확인이 필요합니다. Spring 특유의 연결(AOP, 이벤트, MyBatis XML 등)은 아직 검증하지 않았습니다.

## 1. 배경

코드를 tree-sitter로 파싱해 로컬 SQLite 그래프로 만들고 MCP로 에이전트에 구조 정보를 주는 도구로 [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)와 [codegraph](https://github.com/colbymchenry/codegraph)를 비교했습니다. codebase-memory-mcp는 MCP 도구 17개, Cypher 쿼리, 인프라 설정까지 그래프화하는 넓은 플랫폼입니다. codegraph는 기본으로 `explore` 도구 하나만 노출하는 좁은 도구입니다.

폐쇄망 환경에서는 설치 경로가 결정적이었습니다. codegraph는 플랫폼별 번들을 npm `optionalDependencies`로 받으므로 사내 Nexus npm 프록시로 설치할 수 있습니다. codebase-memory-mcp는 npm `postinstall`이 GitHub Releases에서 바이너리를 내려받아서 그대로는 설치되지 않습니다.

graph 인덱싱은 전체 구조 파악과 호출 체인 추적에는 강하지만, 경로를 아는 파일이나 단순 문자열 검색에서는 grep·Read보다 비쌉니다. 그래서 도구를 하나로 몰지 않고 질문 유형별로 나누는 라우팅 규칙을 두기로 했습니다.

## 2. 실측 결과

공개 Spring Boot 프로젝트를 codegraph로 인덱싱하고 MCP 도구를 직접 호출해 응답 크기를 쟀습니다. 토큰은 글자 수 ÷ 4로 어림했습니다. 측정 조건은 [6. 측정 환경](#6-측정-환경)에 있습니다.

### 2.1 질문 유형별 응답 크기

| 질문 | 좁은 도구 | `explore` | grep |
| --- | --- | --- | --- |
| `getAdminByUsername`(고유한 이름) 호출자 | callers 약 40 tok | 약 6,200 tok | 5줄, 약 170 tok |
| `UmsAdminService.delete`(흔한 이름) 호출자 | callers 약 40 tok, 정답 1건 | 약 6,200 tok | 31줄 중 관련 1줄, 약 1,100 tok |
| `deleteBrand`(오버로드) 영향도 | impact 약 145 tok, HTTP 라우트 포함 | 약 6,200 tok | 10줄, 약 300 tok |
| 로그인 메서드 하나 읽기 | node 약 470 tok | 약 6,200 tok | – |
| 파일 하나 읽기 | node 약 3,000 tok | – | Read 약 2,800 tok |

### 2.2 흐름 질문 (관리자 로그인과 JWT 발급)

| 방식 | 호출 수 | 결과 크기 |
| --- | --- | --- |
| 좁은 도구로 재구성 (node 4번 + callees 1번, 이름을 아는 상태) | 5번 | 합계 약 1,770 tok |

`node`는 채택 구성에서 제외했으므로, 채택 구성에서 같은 작업은 callees와 Read로 합니다(2.3절).
| `explore` (심볼 이름을 넣은 질의) | 1번 | 약 6,200 tok |
| `explore` (자연어 질의) | 1번 | 약 5,400 tok |

### 2.3 X에서 Y까지 (`UmsAdminController.login` → `JwtTokenUtil.generateToken`)

실제 경로는 컨트롤러 → `UmsAdminService.login`(인터페이스) → `UmsAdminServiceImpl.login` → `jwtTokenUtil.generateToken()`입니다.

| 방식 | 결과 | 크기 |
| --- | --- | --- |
| `callees`로 한 단계씩 | 3번 호출로 구현체까지 도달했습니다. 인터페이스에 건 callees가 구현체를 반환했습니다. 구현체의 callees 목록에 `generateToken`이 없어 끊긴 지점이 드러났습니다. | 약 350 tok |
| `explore` (X와 Y 이름 지정) | 흐름(Flow) 절이 없었습니다. 경로를 찾지 못했다는 표시도 없이 관련 소스로 채워졌습니다. | 약 6,200 tok |

### 2.4 고정 비용

아래 항목은 세션에 한 번이 아니라 **매 턴** 모델 입력에 다시 들어갑니다. 토큰은 한글 1자 ≈ 1 tok, 그 밖의 문자 4자 ≈ 1 tok으로 어림했습니다.

| 항목 | 크기 | 턴당 (어림) |
| --- | --- | --- |
| 서버 지침 (MCP `initialize` 응답) | 6,718자 | 약 1,700 tok |
| steering 규칙 `codegraph-usage.md` (`always`) | 2,712자 (한글 907자) | 약 1,400 tok |
| 도구 정의: explore / callers / callees / impact | 1,786자 / 1,125자 / 1,081자 / 1,057자 | 합계 약 1,260 tok |
| **채택 구성의 턴당 합계** | | **약 4,300 tok** |
| (참고) 근거 문서 `codegraph-usage-rationale.md` (`manual`) | 약 8,300자 | 불러올 때만 약 4,600 tok |
| (참고) 제외한 도구 정의: node / search | 2,951자 / 1,170자 | – |

서버 지침을 끄는 옵션은 소스에 없습니다. 따라서 서버 지침과 `explore` 정의(약 2,150 tok)는 codegraph를 켜는 한 항상 듭니다.

### 2.5 관찰된 동작

- **`explore`의 응답은 상한까지 채워집니다.** 질문 4개가 모두 약 24,900자였습니다.
- **흔한 이름에서는 `explore`도 노이즈에 걸립니다.** "who calls UmsAdminService.delete"라고 질의하자 무관한 `SmsFlashPromotion*Controller.delete` 등을 단어 매칭으로 끌어왔습니다. 정답은 영향 범위 요약에만 있었습니다.
- **자연어 질의는 핵심 구현을 빠뜨렸습니다.** `UmsAdminServiceImpl.login` 본문이 "Not shown" 목록으로 밀려났고, 그 자리는 `UmsAdminLoginLog`의 getter가 채웠습니다. 이름을 넣은 질의에서는 흐름과 `UmsAdminService.login → UmsAdminServiceImpl:98` 구현체 연결이 함께 나왔습니다.
- **인터페이스 메서드의 `callers`는 구현체 내부의 자기 호출을 빠뜨립니다.** `UmsAdminService.getAdminByUsername`의 callers는 1건이었지만, `UmsAdminServiceImpl` 126행과 267행에서도 호출합니다.
- **워크트리 DB는 메인 저장소의 데몬이 `projectPath`로 엽니다.** 워크트리에서 새 호출자를 추가하자, `projectPath`를 준 조회에는 약 1.5초 뒤 반영됐습니다(호출자 2건). `projectPath` 없이 조회하면 메인 DB 결과가 그대로 나왔습니다(1건).
- **수정 직후에는 신선도 경고가 붙습니다.** 1.5초 뒤 조회에 "edited 1563ms ago, indexing in progress" 배너가 나왔고, 4초 뒤에는 사라졌습니다.
- **그래프가 평범한 메서드 호출을 놓쳤습니다.** `jwtTokenUtil.generateToken(userDetails)` 호출 2곳(admin·portal 서비스 구현체)이 callers와 callees 어디에도 없었습니다. 같은 필드를 통한 `refreshHeadToken`, `getUserNameFromToken` 호출은 모듈을 넘어서도 잡혔습니다. `generateToken`이 오버로드된 메서드라는 점이 의심되지만, 오버로드인 `deleteBrand`는 정상이어서 원인은 확정하지 못했습니다.
- **`.worktrees/`가 gitignore에 제대로 등록되지 않으면 메인 DB가 오염됩니다.** 메인 데몬의 watcher가 워크트리에서 수정된 파일을 메인 DB에도 넣어 결과가 중복됐습니다.

## 3. 설계 결정

### 3.1 도구 4개 고정 (`CODEGRAPH_MCP_TOOLS=explore,callers,callees,impact`)

`callers`와 `impact`는 grep이 가장 약한 지점(흔한 이름, 인터페이스↔구현체, 오버로드)을 메웁니다. `callees`는 "X에서 Y까지" 흐름 질문을 맡습니다(2.3절). 세 도구의 정의는 턴당 약 820 tok입니다. 세션 앞쪽 87% 안에서 `explore`를 한 번만 피해도 남습니다(3.4절).

초안(2026-10-31)에서는 `callees`가 근거 없이 빠져 있었습니다. 흐름 질문을 codegraph로 처리하는 프로젝트 steering을 검토하다가 확인했고, 실측 후 추가했습니다.

`search`는 Java 클래스명이 대체로 고유해서 grep으로 충분하다고 보고 제외했습니다. `node`는 파일 모드 결과가 Read와 크기가 같고(12,037자 대 원본 11,227자) 도구 정의가 가장 커서 제외했습니다.

codegraph 작성자는 메뉴가 길면 에이전트가 도구를 잘못 고른다는 측정을 근거로 `explore` 하나만 노출합니다. 다만 그 측정은 아키텍처 질문 하나짜리 벤치마크라 호출자나 영향도 같은 중간 질문은 다루지 않았습니다. 그래서 질문 유형마다 도구가 하나씩 대응하도록 메뉴를 4개로 최소화했습니다.

### 3.2 검토했다 버린 대안

| 대안 | 버린 이유 |
| --- | --- |
| `explore`를 완전히 끈다 | 좁은 도구는 이름을 알아야 쓸 수 있습니다. 이름을 모르면 탐색 왕복이 늘어나고, 왕복마다 전체 컨텍스트를 다시 읽어 처리 토큰이 커집니다. |
| 메인 저장소는 3개, 워크트리는 2개 도구로 나눈다 | `.worktrees/`가 메인 저장소 안에 있어서 MCP 프로세스가 1개만 뜹니다. 도구 허용 목록은 프로세스 단위라 저장소별로 나눌 수 없습니다. |
| spec 단계와 구현 단계에 다른 에이전트를 둔다 | Kiro의 spec 전용 에이전트는 빌트인이라 수정할 수 없습니다. |
| steering을 `inclusion: fileMatch`(`**/*.java`)로 바꾼다 | 턴당 약 1,400 tok을 아끼지만, Java 파일을 열기 전의 첫 탐색 질문에서 규칙이 빠집니다. 가장 자주 쓰는 탐색 질문에서 규칙이 빠지면 서버 지침대로 `explore`부터 부르게 됩니다. |
| `explore` 중복 제거(`CODEGRAPH_EXPLORE_DEDUP=1`)를 켠다 | 이미 보낸 소스를 생략한 자리를 다른 소스로 다시 채워서 응답이 거의 줄지 않습니다. 같은 질의를 반복해도 24,979자에서 22,052자로 12% 줄었습니다. dedup 상태는 MCP 연결 단위라서, Kiro가 대화를 요약한 뒤에는 모델이 갖고 있지 않은 소스를 생략할 위험이 있습니다. |

결국 도구 수를 동적으로 바꾸지 않고 규칙으로 제한합니다. 규칙에는 강제력이 없으므로, 필요하면 Kiro `mcp.json`의 `autoApprove`에 `callers`, `callees`, `impact`만 넣어 `explore` 호출 때 승인 창이 뜨게 하는 방법을 보조로 검토합니다.

### 3.3 규칙 문서와 근거 문서 분리

steering을 `inclusion: always`로 두면 매 턴 컨텍스트를 차지합니다. 그래서 규칙(`codegraph-usage.md`, always)과 근거(`codegraph-usage-rationale.md`, manual)를 나누고, 같은 규칙 ID(R1–R16)로 연결합니다. 규칙 파일은 턴당 약 1,400 tok, 근거 파일은 불러올 때만 약 4,600 tok이 듭니다. 두 파일은 4장에 있습니다.

### 3.4 턴당 고정 비용과 손익분기

도구 정의와 steering은 첫 턴부터, `explore` 결과는 호출한 시점부터 매 턴 다시 읽힙니다. 그래서 T턴 세션의 k번째 턴에서 `explore`(약 6,200 tok)를 한 번 피했을 때를 기준으로 비교했습니다.

| 결정 | 턴당 비용 | 손익분기 | 결론 |
| --- | --- | --- | --- |
| 좁은 도구 3개 추가 (callers·callees·impact) | 약 820 tok | k ≤ 0.87T | 유지 |
| callees 단독 | 약 270 tok | k ≤ 0.95T | 유지 |
| steering `always` | 약 1,400 tok | k ≤ 0.78T | 유지 |
| `explore`를 끄는 대안 | 약 450 tok 절약 | 이름을 모르는 탐색의 왕복 증가 비용이 더 큼 | 계속 기각 |

세션 앞쪽 78% 안에 관계 질문(호출자, 흐름, 영향도)이 한 번만 나와도 세 결정 모두 이득입니다. Java/Spring 코드 작업 세션이라면 거의 항상 나옵니다.

반대로 codegraph를 쓰지 않는 세션(문서·설정 작업)에서는 약 4,300 tok이 턴마다 그대로 낭비됩니다. 피하려면 그 세션에서 MCP 서버를 꺼야 합니다. 그런 세션이 드물다면 감수합니다. 프롬프트 캐시가 적용되면 비용은 크게 줄지만 컨텍스트 창 점유는 그대로이고, Kiro가 캐시를 쓰는지는 확인하지 못했습니다.

## 4. 규칙과 근거 파일

Kiro에 그대로 넣는 원본은 [`kiro-steering/`](kiro-steering/) 폴더의 두 파일입니다. 규칙과 근거를 이 노트에 복사해 두면 수정할 때 서로 어긋나므로, 원본은 두 파일로만 관리합니다.

| 파일 | 넣을 위치 | inclusion | 내용 |
| --- | --- | --- | --- |
| [codegraph-usage.md](kiro-steering/codegraph-usage.md) | `.kiro/steering/` | always | 규칙 R1–R16 |
| [codegraph-usage-rationale.md](kiro-steering/codegraph-usage-rationale.md) | `.kiro/steering/` | manual | 규칙별 근거와 태그([실측]/[소스]/[문서]/[추정]/[판단]), 측정 환경, 변경 이력 |

규칙 구성은 다음과 같습니다.

| 규칙 | 내용 |
| --- | --- |
| R1–R2 | 서버 지침보다 우선, 도구 4개 |
| R3–R5 | 가장 싼 도구부터, grep 30건 기준, 상황별 도구 표 |
| R6–R9 | explore 사용 조건: 이름을 모를 때만, 주제당 1회, 질의에 이름 포함, spec 구현 중 금지 |
| R10 | 워크트리는 `projectPath` 필수 |
| R11–R12 | Spring 검증: 인터페이스·구현체 함께 조회, 영향 범위 확정 시 grep 교차 확인 |
| R13–R15 | 인덱스 신선도 배너 대응, `init` 직접 실행 금지 |
| R16 | 호출 흐름: X에서 `callees`로 한 단계씩, 끊기면 그 메서드 본문 Read |

MCP 설정(`.kiro/settings/mcp.json`)에는 다음 환경변수를 둡니다.

```json
{
  "mcpServers": {
    "codegraph": {
      "command": "codegraph",
      "args": ["serve", "--mcp"],
      "env": {
        "CODEGRAPH_MCP_TOOLS": "explore,callers,callees,impact",
        "CODEGRAPH_TELEMETRY": "0"
      }
    }
  }
}
```

## 5. 미검증 사항

| 항목 | 확인 방법 |
| --- | --- |
| Kiro가 codegraph 서버 지침을 모델에 반영하는지 (R1) | 규칙 없이 단순 조회를 시켜 보고 `explore`를 먼저 부르는지 관찰 |
| 에이전트가 규칙대로 도구를 고르는지 (R3–R9) | 사내 대표 Spring 모듈로 질문 유형별 3–4개씩 실행해 호출 로그 확인 |
| Spring 특유의 연결을 그래프가 놓치는지 (R12). 평범한 호출 누락은 실측으로 확인됨 | AOP, 이벤트 리스너, MyBatis XML이 있는 메서드에 `callers`·`impact`를 걸어 grep 결과와 비교. 잘 잡히는 항목은 목록에서 삭제 |
| grep 30건 기준의 적정성 (R4) | 사내 코드에서 흔한 메서드명의 grep 결과 수 분포 확인 |
| `autoApprove` 지원 여부 (3.2절) | 사내 Kiro 버전의 `mcp.json` 스키마 확인 |
| `explore` 응답 상한과 인덱스 규모의 관계 | 사내 대형 저장소에서 응답 크기 측정 |
| Kiro의 프롬프트 캐시 적용 여부 (3.4절) | 사내 Kiro 환경의 요청 로그나 사용량 화면에서 캐시 읽기 토큰 확인 |
| `generateToken` 호출 누락의 원인 (R12, R16) | 사내 코드에서 오버로드된 메서드의 callers를 grep과 비교 |

## 6. 측정 환경

- 대상: [macrozheng/mall](https://github.com/macrozheng/mall). Spring Boot와 MyBatis를 쓰고, Java 파일 524개, 인덱싱된 파일 651개입니다(노드 23,501개, 엣지 48,178개).
- 도구: codegraph 1.6.2 Linux x64 번들. MCP stdio로 도구를 직접 호출했습니다.
- 워크트리: 메인 저장소 안 `.worktrees/feat-a`(gitignore 등록)로 사내 구조를 재현했습니다.
- 토큰은 글자 수 ÷ 4로 어림했습니다.
- 한계: 응답 크기만 쟀고, 에이전트(Kiro)가 실제로 도구를 어떻게 고르는지는 측정하지 않았습니다. 중형 저장소 하나에서의 결과입니다.

## 변경 이력

- 2026-10-31: 초안. 3개 도구 고정과 라우팅 규칙 방식을 채택했습니다.
- 2026-10-31: steering 원본 파일 2개를 `kiro-steering/`에 추가하고, 노트에 복사해 두었던 규칙 원문과 근거 표를 파일 링크로 대체했습니다.
- 2026-11-01: `CODEGRAPH_EXPLORE_DEDUP`을 검토했다 버린 대안에 실측값과 함께 추가했습니다.
- 2026-11-02: `callees`를 추가해 도구를 4개로 늘리고, 호출 흐름 규칙 R16과 X→Y 실측(2.3절), 그래프의 호출 누락 사례를 추가했습니다.
- 2026-11-02: 고정 비용을 턴당 비용으로 다시 계산했습니다(2.4절, 3.4절). steering 크기를 실측값에 추가했고, 결정 자체는 바뀌지 않았습니다. steering의 `fileMatch` 전환을 검토했다 버린 대안에 추가했습니다.
