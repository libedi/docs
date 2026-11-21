# 개발 Oracle DB 통합·Smoke 테스트의 빌드 및 JaCoCo 격리 제안

- 작성일: 2026-11-19
- 상태: 리뷰 반영 제안 (프로젝트별 적용 및 검증 필요)
- 개정일: 2026-11-21 (멀티모듈 Test Fixtures 공통화 추가)
- 대상: Java 25 / Spring Boot 4 / Spring Batch / MyBatis / Oracle 기반 Gradle Kotlin DSL 멀티모듈 프로젝트

## TL;DR

기존 H2 테스트는 기본 `test`에서 항상 실행하여 품질 게이트를 유지한다. 개발 Oracle DB 테스트는 `@DevDbTest`(JUnit `dev-db` 태그·`dev-db` 프로필·실행 조건 결합)와 별도 `devDbTest` Gradle 태스크로 분리하고, **`check`/`build`에 연결하지 않는다.** 이것이 일반 CI 빌드를 개발 DB의 가용성과 분리하는 핵심이다.

명시적으로 `devDbTest`를 실행했을 때는 `ignoreFailures=false`를 기본으로 하여 실제 SQL·Assertion 결함을 빌드 실패로 보고한다. 네트워크 접속 불가나 설정 미비는 사전 `ExecutionCondition`에서 기본적으로 Skip 처리하고, `-PdevDb.required=true`를 지정하면 이를 Fail로 전환한다. 테스트가 0건 발견되면 조건 검사가 실행되지 않으므로, 엄격 모드에서는 JUnit XML 리포트의 건수도 별도로 검증한다. 개발 DB 테스트는 JaCoCo 계측에서 제외해 환경 가용성에 따른 커버리지 변동을 막는다.

**핵심 원칙:** 기본 빌드 보호와 명시적 검증의 실패 판정을 구분한다. `BUILD SUCCESSFUL`은 개발 DB 검증이 실제로 수행되었음을 보장하지 않는다.

## 1. 배경과 요구사항

현재 단위·통합 테스트는 H2 기반으로 수행하며, Gradle `test`와 JaCoCo를 품질 게이트로 사용한다. 실제 Oracle 환경에서만 발견할 수 있는 SQL 문법, DB 객체·권한, MyBatis 매핑, 실행 계획과 DB 설정 차이를 검증하기 위해 개발 DB 기반 통합·Smoke 테스트가 필요하다.

그러나 개발 DB는 네트워크·계정·점검·접속 정책 등 외부 요인으로 사용하지 못할 수 있다. 이러한 상황이 H2 테스트의 빌드 성공을 방해해서는 안 된다.

| 요구사항 | 정책 |
| --- | --- |
| H2 테스트 | 기존 `test`에서 항상 실행, 실패 시 Build Fail |
| 개발 DB 테스트 | `devDbTest`에서 별도 실행, 초기에는 opt-in |
| 개발 DB 테스트 실패 | 연결 불가 시 Skip, 실행된 SQL·Assertion 실패 시 Build Fail |
| JaCoCo | 개발 DB 테스트 실행의 계측 데이터를 수집하지 않음 |
| 강제 검증 전환 | `-PdevDb.required=true`에서 미설정·접속 불가를 Fail 처리하고 JUnit XML 기준 0건도 실패 처리 |
| 안전성 | 개발 DB에서 기본은 읽기 전용, 비밀정보를 소스에 저장하지 않음 |

## 2. 테스트 분류

| 유형 | DB | 예시 | 기본 실행 | 실패 정책 | 커버리지 |
| --- | --- | --- | --- | --- | --- |
| Unit / H2 Integration | H2 | 서비스 로직, Mapper 테스트 | `test` | 필수 게이트 | JaCoCo 포함 |
| Dev DB Integration | Oracle 개발 DB | Oracle SQL·매핑·스키마 검증 | `devDbTest` 명시 실행 | 접속 불가 Skip / 실제 결함 Fail | JaCoCo 제외 |
| Dev DB Smoke | Oracle 개발 DB | 주요 조회 경로·연결 상태 확인 | `devDbTest` 내 태그 추가 가능 | 접속 불가 Skip / 실제 결함 Fail | JaCoCo 제외 |

`@Tag("dev-db")`는 외부 환경 의존성을, `@Tag("smoke")`는 검증 목적을 나타낸다. 두 태그는 필요하면 함께 사용할 수 있다. **통합테스트라고 모두 비차단 테스트가 되는 것은 아니다.** H2 통합테스트는 기존 빌드 게이트에 남긴다.

## 3. Gradle Kotlin DSL 예시

`build.gradle.kts`에 적용하는 최소 구성이다. JaCoCo, Java, JUnit 5 플러그인·의존성이 이미 적용되어 있다고 가정한다. 개발 DB 테스트가 필요한 모듈에만 등록하는 것을 우선 권장한다.

```kotlin
import org.gradle.api.tasks.testing.Test
import org.gradle.testing.jacoco.plugins.JacocoTaskExtension
import org.gradle.api.tasks.testing.logging.TestLogEvent

tasks.named<Test>("test") {
    useJUnitPlatform {
        excludeTags("dev-db")
    }
}

val devDbTest by tasks.registering(Test::class) {
    description = "Runs tests against development Oracle DB"
    group = "verification"

    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath

    useJUnitPlatform { includeTags("dev-db") }

    // 실행한 테스트의 SQL·Assertion 실패는 Build Fail
    ignoreFailures = false

    // 필수 검증 환경에서는 DB 미설정·접속 불가 및 0건 실행을 Fail
    val required = providers.gradleProperty("devDb.required")
        .map(String::toBoolean)
        .getOrElse(false)
    systemProperty("devDb.required", required.toString())

    // 필수 검증에서는 태그 오류로 테스트가 0건인 경우도 실패 처리
    // Test 태스크가 실제 실행될 때의 리포트만 집계하도록 먼저 정리
    val junitXmlDir = reports.junitXml.outputLocation
    reports.junitXml.required.set(true)
    if (required) {
        doFirst {
            junitXmlDir.get().asFile.deleteRecursively()
        }
        doLast {
            val dir = junitXmlDir.get().asFile
            val testCount = dir.walkTopDown()
                .filter { it.isFile && it.extension == "xml" }
                .sumOf { file ->
                    Regex("""<testsuite\b[^>]*\btests="(\d+)"""")
                        .find(file.readText())
                        ?.groupValues?.get(1)?.toIntOrNull() ?: 0
                }
            if (testCount == 0) {
                throw GradleException(
                    "devDb.required=true but no dev-db tests were discovered"
                )
            }
        }
    }

    // Skip/실패 결과를 콘솔에 노출
    testLogging {
        events(TestLogEvent.SKIPPED, TestLogEvent.FAILED)
    }

    // 개발 DB 테스트의 커버리지 기여분은 수집하지 않음
    extensions.configure<JacocoTaskExtension> {
        isEnabled = false
    }

    // Oracle DB 상태는 Gradle의 입력 추적 대상이 아니므로 항상 새로 검증
    outputs.upToDateWhen { false }
    outputs.cacheIf { false }

    shouldRunAfter(tasks.named("test"))
}
```

- `dev-db` 태그를 일반 `test`에서 제외하고 `devDbTest`를 `check`/`build`에 연결하지 않는 **두 장치**가 기본 빌드를 보호한다.
- `shouldRunAfter`는 실행 순서만 지정하며 의존성을 만들지 않는다.
- `devDbTest`는 외부 DB의 가용성·스키마·데이터·권한에 따라 결과가 달라지므로 `outputs.upToDateWhen { false }`와 `outputs.cacheIf { false }`로 이전 실행 결과의 UP-TO-DATE 판정과 빌드 캐시 재사용을 막는다. 이 설정은 일반 H2 `test`에는 적용하지 않는다.
- 엄격 모드의 `doLast`는 생성된 JUnit XML의 `testsuite`별 테스트 건수를 합산한다. XML은 태스크 실행 전에 삭제하여 잔여 리포트의 오판을 방지한다. 이는 문서용 최소 예시이며, 실제 적용 시 Gradle 9.9.1에서 XML 생성 경로, 테스트 0건/전부 Skip, 태그 불일치와 실패 처리까지 검증해야 한다.
- 수동으로 `devDbTest`를 실행하면 실제 SQL·Assertion 실패는 빌드 실패가 되어야 하므로 `ignoreFailures`를 끄는 것이 기본이다. 과도기의 임시 비차단이 꼭 필요하면 별도 명시적 정책으로 관리하고, 실패를 숨기지 않는 리포트를 확보한다.
- 개발 DB 테스트가 필요한 모듈에만 태스크를 등록하는 것은 의도를 명확히 하고 불필요한 실행·설정을 줄이기 위한 권장이다. JUnit Platform의 `includeTags`로 테스트가 0건이 되는 경우 Gradle 9의 `failOnNoDiscoveredTests`가 이를 잡아주지 않을 수 있으므로, 별도 0건 검증을 유지한다([Gradle 이슈 #38578](https://github.com/gradle/gradle/issues/38578)). `failOnNoDiscoveredTests = false`를 설정하는 것은 이 문제의 해결책이 아니다.
- IDE에서 `dev-db` 테스트를 일반 Gradle `test --tests`로 실행하면 태그 제외로 0건이 될 수 있다. Kiro/VS Code의 Java Test Runner 사용 여부를 확인하고, 확실한 경로로는 `./gradlew :대상모듈:devDbTest --tests '패키지.테스트클래스'`를 사용한다.
- Java 소스셋·JaCoCo 구성을 공통 convention plugin으로 관리한다면, 이 정책 역시 개발 DB 대상 모듈에 적용하는 convention으로 추출할 수 있다.

## 4. 테스트 작성 규칙

### 4.1 합성 애너테이션

`@DevDbTest`에 태그·프로필·연결 조건을 묶어 누락을 방지한다.

```java
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.test.context.ActiveProfiles;

@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Tag("dev-db")
@ActiveProfiles("dev-db")
@ExtendWith(DevDbReachableCondition.class)
public @interface DevDbTest {}
```

```java
@DevDbTest
@Tag("smoke")
@SpringBootTest
class OracleMemberMapperSmokeTest {
    @Test
    void canReadReferenceData() {
        // 조회 전용 계정으로 안정적인 기준 데이터 검증
    }
}
```

### 4.2 Context 생성 전에 연결 가용성 확인

JUnit Jupiter의 `ExecutionCondition`은 테스트 클래스 인스턴스 생성과 SpringExtension의 `BeforeAllCallback`보다 먼저 평가되므로 사전 네트워크 확인에 활용한다. 아래는 **설명용 골격**으로, 실제 코드에서는 실행 조건과 환경별 정책을 별도로 테스트한다.

```java
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import org.junit.jupiter.api.extension.ConditionEvaluationResult;
import org.junit.jupiter.api.extension.ExecutionCondition;
import org.junit.jupiter.api.extension.ExtensionContext;

public final class DevDbReachableCondition implements ExecutionCondition {
    @Override
    public ConditionEvaluationResult evaluateExecutionCondition(ExtensionContext context) {
        // 클래스 수준에서 검사하므로 메서드 수준의 반복 연결은 생략한다.
        if (context.getTestMethod().isPresent()) {
            return ConditionEvaluationResult.enabled("Checked at class level");
        }

        String host = System.getenv("DEV_DB_HOST");
        String port = System.getenv("DEV_DB_PORT");

        if (host == null || host.isBlank() || port == null || port.isBlank()) {
            return unavailable("DEV_DB_HOST/PORT not configured");
        }

        final int portNumber;
        try {
            portNumber = Integer.parseInt(port);
        } catch (NumberFormatException e) {
            throw new IllegalStateException("Invalid DEV_DB_PORT", e);
        }
        if (portNumber < 1 || portNumber > 65535) {
            throw new IllegalStateException("DEV_DB_PORT out of range");
        }

        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, portNumber), 2000);
            return ConditionEvaluationResult.enabled("Development DB endpoint reachable");
        } catch (IOException e) {
            return unavailable("Development DB endpoint unreachable");
        }
    }

    private static ConditionEvaluationResult unavailable(String reason) {
        if (Boolean.getBoolean("devDb.required")) {
            throw new IllegalStateException("Development DB required: " + reason);
        }
        return ConditionEvaluationResult.disabled(reason);
    }
}
```

- 기본 로컬 정책: `DEV_DB_HOST`/`DEV_DB_PORT` 미설정 또는 네트워크 미접속은 Skip. 포트 형식 오류는 설정 결함으로 Fail.
- TCP 연결 가능은 JDBC 인증·서비스명·스키마·권한이 정상이라는 뜻이 아니다. **DB 인증·SQL 실패를 Skip 처리하지 않는다.**
- 메서드 수준의 조건 평가는 곧바로 Enabled를 반환하며 **클래스 수준에서만 소켓 검사를 수행**한다. `@DevDbTest`를 클래스에만 부착한다는 전제이며, 메서드 단독 사용까지 허용한다면 별도 처리가 필요하다. 여러 테스트 클래스가 있으면 클래스별 검사는 남는다. 실제 구현에서는 `ExtensionContext.getRoot().getStore(Namespace...)`를 사용해 실행 범위 안에서 **동일 host/port**의 결과를 캐싱하는 방안을 검토한다(네트워크 상태 변경에 따른 캐시 만료 정책도 결정).
- `DEV_DB_HOST`/`DEV_DB_PORT`는 실제 JDBC URL의 목적지와 일치하도록 관리한다. 특히 RAC/SCAN, 프록시, 다중 주소를 사용하는 경우 단순 소켓 확인은 근사 판정임을 문서화한다.
- `-PdevDb.required=true`를 사용하면 DB 미설정 또는 네트워크 미접속 시 조건 평가에서 예외가 발생하여 Fail로 처리된다. 태그 불일치로 `ExecutionCondition` 자체가 실행되지 않는 상황은 Gradle의 JUnit XML 0건 검사에서 처리한다. XML 집계 로직이 해당 Gradle 버전에서 올바르게 동작하는지 검증해야 한다.

### 4.3 Profile별 설정 파일

테스트 전용 `src/test/resources/application-dev-db.yml`을 권장한다.

```text
src/main/resources/application.yml
src/test/resources/application.yml
src/test/resources/application-dev-db.yml
```

Spring Boot는 `@ActiveProfiles("dev-db")`에서 Profile별 설정을 활성화한다. 테스트의 기본 `application.yml`과 Profile별 설정이 병합되므로 **H2 설정 및 다중 DataSource 중 어느 값이 남는지** 확인한다.

```yaml
# src/test/resources/application-dev-db.yml
spring:
  datasource:
    url: ${DEV_DB_URL}
    username: ${DEV_DB_USERNAME}
    password: ${DEV_DB_PASSWORD}
    driver-class-name: oracle.jdbc.OracleDriver
  sql:
    init:
      mode: never
  batch:
    job:
      enabled: false
    jdbc:
      initialize-schema: never
```

- `spring.datasource`는 Boot 기본 DataSource를 사용할 때만 해당한다. 현재처럼 별도 `@ConfigurationProperties`로 도메인 A/B, Batch 메타데이터 DB를 구성한다면 **실제 설정 prefix별로 명시적으로 치환**해야 한다.
- `spring.sql.init.mode=never`로 기본 `application.yml`에서 병합될 수 있는 H2용 `schema-locations`/`data-locations` 초기화를 차단한다. Spring Batch 자동 Job 실행과 메타 테이블 자동 생성도 비활성화한다. 이 설정들은 사용자 정의 `DataSourceInitializer`, `ResourceDatabasePopulator`, 별도 초기화 코드나 Mapper의 DML까지 막지는 않는다. 특히 다중 DataSource의 독자적인 초기화 로직을 점검한다.
- `@SpringBootTest`는 전체 Context를 띄우므로 Mapper 검증에서는 가능한 최소 Context 또는 `@MybatisTest` 및 `@AutoConfigureTestDatabase(replace = NONE)`를 검토한다. 다중 SqlSessionFactory가 있으면 슬라이스에서 어떤 구성이 로드되는지 검증해야 한다.
- `DEV_DB_URL`과 사전 확인용 `DEV_DB_HOST/PORT`의 불일치는 잘못된 Skip/Enabled를 만들 수 있다. 비밀정보는 Git에 넣지 않는다.

## 5. 실행 명령과 판정

```bash
# 기본 품질 게이트: H2 테스트 및 기존 JaCoCo
./gradlew test jacocoTestReport

# 개발 DB 검증: 접속 불가 시 Skip, 실제 테스트 실패 시 Build Fail
./gradlew devDbTest

# 두 그룹 동시 실행: 개발 DB 검증은 명시 요청된 경우에만 추가
./gradlew test devDbTest

# 필수 DB 검증: 접속 불가 또는 설정 미비도 실패 처리
./gradlew devDbTest -PdevDb.required=true

# 특정 개발 DB 테스트만 실행 (멀티모듈 예시)
./gradlew :batch-domains:batch-member:batch-member-app:devDbTest --tests 'com.example.OracleMemberMapperSmokeTest'
```

멀티모듈에서는 실제 대상 모듈 경로를 사용한다. 테스트 리포트는 해당 모듈의 `build/reports/tests/devDbTest/`에서 확인한다. IDE의 Gradle `test --tests` 실행은 일반 `test`의 태그 필터에 의해 대상이 발견되지 않을 수 있으므로 별도 태스크를 사용한다.

**주의:** `devDbTest`는 매번 새로 실행되도록 증분 판정·빌드 캐시를 비활성화한다. `--rerun-tasks`를 매번 수동으로 붙이는 방식에 의존하지 않는다. `testLogging`의 `SKIPPED`/`FAILED` 이벤트로 콘솔에서 결과를 확인할 수 있지만, `BUILD SUCCESSFUL`만으로 실제 Oracle 테스트가 실행되었다고 판단하면 안 된다. 필수 검증에서는 JUnit XML 기반 0건 검사가 제대로 동작하는지 확인한다.

## 6. JaCoCo 제외 정책과 확인 사항

개발 DB 가용성에 따라 커버리지 수치가 달라지면 JaCoCo 게이트를 신뢰하기 어려워지므로, **환경 의존 테스트의 커버리지 기여분은 수집하지 않는다.**

1. `devDbTest`에서 `JacocoTaskExtension.isEnabled = false`로 계측을 비활성화한다.
2. 기존 `test` 태스크에서는 계측을 계속 유지한다.
3. `jacocoTestReport`의 `executionData`가 `test`에서 생성한 데이터만 집계하는지 검증한다.
4. 커스텀 통합 리포트나 루트 프로젝트의 `fileTree("build") { include("**/*.exec") }` 등이 있으면 `devDbTest` 산출물이 합쳐지지 않도록 조정한다.
5. 과거 실행에서 남은 `devDbTest.exec` 같은 잔여 파일이 집계되지 않는지 `clean` 후 확인한다.

**주의:** JaCoCo의 `classDirectories.exclude`로 테스트 클래스를 제외하는 방식은 목적에 맞지 않는다. 여기서 제외하려는 것은 *테스트 실행으로 인한 커버리지 기여분*이지, 애플리케이션 클래스 자체가 아니다.

## 7. 실패·Skip 판정과 향후 개선

| 상황 | 1차 권장 동작 | Gradle 결과 |
| --- | --- | --- |
| 일반 `build` | 개발 DB 테스트 실행하지 않음 | H2 테스트 결과로 판정 |
| `devDbTest`, 연결 설정 없음 | 기본 Skip / `devDb.required=true`에서 Fail | 기본 모드에서 모두 Skip이면 성공 가능 |
| `devDbTest`, TCP 연결 실패 | 기본 Skip / `devDb.required=true`에서 Fail | 기본 모드에서 모두 Skip이면 성공 가능 |
| TCP 성공, JDBC 인증/서비스명 오류 | 실제 테스트 Fail | Build Fail |
| JDBC 성공, SQL/Assertion 오류 | 실제 테스트 Fail | Build Fail |
| SQL/Assertion 성공 | Pass | Success |

`ignoreFailures=false`는 명시적 테스트 실행 시 결함을 숨기지 않기 위한 기본값이다. `ExecutionCondition`의 Skip은 DB 미접속을 통과시켜도, `testLogging`으로 콘솔에 Skip을 표시한다. 엄격 모드에서는 이 두 상황을 Fail로 전환한다. 태그 오류 등으로 테스트가 전혀 발견되지 않으면 엄격 모드의 JUnit XML 0건 검사에서 Fail 처리한다.

후속 단계에서는 여러 테스트 클래스 간 접속 사전 확인 중복을 최소화한다. 필수 CI 검증에서는 `-PdevDb.required=true`를 사용하고, JUnit XML 기반 0건 검사의 동작도 실제 Gradle 환경에서 검증한다. CI 파이프라인이 개발 DB 검증 결과를 비차단으로 운영해야 한다면 Gradle에서 결과를 성공으로 위장하기보다, 별도 CI Job(예: GitLab `allow_failure: true`)으로 상태를 보존한다.

## 8. 개발 DB 사용 시 안전 수칙

- 가능하면 **조회 전용 계정**과 안정적인 기준 데이터만 이용한다. 애플리케이션 설정으로 쓰기 경로를 제한하고, DB 권한으로도 조회 전용을 강제한다(이중 방어).
- `spring.sql.init.mode=never`, `spring.batch.job.enabled=false`, `spring.batch.jdbc.initialize-schema=never`를 개발 DB 테스트 프로필에 명시한다. `DataSourceInitializer`/`ResourceDatabasePopulator` 등 다중 DataSource의 커스텀 초기화와 Batch 메타데이터 DataSource도 점검한다.
- DML 테스트는 전용 스키마·격리된 테스트 데이터·트랜잭션 롤백 및 정리 전략을 별도 설계한다. 단순 `@Transactional`만으로 외부 시스템·다중 DataSource까지 모두 롤백된다고 가정하지 않는다.
- DB 비밀번호와 연결 문자열의 민감 항목은 환경변수 또는 외부 시크릿 관리로 전달하고 Git에 커밋하지 않는다.
- 개발 DB 데이터 변동으로 깨지는 특정 ID·건수 단정은 최소화한다.
- 네트워크 접속 가능 여부, DB 인증, SQL 유효성, 데이터 검증을 가능한 한 서로 구분해 보고한다.
- 폐쇄망 VDI에서 실행할 수 있는 모듈과 네트워크 경로를 먼저 확인한다.

## 9. 도입·검증 체크리스트

- [ ] 기존 H2 테스트가 `test`에서 계속 실행되고 실패 시 Build Fail인지 확인
- [ ] `dev-db` 태그가 일반 `test`에서 제외되고 `devDbTest`는 `check`/`build`에 연결되지 않는지 확인
- [ ] `@DevDbTest`로 Profile·Tag·ExecutionCondition이 적용되는지 확인
- [ ] `src/test/resources/application-dev-db.yml`이 로딩되며 H2/다중 DataSource 설정이 올바르게 치환되는지 확인
- [ ] 개발 DB 접속 설정 누락 또는 네트워크 차단 시 기본 Skip, `-PdevDb.required=true`에서 Fail로 처리되는지 확인
- [ ] 클래스 단위 접속 확인이 테스트 메서드마다 반복되지 않는지 확인
- [ ] Gradle 콘솔에서 Skip/Fail 이벤트가 출력되는지 확인
- [ ] JDBC 인증 오류, SQL·Assertion 실패 시 Build Fail인지 확인
- [ ] 모든 테스트 Skip 시 성공 표시의 의미가 명확히 보고되는지 확인
- [ ] `devDbTest`를 연속 두 번 실행할 때 두 번째가 `UP-TO-DATE` 또는 `FROM-CACHE`로 건너뛰지 않고 실제 실행되는지 확인
- [ ] 개발 DB 접속 불가로 Skip한 뒤 네트워크 복구 후 재실행 시 실제 테스트가 수행되는지 확인
- [ ] `devDbTest` 실행 시 JaCoCo 비활성화 및 통합 리포트 제외 확인
- [ ] 개발 DB 테스트가 필요한 모듈에만 `devDbTest`를 등록했는지 확인
- [ ] Gradle 9.9.1에서 `includeTags`로 테스트가 0건인 경우 실제 판정을 확인하고 엄격 모드의 JUnit XML 0건 검사가 Fail을 발생시키는지 확인
- [ ] 엄격 모드의 XML 리포트 디렉터리가 실행 전에 정리되어 과거 테스트 건수가 섞이지 않는지 확인
- [ ] `./gradlew devDbTest --configuration-cache -PdevDb.required=true` 실행과 재실행에서 Configuration Cache 관련 오류 없이 동작하는지 확인
- [ ] IDE(Kiro/VS Code 등)에서 `dev-db` 테스트 실행 경로 확인
- [ ] Spring Batch Job 자동 실행·메타데이터 자동 생성·Spring SQL 초기화가 비활성화되는지 확인
- [ ] H2용 DDL/DML 초기화 스크립트가 Oracle DB에서 실행되지 않으며 다중 DataSource의 커스텀 초기화도 안전한지 확인
- [ ] 읽기 전용 계정과 테스트 데이터 안전성 확인
- [ ] 필수 CI 검증에서 `-PdevDb.required=true` 동작 및 `includeTags`로 0건인 경우의 JUnit XML 검사 결과 확인. `failOnNoDiscoveredTests`만으로 충분하다고 가정하지 않음

## 10. 제안 결론

**1차:** 동일 `src/test` 소스셋 + `@DevDbTest` 합성 애너테이션 + 클래스 수준 연결 사전 확인 및 Skip(필수 검증 시 Fail) + 별도 `devDbTest` 태스크(`ignoreFailures=false`, UP-TO-DATE/빌드 캐시 비활성화) + Skip/Fail 콘솔 출력 + JaCoCo 수집 제외 + SQL 초기화 방지를 포함한 테스트 전용 `application-dev-db.yml`을 도입한다. 일반 `build`에는 개발 DB 테스트를 연결하지 않는다.

**2차:** 테스트 규모가 늘어나면 `src/devDbTest` 소스셋 또는 Gradle JVM Test Suite를 검토한다. 연결 확인 캐싱, XML 기반 0건 검사 고도화, CI의 필수 검증 단계, 통합·Smoke의 별도 실행 정책을 환경에 맞게 발전시킨다.

## 11. 멀티모듈 공통화: Convention Plugin + shared:core Test Fixtures

### 11.1 설계 결정

현재 모노레포의 여러 배치 모듈이 `shared:core`를 사용한다. 개발 DB 테스트도 향후 여러 모듈에서 반복 사용할 예정이므로, Gradle 실행 정책과 JUnit 테스트 지원 코드를 분리해 공통화한다. **테스트 지원 코드가 소수인 현재 시점에는 `shared:test` 모듈을 신설하지 않는다.**

| 위치 | 담당 책임 |
| --- | --- |
| `build-logic/src/main/kotlin/dev-db-test-conventions.gradle.kts` | `test` 태그 제외, `devDbTest` 생성, 실패/Skip 로그, JaCoCo 및 캐시 정책, 엄격 모드와 공통 테스트 의존성 |
| `shared:core/src/main/java` | 기존 운영 코드 및 공통 설정. 테스트 라이브러리를 운영 의존성에 추가하지 않음 |
| `shared:core/src/testFixtures/java` | `@DevDbTest`, `DevDbReachableCondition` 등 여러 모듈에서 사용하는 JUnit 지원 코드 |
| 실제 개발 DB 테스트 모듈 | `dev-db-test-conventions` 적용, `@DevDbTest` 테스트와 `src/test/resources/application-dev-db.yml` 작성 |

```text
build-logic/
└── src/main/kotlin/
    └── dev-db-test-conventions.gradle.kts

shared/
└── core/
    └── src/
        ├── main/java/                  # 운영 공통 코드
        └── testFixtures/java/          # DevDbTest, DevDbReachableCondition

batch-domains/
└── batch-member/
    └── batch-member-app/
        ├── build.gradle.kts            # dev-db-test-conventions 적용
        ├── src/test/java/              # Oracle 통합·Smoke 테스트
        └── src/test/resources/
            └── application-dev-db.yml
```

### 11.2 shared:core의 Test Fixtures

Gradle의 `java-test-fixtures`를 적용하면 별도 모듈 없이 테스트용 소스셋과 의존성 구성을 분리할 수 있다. 아래는 **개념 예시**로, 버전 카탈로그 alias와 기존 `java-conventions` 구성에 맞춰 조정한다.

```kotlin
// shared/core/build.gradle.kts
plugins {
    id("java-conventions")
    id("java-test-fixtures")
}

dependencies {
    // @DevDbTest의 public 애너테이션에서 JUnit과 Spring Test 타입 사용
    testFixturesApi(libs.junit.jupiter.api)
    testFixturesApi(libs.spring.test)
}
```

`@DevDbTest`와 `DevDbReachableCondition`은 `src/testFixtures/java`에 두고, 실제 테스트는 소비 모듈의 `src/test/java`에 둔다. Fixture 코드는 `shared:core`의 주 운영 JAR과 별도 variant로 배포·소비된다. **기존의 `implementation(project(":shared:core"))`만으로 Fixture 코드가 소비되는 것은 아니다.**

테스트 지원 코드의 public API가 JUnit·Spring Test 타입을 참조하므로 `testFixturesApi`를 사용한다. 일반 `implementation`에 JUnit을 넣지 않는다. JUnit Engine 및 Spring Boot Test 등 **실제 테스트 실행 의존성은 소비 모듈의 기존 테스트 Convention/의존성에서 제공**되어야 한다.

### 11.3 Convention Plugin이 Fixture 의존성까지 구성

여러 모듈에 반복할 `testImplementation(testFixtures(project(":shared:core")))`를 선택 적용하는 Convention Plugin 내부로 옮긴다.

```kotlin
// build-logic/src/main/kotlin/dev-db-test-conventions.gradle.kts
plugins {
    id("java")
    id("jacoco")
}

dependencies {
    add("testImplementation", testFixtures(project(":shared:core")))
}

// 3장의 기존 test/devDbTest 설정을 여기로 이동한다.
// 해당 설정을 각 모듈에 중복 선언하지 않는다.
```

**주의:** 이는 프로젝트 구성 예시이며, 실제 `build-logic`의 Precompiled Script Plugin 컴파일 환경과 플러그인 적용 순서에서 `testFixtures(project(...))`가 정상 해석되는지 검증해야 한다. 만약 편의 확장 함수 접근에 제약이 있다면 target `Project`의 `dependencies` API로 구성한다. 도메인 테스트에 필요한 `spring-conventions` 등 기존 Plugin은 유지하되, 중복 적용·구성 덮어쓰기를 확인한다.

개발 DB 테스트가 필요한 소비 모듈에서만 Plugin을 적용한다.

```kotlin
// batch-member-app/build.gradle.kts
plugins {
    id("spring-conventions")
    id("dev-db-test-conventions")
}
// 별도의 testImplementation(testFixtures(project(":shared:core"))) 선언 불필요
```

- `shared:core` **자체에는** `dev-db-test-conventions`를 적용하지 않는다. 동일 프로젝트의 Fixture를 다시 프로젝트 의존성으로 추가하는 자기 참조를 피한다.
- Plugin 적용은 **opt-in**이며 모든 하위 프로젝트에 일괄 적용하지 않는다. 테스트가 없는 모듈의 불필요한 태스크 등록과 0건 검증 문제를 줄인다.
- `devDbTest`를 `check`/`build`에 연결하지 않고, 기본 `test`와 JaCoCo/SpotBugs 게이트를 유지한다. 3~9장의 테스트 실행 정책은 그대로 재사용한다.
- `application-dev-db.yml`은 대상 모듈의 테스트 리소스에 두어 도메인별 DataSource를 명시한다. DB 비밀값과 프로필 설정을 Convention Plugin 안에 넣지 않는다.

### 11.4 기존 Nexus 배포 및 빌드 환경 확인

`shared:core`가 Maven/Nexus에 배포된다면 `java-test-fixtures`가 추가하는 Fixture variant와 게시 메타데이터(Gradle Module Metadata, 필요한 경우 별도 artifact)가 소비자와 저장소 정책에 맞는지 확인한다. 일반 애플리케이션에 Fixture가 무조건 전파된다고 가정하지 말고 **실제 운영 `runtimeClasspath`에 JUnit·Spring Test가 포함되지 않는지** 의존성 리포트로 검증한다. 테스트용 variant가 외부 배포에 불필요하다면 게시 variant 관리 정책을 별도로 결정한다.

폐쇄망 Nexus에서 JUnit/Spring Test와 Fixture 관련 의존성을 해석할 수 있는지도 확인한다. Convention Plugin의 공통 적용은 로컬 Gradle 구성·Configuration Cache 비용에 영향을 줄 수 있으므로 기존 멀티모듈 빌드 성능 기준과 비교한다.

### 11.5 도입 체크리스트

- [ ] `shared:core`에 `java-test-fixtures` 적용 후 `src/testFixtures/java` 컴파일 성공
- [ ] Fixture의 `testFixturesApi` 의존성이 소비 모듈 테스트 클래스패스에 제공되는지 확인
- [ ] `dev-db-test-conventions` 적용만으로 `devDbTest`와 Fixture 의존성이 등록되는지 확인
- [ ] `shared:core`에는 개발 DB Convention Plugin을 적용하지 않는지 확인
- [ ] 소비 모듈의 기존 H2 `test`, JaCoCo, SpotBugs 정책이 변경되지 않는지 확인
- [ ] 운영 `runtimeClasspath`에 JUnit·Spring Test 의존성이 Fixture로 인해 유입되지 않는지 확인
- [ ] Nexus 게시/소비 시 Test Fixtures variant 관련 메타데이터와 의존성 해석 확인
- [ ] Gradle 9.9.1에서 `--configuration-cache` 사용 시 추가 Plugin 구성과 `devDbTest` 실행 검증

**결정:** 현재는 별도 `shared:test` 모듈보다 `shared:core` Test Fixtures를 우선 채택한다. 장래에 테스트 공통 기능이 다수의 독립 책임으로 확장되거나 Fixture의 배포/의존성 관리 비용이 커지면 테스트 전용 모듈 분리를 재검토한다.

## 참고 자료

- [Gradle Test 태스크](https://docs.gradle.org/current/dsl/org.gradle.api.tasks.testing.Test.html)
- [Gradle JaCoCo Plugin](https://docs.gradle.org/current/userguide/jacoco_plugin.html)
- [Gradle JVM Test Suite](https://docs.gradle.org/current/userguide/jvm_test_suite_plugin.html)
- [Gradle Java Test Fixtures (9.9.1)](https://docs.gradle.org/9.9.1/userguide/java_test_fixtures_plugin.html)
- [Gradle Convention Plugins](https://docs.gradle.org/current/userguide/implementing_gradle_plugins_convention.html)
- [JUnit 5 User Guide — Tagging and Filtering](https://docs.junit.org/current/user-guide/#writing-tests-tagging-and-filtering)
