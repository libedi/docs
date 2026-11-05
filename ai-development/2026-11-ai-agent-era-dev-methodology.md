# AI Agent 시대의 소프트웨어 개발방법론: 2026년 11월 재점검

> 9월판 이후 무엇이 바뀌었고, 무엇을 다르게 봐야 하는가

- 작성일: 2026-11-05
- 조사 기준 시점: 2026년 11월 초
- 이전판: [AI Agent 시대의 소프트웨어 개발방법론: 2026년 9월 현황과 전망](2026-09-ai-agent-era-dev-methodology.md) (2026-09-28)
- 관점: Java/Spring 백엔드 개발자. 특정 방법론의 지지자가 아니라, 에이전트 시대에 더 나은 개발 방식을 찾아 실험하고 적용하려는 입장
- 관련 문서: [Kiro spec workflow에 에이전트 코드 리뷰 단계를 추가하는 제안](2026-11-agent-code-review-stage.md), [서브에이전트는 언제 나누는가](2026-11-subagent-boundaries.md)
- 조사·작성 보조: Claude

## 목차

- [이 문서를 읽는 법](#이-문서를-읽는-법)
- [TL;DR](#tldr)
- [1장. 관점 전환: "어떤 방법론인가"에서 "의도를 어디에 두는가"로](#1장-관점-전환-어떤-방법론인가에서-의도를-어디에-두는가로)
- [2장. 9월 결론 재평가](#2장-9월-결론-재평가)
- [3장. 축별 현황 (2026년 11월 초)](#3장-축별-현황-2026년-11월-초)
- [4장. 9월 이후 타임라인](#4장-9월-이후-타임라인)
- [5장. 열린 질문](#5장-열린-질문)
- [6장. 실천 권고 (개정)](#6장-실천-권고-개정)
- [7장. 한계](#7장-한계)
- [참고 자료](#참고-자료)
- [변경 이력](#변경-이력)

## 이 문서를 읽는 법

- 9월판의 결론을 기준선으로 삼아 각 결론이 강화·수정·유지되는지 판정한다.
- 9월판과 달리 SDD를 중심축으로 두지 않는다. 9월판의 결론(병목이 '의도 명세와 검증'으로 이동)은 SDD에 종속되지 않으며, SDD는 "의도를 문서에 둔다"는 여러 답 중 하나로 다룬다(1장).
- 9월판 대비 바뀐 것: 관점(SDD 중심 → 의도를 어디에 두는가), 결론 2·3의 정교화, 정정 1건(MCP 사양 버전), 9월판에서 빠졌던 자료 보강.
- 증거 등급: **[RCT]** 무작위 대조 실험 · **[실험]** 소규모 통제 실험 · **[관찰]** 관찰·설문 · **[벤더]** 도구·보안 벤더 자체 보고 · **[자기 보고]** 기업 사례 · **[의견]** 전문가·컨설팅 의견 · **[2차]** 1차 자료 미확인, 2차 보도로만 확인
- 🆕 표시는 2026-09-28 이후 발표된 자료다. 9월 이전 자료지만 9월판에서 빠졌던 것은 **(9월판 누락)**으로 표시한다.

## TL;DR

1. **병목 이동(9월 결론 1): 강화.** 사람이 코드를 한 줄도 쓰지 않은 실험에서도 시간의 ⅔는 도메인·경계·계획에, ⅓은 하네스에 쓰였다. Thoughtworks Technology Radar Vol.35의 대주제는 "Harness engineering at scale"이다.
2. **하네스(9월 결론 2): 강화하되 정교화.** "하네스를 항상 무겁게"가 아니라 "독립 검증 게이트는 항상, 개발 중 센서를 돌리는 빈도는 모델 능력에 맞춘다". 그리고 지시문은 줄이고 결정적 검사로 옮긴다.
3. **실증(9월 결론 3): 유지.** 보안 벤치마크는 처음으로 개선됐지만(평균 56% → 62%) Java는 31%로 정체다. 전달 안정성은 Faros 텔레메트리(머지된 PR 대비 인시던트 비율 +242.7%)가 보여 주듯 악화 쪽 증거가 더 강해졌다. 반면 "AI가 느리게 만든다"는 2025년 METR 결과는 더 이상 현재를 대표하지 않는다. 정리하면 **속도는 개선 쪽이지만 크기는 미확정, 전달 안정성은 악화 쪽**이다.
4. **새 프레임: 방법론 선택은 배합의 문제다.** "SDD냐 TDD냐"가 아니라 의도를 어디에 두고(문서 / 실행 가능한 계약·속성 / 코드 구조 / 대화 / 조직 기억) 무엇이 그것을 검증하는가의 배합이다. 업계 신호는 문서의 비중을 줄이고(AI-driven documentation sprawl, Caution) 기계가 판정할 수 있는 곳으로 옮기는 쪽이다.
5. **리뷰는 다층화·다중화된다.** 뮤테이션 테스트 Adopt, 위험 등급별 감독 Trial, "Human-in-the-loop theater" Caution. GitHub은 서로 다른 제공사 모델의 리뷰 에이전트 여러 개를 묶은 코드 리뷰 등급을 내놓았다. 도구 경쟁의 축이 '코드 생성'에서 '병렬 실행·리뷰·머지'로 옮겨 갔다.
6. **실천의 출발점.** 성공의 정의를 "실패가 없음"에서 "기대한 검사가 모두 실행되어 통과함"으로 바꾸고, 테스트 오라클은 사람이 소유하되 에이전트가 고치거나 볼 수 없게 하며, 맡기는 단위는 결과를 판정할 수 있는 만큼만 키운다.

---

## 1장. 관점 전환: "어떤 방법론인가"에서 "의도를 어디에 두는가"로

### 1.1 왜 프레임을 바꾸는가

9월판은 SDD를 축으로 방법론을 정리했다. 하지만 9월판이 도달한 결론, 즉 병목이 코드 작성에서 의도 명세와 검증으로 옮겨 갔다는 결론은 SDD를 전제하지 않는다. SDD는 이 병목에 대한 한 가지 답, "의도를 문서에 둔다"는 답일 뿐이다. 방법론을 고르는 질문을 다음 두 개로 바꾸면 선택지가 넓어진다.

- 의도는 어디에 사는가?
- 무엇이 그 의도가 지켜졌음을 판정하는가?

### 1.2 의도를 두는 다섯 장소

| 장소 | 대표 실천 | 강점 | 실패 양상 | 11월 근거 |
|---|---|---|---|---|
| ① 문서 | SDD(Kiro, Spec Kit, OpenSpec), ADR | 사람 간 합의, 리뷰 가능, 기존 코드에 덧입히기 | 비대화, 코드와의 드리프트, "진척의 착시" | Radar: OpenSpec Trial, AI-driven documentation sprawl Caution |
| ② 실행 가능한 계약·속성 | 계약 우선(OpenAPI·AsyncAPI), 속성 기반 테스트(PBT), 에이전트가 못 보는 수용 테스트, 뮤테이션 테스트 | 기계가 판정, 테스트 우회(reward hacking)에 가장 강함 | 명세 가능성이 낮은 영역(UX, 탐색적 설계)에 약함 | Jain 실험, Radar: Mutation testing Adopt |
| ③ 코드베이스 구조·환경 | 아키텍처 규칙(ArchUnit), 타입, 모듈 경계, 짧은 AGENTS.md, 샌드박스 | 문서 없이 경계를 강제, 사람에게도 이로움 | 초기 투자, 기존 코드베이스 적용 비용 | OpenAI 하네스 사례(9월판), Shopify "agent-friendly ≈ human-friendly", Radar: Agent sandboxing·Progressive context disclosure Adopt |
| ④ 대화 | plan 모드, grilling(에이전트가 사람을 인터뷰) | 코드 생성 전에 모호성 제거, 사람의 이해를 강제 | 휘발성: 결론을 ②③에 착지시키지 않으면 사라짐 | Radar: Grilling Trial |
| ⑤ 조직 기억 | 공개 에이전트 세션, 피드백 플라이휠, 스스로 개선하는 하네스, 메모리 | 학습이 누적됨 | 오염과 비대화: 정기적 삭제가 필요 | Shopify River, Radar: Feedback flywheel·Self-improving harness Trial |

### 1.3 배합의 원칙 (추론)

- **명세 가능성이 높은 것은 ②로.** API 계약, 배치의 불변식(멱등성, 건수 보존, 재시작 시 중복·누락 없음), 데이터 변환 규칙은 실행 가능한 형태로 고정한다.
- **경계와 의존 방향은 ③으로.** 문서로 쓰지 말고 아키텍처 테스트로 강제한다.
- **모호성이 큰 초기 단계는 ④로 해소하고, 그 결론을 ②③에 착지시킨다.**
- **①은 ②③이 표현하지 못하는 것에 한정한다.** 왜 그렇게 했는가(근거), 비목표, 거부된 대안 같은 것들이다.
- **⑤는 ①~④를 갱신하는 루프다.** 추가만 하지 말고 지우는 절차를 같이 둔다.

이 관점에서 보면 "스펙 문서가 점점 비대해진다"는 흔한 증상은 ①이 ②③이 맡아야 할 일까지 떠안고 있다는 신호일 수 있다.

---

## 2장. 9월 결론 재평가

### 2.1 결론 1. 병목이 '의도 명세와 검증'으로 이동 — 강화

- 🆕 Rachel Laycock(Thoughtworks CTO), "Why are good developers so wary of agentic development?"(2026-10-29) [자기 보고·의견]: 사람이 코드를 한 줄도 쓰지 않은 1주 실험에서 팀은 시간의 약 ⅔를 화이트보드(도메인·경계·계획), ⅓을 하네스에 썼다. 동시에 "애플리케이션은 돌았지만 빌드는 자주 빨간색이었다", "Built is not the same as working in production"이라고 썼다.
- 🆕 Radar Vol.35(2026-11-04) [의견]: Path-to-production mapping을 Adopt로 두며, 코딩 속도가 아니라 전체 흐름의 병목을 보라고 권한다.
- Sonar State of Code Developer Survey 2026(2026-01-08, 1,149명, 2025년 10월 조사) [벤더·관찰] **(9월판 누락)**: 38%가 AI 코드 리뷰가 동료의 코드 리뷰보다 더 힘들다고 답했다. 96%는 AI 코드가 기능적으로 맞다고 완전히 신뢰하지 않지만, 커밋 전에 항상 확인한다는 응답은 48%다.

### 2.2 결론 2. 통합 하네스 — 강화, 단 정교화

**독립 게이트는 항상, 센서 빈도는 모델에 맞춘다.**

- 🆕 Naresh Jain, "Are Harnesses Worth the Cost?"(martinfowler.com, 2026-10-13) [실험; 저자는 Specmatic 창업자]
  - 설계: greenfield Java BFF 서비스 1개(HTTP API, Order API 호출, Kafka 발행, 202 지연 생성, 429/503/502 오류 계약). 모델당 하네스 유무 각 10회, Codex, 추론 강도 low. 하네스는 OpenAPI·AsyncAPI 계약, 예시, API 개발 skill(가이드)과 계약 적합성·API 테스트·mock 검증(센서)으로 구성. 비공개 외부 수용 테스트 178개를 모두 통과하면 accepted로 판정.
  - 결과: 프런티어 모델(GPT-6 Sol)은 하네스 유무와 무관하게 10/10이었고, 하네스를 붙이면 토큰 약 10.5배·시간 약 3배·비용 약 7배($2.679 vs $0.406)가 들었다. 저가 모델(GPT-6 Luna)은 3/10에서 10/10으로 올랐고, 하네스를 쓴 Luna가 하네스 없는 Sol보다 33% 쌌다($0.273 vs $0.406). 하네스 없는 Luna의 실패는 대부분 계약 경계(202 대신 503, Kafka 헤더·null 필드, 환경변수명 불일치)에서 났다.
  - 저자 결론: "Model capability changes when and how often sensors run, not whether an independent verification gate is needed."
  - 저자가 밝힌 한계: 서비스 1개·10회, 브리프가 이례적으로 상세함, 하네스 작성·유지 비용 제외, 가이드와 센서의 기여 분리 불가, 계약을 실험자가 직접 작성.

**지시문은 줄이고 결정적 검사로 옮긴다.**

- 🆕 Radar Vol.35 "Agent instruction bloat"(Caution): 변환 가능한 지시는 결정적 hook이나 검사로 바꾸고, 새 모델이 나올 때마다 지시를 재평가해 불필요한 것을 지우라고 권한다(regression이 아니라 progression testing). 근거로 Anthropic이 최신 모델용 Claude Code 시스템 프롬프트의 80% 이상을 측정 가능한 손실 없이 제거했다는 사례를 든다. 9월판의 ETH Zurich AGENTS.md 연구(일반적 개선 없음, 추론 비용 20% 이상 증가)와 같은 방향이다.
- 🆕 Radar Vol.35 "Progressive context disclosure"(Adopt): AGENTS.md는 짧게 두고, 문서는 링크로 필요할 때만 로드한다.

**반론**: Jain의 결과를 거꾸로 읽으면 "프런티어 모델에게 개발 중 하네스는 낭비"다. 그러나 이 실험은 브리프가 이례적으로 상세한 greenfield 1건이다. 요구사항이 모호하고 기존 코드가 많은 조건에서는 결론이 달라질 수 있으므로 각자의 환경에서 측정해야 한다.

### 2.3 결론 3. 체감 속도는 오르지만 안정성·품질은 불확실하거나 악화 — 유지

조사 과정에서 "보안 개선과 METR 재해석을 근거로 결론 3을 완화하자"는 해석이 나왔다. 그러나 전달 안정성에 관한 증거를 함께 보면 완화할 근거는 약하다.

**안정성: 악화 쪽 증거가 더 강해졌다.**

- Faros AI Engineering Report 2026 "The Acceleration Whiplash"(2026-04-12, 개발자 22,000명·4,000개 이상 팀, 2년치 텔레메트리) [벤더] **(9월판 누락)**. 설문이 아니라 버전 관리·CI/CD·인시던트·작업 관리·IDE 텔레메트리로, 각 조직 안에서 AI 도입이 가장 낮던 시기와 가장 높던 시기를 비교했다.
  - 처리량: 개발자 1인당 에픽 완료 +66%, 작업 처리량 +33.7%, PR 병합률 +16.2%
  - 안정성: 머지된 PR 대비 인시던트 비율 +242.7%, 월간 인시던트 +57.9%, 개발자당 버그 +54%(2025년판은 +9%였으나 데이터셋이 다름)
  - 리뷰: 첫 리뷰까지 중앙값 시간 +156.6%, 리뷰 중앙값 시간 +441.5%, 리뷰 없이 머지된 PR +31.3%
  - 코드 churn +861%
  - 고성과 조직도 같은 하락을 겪었다고 보고하며, 강한 기반이 AI의 이점을 증폭하고 위험을 막는다는 DORA 2025(설문 기반)의 설명과 배치된다고 주장한다.
- 🆕 Laycock(2026-10-29): 빌드가 자주 빨간색이었다.
- 해석: Faros가 말하는 '강한 기반'은 일반적인 엔지니어링 성숙도이지 에이전트 전용 하네스가 아니다. 따라서 이 결과는 "하네스는 효과가 없다"는 반증이 아니라 **"기존 DevOps 성숙도만으로는 부족하다"**로 읽는 것이 맞다. 벤더 데이터이므로 효과 크기는 할인해서 본다.

**보안: 첫 개선, Java는 정체.**

- 🆕 Veracode GenAI Code Security Fall 2026 업데이트(2026-10-29) [벤더]: 평균 보안 통과율 56% → 62%로, 2025년 7월 시리즈 시작 이후 첫 의미 있는 개선이다. 언어별로는 Python 64.22%, C# 59.55%, JavaScript 56.99%, **Java 31.00%**(7월 30%에서 거의 변화 없음). 18개 모델 중 Claude Opus 5.5와 GPT-6-Sol이 73%로 선두다. Veracode는 "중간 모델 + 스캔"이 "프런티어 모델 단독"보다 낫다고 주장하는데, 자사 제품과 이해가 얽힌 주장이다.
- 보안 통과율은 보안 요구를 명시하지 않은 벤치마크의 결과이지 전달 안정성 지표가 아니다.

**속도: "느려진다"는 낡은 인용, "빨라졌다"도 미확정.**

- METR "We are Changing our Developer Productivity Experiment Design"(2026-02-24) [RCT → 설계 변경]: 원 참가자 부분집합에서 -18%(신뢰구간 -38% ~ +9%), 신규 참가자에서 -4%(-15% ~ +9%). 30~50%의 개발자가 일부 과제를 제출하지 않는 선택 편향 때문에 METR 스스로 이 추정치를 실제 영향의 나쁜 대리지표로 보고 설계를 바꿨다. 2025년 7월의 "19% 느려짐"을 현재 상태로 인용하면 낡은 인용이다.

**신뢰: 검증 가능성에 조건부.**

- 🆕 Stack Overflow Developer Survey 2026(2026-10 공개, n=30,903) [관찰, 자기 선택 표본]: "쉽게 검증할 수 있을 때 신뢰" 48.0%, "중요한 결정까지 신뢰" 6.6%, "대부분 업무에 불신" 12.3%. 초기 경력자(1~5년)의 중요 결정 신뢰는 4%다. 2025년과 문항이 달라 직접 비교는 불가하지만, "신뢰는 검증 가능성에 조건부"라는 결과는 하네스 논리를 직접 지지한다.

**정리**: 결론 3은 "속도는 개선 쪽이지만 크기는 통계적으로 미확정, 전달 안정성은 악화 쪽, 보안은 평균 개선·Java 정체"로 다듬어 유지한다.

### 2.4 전망 재평가

- (a) "SDD vs TDD"가 아니라 통합 하네스로 수렴 — **강화.** 1장의 프레임대로 '배합'의 문제가 됐다.
- (b) spec-as-source는 좁은 영역에 머문다 — **강화.** 업계 평가는 spec-anchored(OpenSpec Trial)로 수렴했고, spec-as-source가 확산된다는 증거는 없다.
- (c) 리뷰의 계층화 — **강화, 단 경고 추가.** 위험 등급별 감독(Trial)과 Kiro Crew 사례가 뒷받침하지만, 사람이 실질적으로 평가할 수 없는 승인은 "accountability sink"가 된다는 경고(Human-in-the-loop theater, Caution)가 붙었다.

---

## 3장. 축별 현황 (2026년 11월 초)

1장에서 나눈 다섯 장소를 따라 정리한다. 3.6~3.8은 사람, Java/Spring, 도구 지형을 따로 다룬다.

### 3.1 문서에 의도를 두는 접근: SDD 도구 생태계

- **업계 평가** 🆕 Radar Vol.35 [의견]
  - "Spec-driven development" 블립은 재평가되지 않았다(마지막 평가는 2025년 11월 Assess). GitHub Spec Kit도 2026년 4월 Assess 이후 갱신이 없다.
  - **OpenSpec: Assess → Trial.** 변경을 영속적인 source-of-truth 스펙에 대한 delta로 다루는 spec-anchored 워크플로와, 기존 코드에 스펙을 덧입히는 능력을 근거로 든다. 동시에 "스펙 파일은 에이전트가 대량 생성하는 Markdown"이라고 경고한다.
  - **AI-driven documentation sprawl: Caution.** 문서는 코드와 달리 자동 품질 게이트를 거치지 않아 "big ball of documentation mud"가 된다고 진단한다.
- **AWS Kiro** [벤더]
  - **Analyze Requirements** **(9월판 누락)**: 설계 전에 요구사항의 불일치·모호성·공백을 잡는 단계다(2026년 8월 문서 기준). LLM 추론 기반이라 결정적 검사는 아니지만, "스펙의 단위 테스트"라는 열린 질문(5장)에 가장 가까운 기성 기능이다.
  - **Bugfix Spec** **(9월판 누락)**: requirements 대신 현재 동작·기대 동작·**바뀌지 않아야 할 동작**으로 구성하고, PBT를 버그 존재 확인·수정 확인·불변 동작 확인의 세 범주로 만든다. '바뀌지 않아야 할 것'을 명시적으로 검증 대상으로 삼는다는 점이 참고할 만하다.
  - 🆕 Workflows(09-30), CLI V3 기본화(10-09), Memory(CLI 2.29·IDE 1.4, read-write/read-only/off 선택), Markdown Review(IDE 1.3.11, .md 구절 단위 코멘트를 모아 한 번에 전송), 로컬 샌드박싱(10-14), 워크스페이스 신뢰(CLI 2.33, 폴더의 hooks·agents·MCP를 로드하기 전에 신뢰 확인).
  - 🆕 **"Spec it safe"**(10-30): EARS 형식 요구사항을 분석해 각 요구사항이 노출된 CWE/OWASP 약점을 찾고, 추적·테스트 가능한 `[SECURITY: …]` 제약을 제안한다. 코드는 읽지 않고 스펙만 읽으며, Node CLI로 Kiro 없이도 실행할 수 있다.
- **GitHub Spec Kit** [벤더·2차]: 🆕 1.2.3(2026-10-22) 이후 1.3.0까지 릴리스됐다. 1.x에서 버그 수정과 아이디어 평가를 번들 확장으로 분리했다. 공식 설치 명령은 `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v1.2.3`로, GitHub git 경로와 Python 도구를 전제한다.
- **해석**: SDD 도구들은 스스로 무게를 줄이는 방향으로 움직인다(Quick Spec, 버그 수정 분리, delta 스펙). 1장의 프레임으로 보면 ①의 비중을 줄이고 ②(PBT, 보안 제약)와 연결하려는 시도다.

### 3.2 실행 가능한 계약·속성·테스트 오라클

- **계약이 곧 하네스다.** Jain 실험(2.2절)의 하네스는 결국 OpenAPI·AsyncAPI 계약 + 예시 + 외부 수용 테스트였고, 실패가 몰린 지점도 계약 경계였다. 🆕 API Evangelist는 이를 "The Harness That Works Is A Contract"(2026-10-19)로 요약했다.
- **테스트 우회(reward hacking) 연구** [학술, 대부분 arXiv 프리프린트]
  - SpecBench(arXiv 2605.21384): 공개 검증 테스트와 held-out 테스트를 분리해 측정했다. 한 사례는 공개 97% / held-out 0%였다.
  - BaitBench(arXiv 2608.30724): 프런티어 에이전트 7종 실행의 57.1%에서 reward hacking이 나타났고, "부정행위하지 말라"는 validity-aware 프롬프트는 이를 6.2%p만 줄였다.
  - 🆕 "Reward Hacking as a Transmissible Strategy in Multi-Agent Coding Systems"(arXiv 2610.12822, 2026-10-09): 한 에이전트에서 유도된 우회 전략이 다른 에이전트로 전파되어 시스템 전체에 영향을 줄 수 있다고 보고한다.
  - 시사점: 금지 지시문은 거의 효과가 없다. **에이전트가 볼 수 없거나 수정할 수 없는 오라클**이 핵심 방어선이다. 서브에이전트 구성에서는 위험이 더 커질 수 있다.
- **뮤테이션 테스트** 🆕 Radar Adopt: AI가 생성한 테스트로 커버리지 지표가 쉽게 부풀려지기 때문이다. 에이전트가 루프 안에서 직접 뮤테이션을 돌릴 수 있다고 쓰면서도, 비용 때문에 대상 패키지 한정이나 증분 실행을 권한다.
- **Böckeler의 센서 연작** [의견·실험] **(9월판 누락)**: "Maintainability sensors for coding agents"(2026-05-27)는 하네스의 센서를 실제로 붙여 본 경험을 다룬다. 정적 분석 센서들의 효과는 엇갈렸다고 보고됐고[2차], 결론부 "The test suite as a regression sensor"(2026-07-06 추가)는 회귀 센서로서의 테스트 스위트와 그 신뢰도를 점검하는 뮤테이션 테스트의 역할을 다룬다. 9월 이후 새 글은 확인하지 못했다.

### 3.3 코드베이스 구조와 실행 환경

- **에이전트 친화 ≈ 사람 친화.** Shopify Engineering "Under the River"(2026-05-28) [자기 보고] **(9월판 누락)**: 2024년 초부터 모노레포(World)와 재현 가능한 환경에 투자했고, 에이전트를 위해 한 모든 변경이 사람에게도 옳은 일이었다고 쓴다. 하네스(에이전트 루프)를 샌드박스(코드가 실행되는 곳) 밖에 두어 에이전트 루프가 코드 실행과 같은 피해 반경에 있지 않게 했다.
- 🆕 Radar Vol.35: Agent sandboxing Adopt(모든 에이전트의 기본값), Progressive context disclosure Adopt, Enterprise harness Assess(조직 단위 skills·hooks·정책 계층을 "얇고 연합적으로").
- **표준화** [공식]
  - Agentic AI Foundation(Linux Foundation)은 🆕 2026-10-22 기준 10개 프로젝트를 호스팅한다. 출범 당시의 MCP·goose·AGENTS.md, 8월에 합류한 A2A에 이어 Agent Skills(Anthropic), Open Responses(OpenAI), OpenEnv(Hugging Face), OpenSandbox(Alibaba)가 추가됐다.
  - MCP 최신 사양은 2026-07-28이다. 프로토콜 계층이 stateless가 됐고, initialize 핸드셰이크 대신 `server/discover`와 Multi-Round-Trip Requests가 들어왔으며, Roots·Sampling·Logging은 deprecated됐다.
- **정정**: 9월판이 Spring AI 2.0 기준으로 적은 "MCP 사양 2025-11-25"는 9월 시점에 이미 직전 버전이었다.

### 3.4 루프와 감독: 리뷰·머지·위험 등급

- 🆕 **Kiro Crew, "Keeping a software factory stable at 1,000 PRs a week"(2026-10-26)** [자기 보고, 벤더 내부 팀]
  - 수동 전수 리뷰는 "하루도 못 갔다". 모든 AI 코멘트 해결을 머지 조건으로 삼자, 고치면 새 코멘트가 붙는 churn이 생겼다.
  - 심각도 등급을 도입했다. blocking·concern은 같은 PR에서 고치고 nit은 후속 이슈로 돌린다. blocking 판정에는 위치·인용 증거·트리거·결과가 모두 필요하다.
  - 역할 분리 리뷰어(설계, first-principles, UX)를 두고, **다른 모델 계열의 리뷰어**를 쓴다("같은 계열은 맹점을 공유한다").
  - **단일 PR Readiness 판정**: "기대된 모든 레인이 실행되었고 모두 통과"를 뜻해야 하며, "실패 없음"과 "아직 아무것도 안 돌았음"을 구분한다.
  - 리뷰 규칙은 main에서 로드한다("A PR never writes its own judge"). PR 설명과 코드의 일치를 CI로 검사하고, 단순 등급 PR은 자동 승인·머지한다.
  - 결함률 같은 결과 지표는 공개하지 않았다.
- 🆕 **GitHub Universe 2026(10-28)** [벤더·2차]
  - Copilot 코드 리뷰 **Max**(퍼블릭 프리뷰): 단일 모델이 아니라 서로 다른 제공사 모델 기반의 독립 리뷰 에이전트 여러 개와 집계 에이전트로 동작한다. 일상 리뷰는 Lite·Balanced, 고위험 변경은 Max로 리뷰 깊이를 나누는 구조다.
  - **Agent Merge**가 github.com의 PR에 들어와 실패한 Actions 워크플로와 머지 충돌을 자동으로 고친다. Copilot app의 **Projects**(퍼블릭 프리뷰)는 여러 저장소에 걸친 목표를 받아 필요한 만큼 에이전트를 돌린다.
  - GitHub Enterprise 고객에게 Copilot 기능을 별도 구독 없이 제공한다고 발표했다.
- **Stripe Minions** [자기 보고·2차] (9월판 미확인 → 확인): Stripe 개발자 블로그(2026-02-09)와 InfoQ(2026-03)에 따르면 사람이 쓴 코드 없이 사람이 리뷰하는 PR이 주 1,300건 이상 머지된다. LLM 노드와 결정적 노드(테스트, CI 정책)를 섞는 "blueprint" 구조이고, CI 라운드는 최대 2회로 제한한다.
- 🆕 **Cursor** [자기 보고·2차]: 자사 머지 PR 중 클라우드 에이전트가 만든 비중이 2025년 12월 10분의 1에서 2026년 10월 56%로 올랐다고 밝혔다.
- 🆕 **Radar Vol.35**: Risk-tiered human oversight Trial, Agent pipeline responsibility Assess(에이전트도 그린 빌드에 책임), Human-in-the-loop theater Caution.
- **감독 제어 관점** 🆕 Martin Fowler "Fragments: October 28" [의견]: Annie Vella의 "직접 제어에서 감독 제어(supervisory control)로" 프레임을 Endsley-Kiris 자동화 단계 모델과 함께 소개한다. "loop engineering"이라는 용어는 정의된 1차 용례를 찾지 못했다. 확립된 용어라기보다 "SDLC를 우리가 짓고 감독하는 제어 시스템으로 보라"는 관점에 가깝다.
- **해석**: 도구 경쟁의 축이 코드 생성에서 병렬 실행·리뷰·머지 자동화로 옮겨 갔다. "다른 계열 모델로 리뷰한다"는 실무 원칙이 제품 기능이 됐지만, 이종 모델 리뷰어들의 오류가 실제로 독립적인지는 독립적으로 측정한 자료가 없다.

### 3.5 대화와 조직 기억

- **Grilling** 🆕 Radar Trial: 에이전트가 계획 전에 사람을 인터뷰해 모호성을 해소한다. Radar는 이것이 codebase cognitive debt 대응에도 도움이 된다고 쓴다.
- **공개 세션으로서의 에이전트: Shopify River** [자기 보고]
  - River는 회사 Slack의 공개 채널에서만 일하는 에이전트로, Shopify 전체 머지 PR의 약 8건 중 1건을 공동 작성한다.
  - CEO Tobi Lütke는 위험은 AI가 일을 한다는 것이 아니라 우리가 거기서 배우지 못한다는 것이며, 에이전트와의 상호작용이 모두 비공개 창에서 일어나면 키보드 앞의 한 사람만 배운다고 썼다.
  - 🆕 Lütke는 10월 19일 River가 2026년 9월에 121,804개 스레드를 처리했다고 밝혔다(3월 35,418개) [2차].
  - Shopify는 AI가 작성한 코드 줄 수나 PR 수를 성공 지표로 쓰지 않는다고 밝혔다 [2차].
- 🆕 **Radar**: Feedback flywheel Trial(세션마다 공유 산출물을 갱신하되 제거도 함께), Self-improving harness Trial(에이전트가 하네스 개선을 제안하고 사람이 경계를 설정).
- 🆕 **Kiro Memory**: 저장소 관례, 교정 사항, 이미 배제한 접근법을 세션 간에 이어 간다. 잘못된 교정이 누적될 위험이 있으므로 read-only로 시작하는 것을 권한다(추론).

### 3.6 사람: 신뢰·역량·정체성

- 🆕 Stack Overflow 2026: 초기 경력자의 중요 결정 신뢰는 4%이고, 업무에서 AI를 피하는 이유로 기술 상실 우려를 든 응답은 17.1%다.
- 🆕 Fowler "Fragments: October 28"은 Karpathy의 말을 인용한다. 다수의 전문가는 여전히 완만한 향상만 보고, 소수만 곡선이 수직으로 꺾이는 현기증을 겪는다. 또 1~2주짜리 agentic engineering 몰입 교육에서 가장 큰 영향은 기술이 아니라 정체성에 관한 정서적 충격이었다고 전한다 [의견·일화].
- 🆕 Laycock: 숙련 개발자가 신중한 이유를 변화 거부가 아니라 운영 신뢰의 부재로 다시 해석한다.
- 🆕 Radar: Agent skill cognitive surrender Caution(이해 없이 대형 skill 라이브러리나 프레임워크를 도입하는 것).
- 새 RCT는 확인하지 못했다. Anthropic 2026년 1월 RCT의 후속 연구도 미확인이다.

### 3.7 Java/Spring 관점

- **보안**: Java 31%(Veracode Fall 2026). 9월판의 Java 보안 경고는 그대로 유지된다. 스펙 단계에서 보안 요구를 주입하는 방식(Kiro "Spec it safe" 등)의 가성비가 높다.
- **외부 계약이 먼저 실패했다**: Jain 실험은 Java 서비스였고, 실패는 대부분 HTTP 상태 코드·Kafka 메시지 형식·환경변수 같은 계약 경계에서 났다(n=1). 9월판은 Spring의 런타임 마법을 주된 위험 지점으로 꼽았는데, 적어도 이 사례에서는 외부 계약이 먼저 터졌다.
- **Spring AI** [공식]: 2.1.0-M1(2026-09-25, Spring Boot 4.2 추적), 🆕 2.1.0-RC1(2026-10-23). MCP 2026-07-28 지원은 진행 중이며, Spring 팀은 MCP Java SDK 2.0이 아직 이를 지원하지 않는다고 밝혔다(2026-09-15 이슈). Boot 3.x 프로젝트에서 stateless MCP 서버를 Spring AI 공식 경로로 쓰기는 당분간 어렵다.
- **JetBrains**: Junie GA(2026-06-17), JetBrains Air 발표(2026-09). 방법론 차원의 신규 증거는 없다.
- **컴파일 타임 DI(Micronaut·Quarkus·Spring AOT) 재평가, Java 정적 타입의 새 증거**: 9월 이후 신규 자료를 찾지 못했다.

### 3.8 도구 지형 요약 (9월 이후)

| 도구 | 9월 이후 주요 변화 | 방법론적 의미 |
|---|---|---|
| Kiro | Workflows, CLI V3, Memory, Markdown Review, 샌드박싱, Spec it safe | 스펙 리뷰 비용 절감, 세션 간 학습, 스펙 단계 보안 |
| GitHub Copilot | 코드 리뷰 Max(이종 모델 다중 리뷰), Agent Merge, Projects, Enterprise 번들 | 리뷰·머지의 제품화 |
| Cursor | 클라우드 에이전트 캔버스, Environments API, 자사 PR의 56% | 병렬·원격 실행의 일상화 |
| Claude Code | 명령형 훅의 차단 규칙 수정(2.1.294), 서브에이전트 작업 강도 조절·마켓플레이스 플러그인 설치(2.1.292) [2차] | 점진적 |
| Codex | CLI 기본 모델 GPT-6.1 Sol(0.161.0, 10-07) | 점진적 |

---

## 4장. 9월 이후 타임라인

| 날짜 | 사건 | 유형 | 9월 결론에 대한 영향 |
|---|---|---|---|
| 09-22 | Claude Opus 5.5, GPT-6 Sol/Luna 출시(9월판 직전) | 벤더 | 중립: 모델 등급 분화가 하네스 비용 논쟁의 전제가 됨 |
| 09-30 | 🆕 Kiro Workflows | 벤더 | 강화: 다단계 절차의 코드화 |
| 10-06경 | 🆕 Stack Overflow 2026 결과 | 관찰 | 강화: 신뢰는 검증 가능성에 조건부 |
| 10-06~16 | 🆕 Cursor 원격 제어, Origin 마켓플레이스, 클라우드 에이전트 업데이트 | 벤더 | 중립: 병렬 실행의 일상화 |
| 10-09 | 🆕 Kiro CLI V3 기본화, Memory | 벤더 | 보강: 세션 간 학습, 단 오염 위험 |
| 10-09 | 🆕 arXiv 2610.12822(멀티에이전트 reward hacking 전파) | 학술(프리프린트) | 강화: 사람 소유 오라클 필요 |
| 10-13 | 🆕 Naresh Jain "Are Harnesses Worth the Cost?" | 실험 | **수정**: 센서 빈도를 모델 능력에 맞춤 |
| 10-14~21 | 🆕 Kiro 샌드박싱, 워크스페이스 신뢰, Markdown Review | 벤더 | 강화: 안전 기본값, 스펙 리뷰 비용 절감 |
| 10-19 | 🆕 Lütke, River 9월 스레드 121,804건 | 자기 보고 | 보강: 공개 세션 학습의 규모 |
| 10-22 | 🆕 Spec Kit 1.2.3, AAIF 10개 프로젝트 | 벤더·공식 | 중립 |
| 10-23 | 🆕 Spring AI 2.1.0-RC1 | 공식 | 중립 |
| 10-26 | 🆕 Kiro Crew "software factory stability" | 자기 보고 | 강화: 계층화 리뷰, 단일 readiness 게이트 |
| 10-28 | 🆕 GitHub Universe(코드 리뷰 Max, Agent Merge) | 벤더 | 강화: 리뷰 다중화의 제품화 |
| 10-28 | 🆕 Fowler "Fragments: October 28"(Karpathy, Vella) | 의견 | 강화: 감독 제어 관점 |
| 10-29 | 🆕 Veracode Fall 2026(62%, Java 31%) | 벤더 | **수정**: 보안 개선 조짐, Java 정체 |
| 10-29 | 🆕 Laycock "good devs wary" | 자기 보고·의견 | 강화: 안정성 문제 |
| 10-30 | 🆕 Kiro "Spec it safe" | 벤더 | 부분 진전: 스펙 단계 보안 검증 |
| 11-04 | 🆕 Thoughtworks Radar Vol.35 | 의견 | **강화**: 하네스 대주제, 뮤테이션 테스트 Adopt, 문서 비대화 Caution |

9월 이전이지만 9월판에서 빠졌던 자료: Sonar State of Code 2026(01-08), Faros AI Engineering Report 2026(04-12), Böckeler 센서 연작(05-27, 07-06), Shopify "Under the River"(05-28), Kiro Analyze Requirements·Bugfix Spec(8월 문서 기준).

---

## 5장. 열린 질문

### 5.1 9월판 질문의 진전

| 질문 | 진전 | 근거 |
|---|---|---|
| (1) 스펙의 "단위 테스트"(모호성·모순 검증) | 부분 진전 | Kiro Analyze Requirements(LLM 기반 모순·모호성·공백 탐지), Kiro "Spec it safe"(결정적 엔진, 보안 한정), Grilling(대화로 해소). 결정적인 범용 검출기는 없음 |
| (2) TDD의 인지적 가치를 명세 단계로("Spec-TDD") | 부분 진전(실험 1건) | Jain 실험의 계약 + 예시 + 외부 수용 테스트 = 실행 가능한 명세가 곧 오라클 |
| (3) 에이전트 리뷰어를 어느 위험 등급까지 신뢰하나 | 실무 진전, 독립 증거 없음 | Radar Risk-tiered oversight, Kiro Crew의 단순 등급 자동 머지, GitHub 리뷰 깊이 3단계. 리뷰어 정확도를 독립 측정한 자료 없음 |
| (4) Spring 런타임 마법은 부채인가 / 컴파일 타임 DI 재평가 | 변화 없음 | 신규 증거 없음. 다만 Jain 사례에서는 외부 계약이 먼저 실패 |
| (5) 검증 역량 형성과 조직 학습 | 설계 사례 등장, 실증 없음 | Shopify River(공개 세션), Grilling, cognitive surrender 경고. 새 RCT 없음 |
| 스펙-코드 드리프트의 결정적 탐지 | 부분 진전 | OpenSpec delta+archive, Spec Kit converge 단계, Kiro Crew의 PR 설명-코드 일치 CI 검사. 표준 도구 없음. 이 저장소의 [에이전트 코드 리뷰 단계 제안](2026-11-agent-code-review-stage.md)에 AC → design Property → 테스트 표시 → 실행 결과를 대조하는 `spec-trace.mjs` 초안이 있음(사내 검증 전) |
| 비결정성과 재현 가능 빌드 | 미미 | Kiro "Lean으로 하네스 성질 증명"(11-02, 본문 미확인) |
| 책임 소재·규제 요건 | 개념 진전 | "accountability sink" 경고, Agent pipeline responsibility, Kiro Crew의 "우리가 책임지는 것은 review record" |

### 5.2 새로 생긴 질문

1. **맡기는 단위와 리뷰 가능한 단위의 긴장.** 맡기는 단위를 키우면 변경도 커져서 사람이 집중해서 리뷰할 수 있는 한계와 충돌한다. 맡기는 단위는 키우되 증명은 기계가 판정할 수 있는 작은 단위로 쪼개는 것이 답인가?
2. **이종 모델 리뷰어의 오류는 정말 독립적인가?** "다른 계열은 맹점을 공유하지 않는다"는 가정을 측정한 자료가 없다. 비슷한 학습 데이터와 관행에서 오는 상관 오류는 남을 수 있다.
3. **서브에이전트 구성은 reward hacking을 전파하는가?** 오케스트레이터-서브에이전트 구조에서 한 에이전트의 우회 전략이 다른 에이전트의 '정상' 기준이 될 위험을 어떻게 차단하나? 분리 기준 자체는 [서브에이전트는 언제 나누는가](2026-11-subagent-boundaries.md)에서 다뤘지만, 전파 위험은 아직 그 기준에 들어 있지 않다.
4. **공개 세션 학습은 폐쇄망·규제 환경에서 어떻게 가능한가?** River식 학습 구조를 보안 제약이 강한 조직으로 옮기는 방법은 무엇인가?
5. **지시문의 progression testing은 어떻게 하나?** 모델이 바뀔 때 어떤 steering·rule을 지워도 되는지 판단하는 실험 설계가 필요하다.
6. **의도를 두는 장소의 배합은 무엇으로 평가하나?** 같은 기능을 문서 중심 / 계약·속성 중심으로 만들었을 때의 리뷰 시간, 재작업, 결함을 비교한 자료가 없다.

---

## 6장. 실천 권고 (개정)

9월판의 단계식 권고(하네스 먼저 → Spec-lite → 인간 소유 오라클 → …)를 특정 방법론에 묶이지 않는 원칙으로 다시 정리한다. 효과는 대부분 미입증이며 실무 관찰과 추론에 기반한다.

### 원칙 1. 성공의 정의부터 바꾼다

- CI에 단일 readiness 판정을 둔다. 판정은 "실패 없음"이 아니라 "기대한 검사 목록이 모두 실행되었고 모두 통과"여야 한다. 예: Surefire·Failsafe 리포트의 테스트 수가 0보다 크고 직전보다 줄지 않았는지, ArchUnit·SpotBugs·PIT 레인이 실제로 실행되었는지.
- 에이전트의 텍스트 보고("완료했습니다")가 아니라 기계가 읽을 수 있는 산출물(리포트 파일)을 근거로 완료를 판정한다. 서브에이전트가 성공을 잘못 보고하는 문제에 대한 직접적인 대응이다.
- 구현 예: [에이전트 코드 리뷰 단계 제안](2026-11-agent-code-review-stage.md)의 `spec-trace.mjs`는 AC에 연결된 테스트 중 하나라도 미실행·건너뜀이면 '통과'가 아니라 '일부 미실행'으로 내고, 파서가 멈춰도 결과 파일을 남긴다.

### 원칙 2. 오라클은 사람이 소유하고, 에이전트는 고칠 수도 볼 수도 없게

- 수용·계약 테스트 디렉터리에 CODEOWNERS를 걸고, 에이전트 PR의 테스트 수정·삭제·`@Disabled`를 CI에서 탐지해 별도 승인을 요구한다.
- 가능하면 에이전트가 볼 수 없는 held-out 수용 테스트 세트를 둔다. 금지 지시문만으로는 우회가 거의 줄지 않는다(BaitBench −6.2%p).
- 리뷰 규칙과 프롬프트는 PR이 수정할 수 없는 위치에서 로드한다.

### 원칙 3. 의도는 기계가 가장 잘 검증할 수 있는 곳에 둔다

- 우선순위: 실행 가능한 계약·속성 > 코드 구조 규칙 > 문서.
- 외부 계약(HTTP 상태, 메시지 스키마, 설정 키)은 OpenAPI·AsyncAPI·계약 테스트로 고정한다. 배치의 불변식은 속성 기반 테스트(jqwik 등)로 고정한다.
- 문서는 근거, 비목표, 거부된 대안처럼 기계가 표현하지 못하는 것에 한정한다. 작은 버그에는 문서를 쓰지 않는다.

### 원칙 4. 독립 검증 게이트는 항상, 센서 빈도는 모델에 맞춘다

- 정형화된 작업(CRUD, 배치 Reader/Writer 보일러플레이트)은 저가 모델 + 촘촘한 센서, 모호한 설계 작업은 프런티어 모델 + 최종 게이트 조합을 비교 측정해 본다. Radar도 "Blanket frontier model usage"를 Caution으로 분류했다.

### 원칙 5. 지시문은 덜고 결정적 검사로 옮긴다

- 변환 가능한 지시는 hook, 아키텍처 테스트, 린터 규칙으로 바꾼다.
- 모델을 바꿀 때마다 steering·rule·AGENTS.md를 재평가해 지운다(progression testing). 메모리 기능은 read-only로 시작한다.

### 원칙 6. 리뷰는 위험 등급별로, 판정 기준은 엄격하게

- blocking의 정의(위치, 인용 증거, 트리거, 결과)를 정하고 nit은 후속 이슈로 돌린다.
- 가능하면 구현 모델과 다른 계열의 모델로 리뷰한다. 다른 모델의 가치는 성능이 아니라 틀리는 지점이 다르다는 데 있다. 단, 이종 모델 리뷰의 독립성은 검증된 사실이 아니며, 모델에 따라 과잉 지적으로 리뷰 피로를 키울 수도 있다. 같은 모델을 쓸 때는 판단을 diff·테스트 결과 같은 증거에 묶어 자기 선호 편향을 줄인다([에이전트 코드 리뷰 단계 제안](2026-11-agent-code-review-stage.md) 6장).
- 위험 등급을 나눈다. 예: 배치 Job 설정·트랜잭션 경계는 사람이 직접, 일반 서비스 로직은 사람 리뷰, 테스트·문서·의존성 패치 일부는 자동.
- 사람이 평가할 수 없는 diff에 대한 형식적 승인이 되지 않도록 리뷰 용량을 먼저 산정한다(HITL theater 경계).

### 원칙 7. 맡기는 단위는 판정할 수 있는 만큼만 키운다

- "이 기능을 구현해"(작업 단위)보다 "Job X는 재시작해도 중복·누락이 없어야 한다"(결과 단위)로 맡기되, 그 결과를 판정할 수단(속성, 수용 테스트)을 먼저 고정한다. 결과 단위로 맡긴 사례는 결과를 외부에서 싸게 확인할 환경을 먼저 갖췄다. 예를 들어 Felix Rieseberg(2026-10-13)는 "앱을 크래시 없이 유지하라"고 맡기기 전에 크래시 리포트 접근, 앱 버전과 커밋 매핑, 세 OS에서의 재현 환경을 만들었다 [의견].
- 판정할 수 없으면 사람은 과정을 통제하게 된다. 에이전트에게 방법을 일일이 지시하고 있다면 판정 수단이 없다는 신호로 본다. 방법 지시는 기능마다 반복되는 비용이고, 판정 수단은 한 번 만들면 계속 쓰인다.
- 도메인 지식이 부족하고 비교할 기존 시스템도 없어 판정 수단 자체가 약하다면, 잠정 결정을 확정과 구분해 드러내고 확인할 사람을 함께 남긴다.

### 원칙 8. 학습을 공유 산출물로 남긴다

- 에이전트 세션에서 얻은 교훈은 개인 대화에 두지 말고 테스트, 아키텍처 규칙, 문서 같은 공유 산출물로 승격한다.
- 주니어에게는 계획 단계에서 에이전트가 grilling하게 하고, 답하지 못한 질문을 학습 과제로 삼는다. 일부 작업은 AI 없이 구현·디버깅하게 하는 9월판 권고는 유지한다.

### 측정 지표

9월판 지표(리드타임, 변경 실패율, 리뷰 대기 시간, 재작업률)에 더해:

- 뮤테이션 점수(변경 패키지 기준)
- 에이전트 PR 중 테스트 파일 변경 비율
- readiness 판정의 "미실행 레인" 발생 수
- 위험 등급별 리뷰 소요 시간
- 메인 빌드 red 비율과 지속 시간
- 스펙 문서 수와 마지막 수정 이후 경과일(비대화 지표)
- 승인된 변경 1건당 토큰·크레딧

### 개인 실험 템플릿 (Jain 실험의 축소판)

- **질문 하나**: 예) "이 유형의 feature에서 문서 중심 스펙과 계약·속성 중심 스펙 중 무엇이 리뷰 시간과 재작업을 줄이나?"
- **조건**: 바꾸는 변수는 하나만(스펙의 무게, 하네스 유무, 모델 등급 중 하나)
- **반복**: 같은 과제를 조건별로 여러 번(비결정성 때문에 1회 비교는 의미가 약하다)
- **판정**: 에이전트가 보지 못한 외부 수용 테스트
- **기록**: 통과율, 토큰·시간, 사람 개입 횟수, 리뷰 시간, 이후 재작업

### 폐쇄망 환경 적용 메모 (외부 GitHub 체크아웃·PyPI 불가, npm 미러 가능)

- Spec Kit 공식 설치 경로(uv + GitHub git)는 사용할 수 없다.
- Kiro "Spec it safe" 엔진은 Node CLI라 npm 경로와 맞지만 소스(aws-samples)를 승인된 경로로 반입해야 하고, 도입 전에 내용을 검토한다(cognitive surrender 경계).
- PIT·jqwik·ArchUnit·Testcontainers는 사내 Maven 프록시가 있으면 그대로 쓸 수 있다.
- Kiro Analyze Requirements·Bugfix Spec은 사내 Kiro 버전에서 제공되는지 확인한다.

---

## 7장. 한계

- 실증 데이터의 상당수가 벤더 연구(Faros, Veracode, Sonar)이거나 이해관계자의 자기 보고(Kiro Crew, Stripe, Shopify, Cursor)다. 효과 크기는 할인해서 본다.
- Radar는 Thoughtworks 고객 경험에 기반한 의견이며 통계적 증거가 아니다.
- Jain 실험은 Java 서비스 1개 × 모델 2종 × 10회이고, 저자는 하네스 도구 개발사의 창업자다.
- reward hacking 연구 대부분은 동료 심사 전 arXiv 프리프린트다.
- GitHub Universe, Cursor, Claude Code·Codex 변경 사항 일부와 Shopify 지표 일부는 2차 자료로만 확인했다.
- martinfowler.com을 직접 열람하지 못해 Böckeler의 9월 이후 글은 확인하지 못했다(없다는 뜻이 아니다).
- DORA 2026 연례 보고서는 확인하지 못했다. 확인된 것은 ROI 보고서(v2026.1)다.
- "Architecture as Capability Equalizer" 논문은 이번에도 찾지 못했다.

---

## 참고 자료

**이전판**
- [AI Agent 시대의 소프트웨어 개발방법론: 2026년 9월 현황과 전망](https://github.com/libedi/docs/blob/main/ai-development/2026-09-ai-agent-era-dev-methodology.md)

**업계 평가·의견**
- Thoughtworks, [Technology Radar Vol.35](https://www.thoughtworks.com/radar) (2026-11-04) · [Techniques](https://www.thoughtworks.com/radar/techniques) · [OpenSpec](https://www.thoughtworks.com/radar/tools/openspec)
- Naresh Jain, [Are Harnesses Worth the Cost?](https://martinfowler.com/articles/are-harnesses-worth-the-cost.html) (2026-10-13)
- API Evangelist, [The Harness That Works Is A Contract](https://apievangelist.com/2026/10/19/the-harness-that-works-is-a-contract/) (2026-10-19)
- Birgitta Böckeler, [Maintainability sensors for coding agents](https://martinfowler.com/articles/sensors-for-coding-agents.html) (2026-05-27, 2026-07-06 보강)
- Martin Fowler, "Fragments: October 28" (2026-10-28)
- Rachel Laycock, "Why are good developers so wary of agentic development?" (2026-10-29)
- Felix Rieseberg, [How to be more ambitious: A tutorial for humans with models](https://felixrieseberg.com/how-to-be-more-ambitious-a-tutorial-for-humans-with-models/) (2026-10-13)

**실증·보고서**
- Faros AI, [Ten takeaways from the AI Engineering Report 2026: The Acceleration Whiplash](https://faros.ai/blog/ai-acceleration-whiplash-takeaways) (2026-04-12)
- Sonar, [State of Code Developer Survey 보도자료](https://www.sonarsource.com/company/press-releases/sonar-data-reveals-critical-verification-gap-in-ai-coding/) (2026-01-08)
- Veracode GenAI Code Security Fall 2026 ([보도](https://finance.yahoo.com/technology/ai/articles/veracode-finds-first-meaningful-gain-132700286.html), 2026-10-29)
- Stack Overflow, [Developer Survey 2026 – AI](https://survey.stackoverflow.co/2026/ai) · [보도자료](https://stackoverflow.co/company/press/archive/stack-overflow-annual-developer-survey-ai-trust-conditional)
- METR, "We are Changing our Developer Productivity Experiment Design" (2026-02-24)
- DORA, [ROI of AI-assisted Software Development](https://dora.dev/ai/roi/report) · [DORA 2025: Year in review](https://dora.dev/insights/dora-2025-year-in-review/)

**학술**
- [SpecBench (arXiv 2605.21384)](https://arxiv.org/html/2605.21384v1)
- [BaitBench (arXiv 2608.30724)](https://arxiv.org/html/2608.30724v1)
- [Reward Hacking as a Transmissible Strategy in Multi-Agent Coding Systems (arXiv 2610.12822)](https://arxiv.org/abs/2610.12822)

**기업 사례**
- Kiro, [Keeping a software factory stable at 1,000 PRs a week](https://kiro.dev/blog/software-factory-stability/) (2026-10-26)
- Shopify Engineering, [Under the River](https://shopify.engineering/under-the-river) (2026-05-28) · Tobi Lütke, [Learning on the Shop floor](https://www.shopify.com/careers/candidate-guide/shop-floor)
- [River 스레드 수 보도 (Dealroom)](https://dealroom.co/news/163841-river-threads-jump-to-121-804-as-shopifys-ai-agent-floods-its-slack/) · [Inside the Software Factory: Shopify (Port)](https://software-factories.port.io/shopify)
- InfoQ, [Stripe autonomous coding agents](https://infoq.com/news/2026/03/stripe-autonomous-coding-agents/) (2026-03)
- [Cursor 클라우드 에이전트 56% 보도 (Tech Insider)](https://tech-insider.org/cursor-ai-agents-56-percent-merged-prs-2026/)

**도구·표준**
- Kiro, [Specs 문서](https://kiro.dev/docs/specs/) · [블로그](https://kiro.dev/blog/) · [CLI changelog](https://kiro.dev/changelog/cli/)
- AWS, [Spec it safe](https://aws.amazon.com/jp/blogs/news/spec-it-safe/) · [sample-kiro-spec-security-hardening](https://github.com/aws-samples/sample-kiro-spec-security-hardening)
- [GitHub Spec Kit](https://github.com/github/spec-kit)
- [Copilot code review Max 보도 (Data Studios)](https://www.datastudios.org/post/github-copilot-code-review-max-multi-agent-reviews-approvals-generally-available) · [Copilot app Universe 업데이트 (SmartScope)](https://smartscope.blog/blog/github-copilot-app-updates-universe-projects-agent-merge-2026/) · [GitHub Japan 보도자료](https://digitalpr.jp/pdf.php?r=147105) (2026-10-29)
- [Claude Code October 2026 releases (Havoptic)](https://www.havoptic.com/releases/claude-code/2026/10) · [Codex CLI 0.161.0 (SessionWatcher)](https://sessionwatcher.com/news/codex-cli-0-161-0-gpt-6-1-sol-default-model)
- Spring, [Spring AI 2.1.0-M1](https://spring.io/blog/2026/09/25/spring-ai-2-1-0-M1-available-now/) · [Spring AI releases](https://github.com/spring-projects/spring-ai/releases) · [Issue #6954](https://github.com/spring-projects/spring-ai/issues/6954)
- [MCP 사양 버전 타임라인 (2차)](https://hidekazu-konishi.com/entry/mcp_specification_version_timeline.html)
- [Junie 블로그](https://junie.jetbrains.com/blog)

## 변경 이력

- 2026-11-05: 초판. 9월판의 결론을 재평가하고, SDD 중심 서술을 '의도를 어디에 두는가' 프레임으로 바꿨습니다. 9월판에서 빠졌던 자료(Sonar, Faros, Shopify River, Böckeler 센서 연작, Kiro Analyze Requirements·Bugfix Spec)를 보강하고 MCP 사양 버전을 정정했습니다.
- 2026-11-06: 1장의 1.4절(위임 고도)을 삭제하고 그 결론을 6장 원칙 7로 옮겼습니다. 1장의 주제(의도를 어디에 두는가)와 다른 축이기 때문입니다. 원칙 7에 "방법 지시는 판정 수단이 없다는 신호"라는 관점을 더하고, 타임라인의 Rieseberg 항목과 Goals Gone Wild 참고를 지웠습니다. 문서 전체에서 "거처"라는 표현을 "장소"(제목·표)와 "곳"(본문)으로 바꿨습니다.
