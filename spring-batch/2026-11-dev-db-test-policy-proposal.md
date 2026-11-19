# 개발 Oracle DB 통합·Smoke 테스트의 빌드 및 JaCoCo 격리 제안

- 작성일: 2026-11-19
- 상태: 제안 (프로젝트별 적용 및 검증 필요)
- 대상: Java 25 / Spring Boot 4 / Spring Batch / MyBatis / Oracle 기반 Gradle Kotlin DSL 멀티모듈 프로젝트

## TL;DR

기존 H2 기반 테스트는 항상 실행하고 실패 시 빌드에 반영한다. 실제 개발 Oracle DB를 사용하는 테스트는 JUnit 5의 `@Tag("dev-db")`로 분리해 별도 Gradle `devDbTest` 태스크로 실행한다. 초기 도입 단계에서는 `devDbTest` 실패를 빌드 결과에 반영하지 않고(`ignoreFailures`), JaCoCo 계측도 비활성화한다. 향후 DB 미접속으로 인한 **환경적 미실행**과 SQL/Assertion **실제 결함**을 구분하는 정책으로 발전시킨다.

**핵심 원칙:** 테스트 실행 여부, 테스트 결과, Gradle 빌드 실패 판정, JaCoCo 수집은 별개의 정책이다.

## 1. 배경과 요구사항

현재 단위·통합 테스트는 H2 기반으로 수행하며, Gradle `test`와 JaCoCo를 품질 게이트로 사용한다. 실제 Oracle 환경에서만 발견할 수 있는 SQL 문법, DB 객체·권한, MyBatis 매핑, 실행 계획과 DB 설정 차이를 검증하기 위해 개발 DB 기반 통합·Smoke 테스트가 필요하다.

그러나 개발 DB는 네트워크·계정·점검·접속 정책 등 외부 요인으로 사용하지 못할 수 있다. 이러한 상황이 H2 테스트의 빌드 성공을 방해해서는 안 된다.

| 요구사항 | 정책 |
| --- | --- |
| H2 테스트 | 기존 `test`에서 항상 실행, 실패 시 Build Fail |
| 개발 DB 테스트 | `devDbTest`에서 별도 실행, 초기에는 opt-in |
| 개발 DB 테스트 실패 | 초기에는 리포트에 남기되 빌드 실패로 전파하지 않음 |
| JaCoCo | 개발 DB 테스트 실행의 계측 데이터를 수집하지 않음 |
| 운영 전환 | 필요 시 속성으로 실패 허용을 끄고 강제 검증 가능 |
| 안전성 | 개발 DB에서 기본은 읽기 전용, 비밀정보를 소스에 저장하지 않음 |

## 2. 테스트 분류

| 유형 | DB | 예시 | 기본 실행 | 실패 정책 | 커버리지 |
| --- | --- | --- | --- | --- | --- |
| Unit / H2 Integration | H2 | 서비스 로직, Mapper 테스트 | `test` | 필수 게이트 | JaCoCo 포함 |
| Dev DB Integration | Oracle 개발 DB | Oracle SQL·매핑·스키마 검증 | `devDbTest` 명시 실행 | 초기 비차단 | JaCoCo 제외 |
| Dev DB Smoke | Oracle 개발 DB | 주요 조회 경로·연결 상태 확인 | `devDbTest` 내 태그 추가 가능 | 초기 비차단 | JaCoCo 제외 |

`@Tag("dev-db")`는 외부 환경 의존성을, `@Tag("smoke")`는 검증 목적을 나타낸다. 두 태그는 필요하면 함께 사용할 수 있다. **통합테스트라고 모두 비차단 테스트가 되는 것은 아니다.** H2 통합테스트는 기존 빌드 게이트에 남긴다.

## 3. Gradle Kotlin DSL 예시

다음은 **모듈별 `build.gradle.kts`**에 적용하는 최소 구성이다. JaCoCo 플러그인과 Java 플러그인, JUnit Platform 설정 및 테스트 의존성은 이미 적용되어 있다고 가정한다.

```kotlin
import org.gradle.api.tasks.testing.Test
import org.gradle.testing.jacoco.plugins.JacocoTaskExtension

tasks.named<Test>("test") {
    useJUnitPlatform {
        excludeTags("dev-db")
    }
}

val devDbTest by tasks.registering(Test::class) {
    description = "Runs integration/smoke tests against development Oracle DB"
    group = "verification"

    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath

    useJUnitPlatform {
        includeTags("dev-db")
    }

    // 기본은 비차단. 필요 시 -PdevDbTest.ignoreFailures=false 로 강제한다.
    ignoreFailures = providers.gradleProperty("devDbTest.ignoreFailures")
        .map(String::toBoolean)
        .getOrElse(true)

    // JaCoCo 플러그인이 적용되어 있다는 전제
    extensions.configure<JacocoTaskExtension> {
        isEnabled = false
    }

    shouldRunAfter(tasks.named("test"))
}
```

- `devDbTest`는 `check` 또는 `build`에 자동 연결하지 않는다. 개발 DB 접속 제한으로 인해 기본 품질 게이트가 불안정해지는 것을 막기 위해서다.
- `shouldRunAfter`는 두 태스크가 모두 선택되었을 때 실행 순서를 지정할 뿐, 의존성을 만들지 않는다.
- `ignoreFailures`는 **접속 오류뿐 아니라 Assertion·SQL 실패까지 모두 무시**한다. 도입 초기 편의 정책이지 결함 분류 방법은 아니다.
- `Test` 태스크가 새로 만들어져도 기본 `jacocoTestReport`는 일반적으로 `test`의 데이터만 사용한다. 프로젝트에서 커스텀 집계 또는 `*.exec` 글롭을 사용한다면 별도로 확인한다.
- Java 소스셋·JaCoCo 설정을 공통 convention plugin에서 관리한다면 위 설정도 같은 플러그인에 옮기는 것을 검토한다. 모든 모듈에 무조건 등록하는 대신 개발 DB 대상 모듈에만 적용할 수 있다.

### JUnit 5 예시

```java
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

@Tag("dev-db")
@Tag("smoke")
@SpringBootTest
@ActiveProfiles("dev-db")
class OracleMemberMapperSmokeTest {

    @Test
    void canReadKnownReferenceData() {
        // 개발 DB에 실제로 존재하는 안정적인 기준 데이터를 조회한다.
        // 결과는 DB 상태에 따라 달라지지 않는 조건으로 검증한다.
    }
}
```

`@ActiveProfiles("dev-db")`는 그 프로필을 선택할 뿐, 환경변수 공급·보안·DB 연결을 자동 해결하지 않는다. Spring Context 생성 전에 연결이 실패할 경우 `@BeforeAll`의 JUnit Assumption만으로는 안전하게 중단 처리할 수 없다는 점에 주의한다.

## 4. 실행 명령과 판정

```bash
# 기본 품질 게이트: H2 테스트 및 기존 JaCoCo
./gradlew test jacocoTestReport

# 개발 DB 검증: 실패를 기록하지만 Gradle 태스크는 비차단
./gradlew devDbTest

# 두 테스트 실행: 개발 DB 테스트는 별도 비차단 정책
./gradlew test devDbTest

# 개발 DB 테스트의 실제 실패를 빌드 실패로 처리해야 할 때
./gradlew devDbTest -PdevDbTest.ignoreFailures=false
```

멀티모듈에서는 `./gradlew :batch-domains:batch-member:batch-member-app:devDbTest`와 같이 실제 대상 모듈 경로를 지정한다(예시이며 프로젝트 구조에 맞게 조정). 실패 상세는 해당 모듈의 `build/reports/tests/devDbTest/`에서 확인한다.

## 5. JaCoCo 제외 정책과 확인 사항

1. `devDbTest`에서 `JacocoTaskExtension.isEnabled = false`로 계측을 비활성화한다.
2. 기존 `test` 태스크에서는 계측을 계속 유지한다.
3. `jacocoTestReport`의 `executionData`가 `test`에서 생성한 데이터만 집계하는지 검증한다.
4. 커스텀 통합 리포트나 루트 프로젝트의 `fileTree("build") { include("**/*.exec") }` 등이 있으면 `devDbTest` 산출물이 합쳐지지 않도록 조정한다.
5. 과거 실행에서 남은 `devDbTest.exec` 같은 잔여 파일이 집계되지 않는지 `clean` 후 확인한다.

**주의:** JaCoCo의 `classDirectories.exclude`로 테스트 클래스를 제외하는 방식은 목적에 맞지 않는다. 여기서 제외하려는 것은 *테스트 실행으로 인한 커버리지 기여분*이지, 애플리케이션 클래스 자체가 아니다.

## 6. 비차단 처리의 한계와 개선안

초기안의 `ignoreFailures = true`는 다음 상태를 동일하게 빌드 성공으로 처리한다.

| 상황 | 초기안 | 향후 권장안 |
| --- | --- | --- |
| DB 연결 제한·점검 | 테스트 실패로 기록되지만 빌드는 성공 | 환경 미가용으로 Skip/Aborted, 경고 |
| DB 연결 성공·SQL 오류 | 실패 기록, 빌드는 성공 | 실제 테스트 Fail |
| DB 연결 성공·Assertion 실패 | 실패 기록, 빌드는 성공 | 실제 테스트 Fail |
| 테스트 성공 | Pass | Pass |

향후에는 **테스트 시작 전 DB 연결 가능 여부를 독립적으로 확인**하고, 연결할 수 없다면 테스트를 실행하지 않거나 JUnit 조건으로 중단한다. DB에 연결된 뒤 발생한 SQL·Assertion 오류는 실패로 유지한다. 단, 미접속과 오인증·스키마 오류를 모두 무조건 Skip하지 않도록 실패 원인을 구분해야 한다.

강제 검증 단계에서는 `ignoreFailures=false`로 실행하거나 별도 CI Job을 사용한다. 기본 CI의 H2 품질 게이트와 개발 DB 의존 Job은 분리해 상태를 각각 보고하도록 한다.

## 7. 개발 DB 사용 시 안전 수칙

- 가능하면 **조회 전용 계정**과 안정적인 기준 데이터만 이용한다.
- DML 테스트는 전용 스키마·격리된 테스트 데이터·트랜잭션 롤백 및 정리 전략을 별도 설계한다. 단순 `@Transactional`만으로 외부 시스템·다중 DataSource까지 모두 롤백된다고 가정하지 않는다.
- DB 비밀번호와 연결 문자열의 민감 항목은 환경변수 또는 외부 시크릿 관리로 전달하고 Git에 커밋하지 않는다.
- 개발 DB 데이터 변동으로 깨지는 특정 ID·건수 단정은 최소화한다.
- 네트워크 접속 가능 여부, DB 인증, SQL 유효성, 데이터 검증을 가능한 한 서로 구분해 보고한다.
- 폐쇄망 VDI에서 실행할 수 있는 모듈과 네트워크 경로를 먼저 확인한다.

## 8. 도입·검증 체크리스트

- [ ] 기존 H2 테스트가 `test`에서 계속 실행되고 실패 시 Build Fail인지 확인
- [ ] `dev-db` 태그가 기본 `test`에서 제외되는지 확인
- [ ] `devDbTest` 명시 실행에서 Oracle 프로필이 적용되는지 확인
- [ ] 개발 DB 접속 차단 시 `ignoreFailures=true`로 빌드가 성공하고 오류 리포트가 남는지 확인
- [ ] `-PdevDbTest.ignoreFailures=false`에서 같은 오류가 Build Fail로 처리되는지 확인
- [ ] `devDbTest` 실행 시 JaCoCo 에이전트가 비활성화되어 `test`의 커버리지에 섞이지 않는지 확인
- [ ] 루트/모듈 공통 JaCoCo 집계 및 검증 태스크의 추가 설정 확인
- [ ] `build`/`check`가 개발 DB 가용성에 의존하지 않는지 확인
- [ ] DB 연결 실패와 SQL·Assertion 실패를 분리하는 2차 개선의 우선순위 결정

## 9. 제안 결론

**1차:** 동일 `src/test` 소스셋 + JUnit 태그 + 별도 Gradle 태스크 + 초기 비차단 + JaCoCo 수집 제외로 최소 변경을 도입한다.

**2차:** 개발 DB 테스트 규모가 늘어나면 `src/devDbTest` 같은 별도 소스셋 또는 Gradle JVM Test Suite를 고려한다. 연결 불가능 상태는 중단으로, 실제 SQL/Assertion 결함은 실패로 분리한다. 통합/Smoke를 서로 다른 실행 정책으로 관리해야 한다면 태스크도 추가 분리한다.

## 참고 자료

- [Gradle Test 태스크](https://docs.gradle.org/current/dsl/org.gradle.api.tasks.testing.Test.html)
- [Gradle JaCoCo Plugin](https://docs.gradle.org/current/userguide/jacoco_plugin.html)
- [Gradle JVM Test Suite](https://docs.gradle.org/current/userguide/jvm_test_suite_plugin.html)
- [JUnit 5 User Guide — Tagging and Filtering](https://docs.junit.org/current/user-guide/#writing-tests-tagging-and-filtering)
