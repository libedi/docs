# Gradle 멀티모듈에서 스테이징된 파일만 Spotless로 포맷팅하는 제안

- 작성일: 2026-11-13
- 상태: 제안

## 배경

feature 브랜치의 pre-commit 훅에서 루트 `spotlessApply`를 실행한다. 규모가 큰 모노레포에서는 새 Git 워크트리마다 Gradle의 프로젝트별 실행 이력이 없어 첫 실행에 포맷팅 대상 전체가 처리될 수 있다. 커밋 한 건에 포함된 파일만 포맷팅하면 워크트리마다 이 비용을 반복하는 일을 줄일 수 있다.

## 제안

feature 브랜치의 pre-commit 훅에서 Git 인덱스에 올라간 경로를 추출하고, 기존 `spotless-conventions`가 해당 경로 중 포맷팅 규칙에 해당하는 파일만 대상으로 삼게 한다. 일반 Gradle 호출과 develop 브랜치의 기존 `spotlessCheck` 정책은 유지한다.

```bash
git diff --cached --name-only --diff-filter=ACMR -z
```

`--cached`는 현재 `HEAD`와 인덱스를 비교한다. rebase 뒤에도 feature 커밋이 있으면 `HEAD`는 마지막 feature 커밋을 가리킨다. 예를 들어 첫 커밋에 `A.java`, 두 번째 커밋에 `B.java`를 각각 스테이징하면 두 번째 훅에는 `B.java`만 들어간다. 두 커밋에서 같은 파일을 수정하면 두 번 대상이 될 수 있다. 목록이 같더라도 Gradle의 `UP-TO-DATE` 판단에는 파일 내용과 설정, 출력 상태가 함께 반영된다.

## 훅과 Gradle 사이의 파일 목록

1. 훅은 워크트리 루트에서 Git을 실행하고, NUL로 구분된 저장소 상대 경로를 실행별 고유 임시파일에 기록한다. Git 실행 실패는 훅 실패로 처리한다. 목록이 비어 있으면 Gradle 실행을 생략한다.
2. 훅은 `./gradlew spotlessApply "-PspotlessStagedFileList=$listFile"`로 임시파일의 절대 경로를 넘긴다. `spotlessStagedFileList`는 이 제안에서 추가하는 프로젝트 프로퍼티다. Gradle이 성공하거나 실패해도 훅은 임시파일을 정리한다.
3. convention plugin은 목록의 경로를 현재 워크트리 루트 기준으로 해석한다. 각 모듈의 포맷별 기존 포함·제외 규칙을 후보 경로에 적용한 뒤, 일치하는 파일만 Spotless의 `target`으로 전달한다. 기존 대상 트리를 먼저 열거하면 전체 파일 탐색 비용이 남으므로 후보 목록에서 시작한다. 일치하는 파일이 없는 포맷에는 빈 대상을 적용한다. 목록을 읽거나 해석할 수 없으면 오류로 중단한다.
4. 첫 적용은 Gradle 호출 한 번으로 시작한다. 모듈별 태스크 선택은 파일 경로와 Gradle 프로젝트 경로의 매핑을 신뢰할 수 있고, 측정에서 태스크 선택 비용이 유의미할 때 검토한다.

Spotless 기본 옵션인 `-PspotlessFiles`는 쉼표로 구분된 정규식을 받는다. 경로가 긴 멀티모듈 저장소에서는 파일이 많은 커밋 한 번으로 Windows `cmd.exe`의 명령줄 제한(8,191자)에 닿을 수 있다. 목록 파일은 명령줄 길이와 파일명 정규식 이스케이프 문제를 함께 해결한다.

## 부분 스테이징과 자동 재스테이징

Git 인덱스는 대상 **경로**를 고르는 데 쓰인다. `spotlessApply`는 작업 트리의 파일 전체를 포맷하므로, 한 파일 안에 스테이징한 변경과 미스테이징 변경이 함께 있을 때 포맷 결과를 `git add`하면 다음 커밋 몫까지 포함할 수 있다.

자동 재스테이징을 사용하는 경우, 포맷 실행 전에 대상 경로에 미스테이징 변경이 있는지 검사한다. 발견하면 커밋을 중단하고 해당 경로를 안내한다. 포맷 성공 뒤에는 실제 포맷팅 대상 중 변경된 파일만 재스테이징한다. 포맷이 실패하면 인덱스를 갱신하지 않는다.

## 검증

- 새 워크트리에서 모듈 한 곳의 파일만 스테이징하고, 그 파일만 포맷되는지 확인한다. 다른 모듈의 같은 파일명과 미스테이징 파일은 별도로 확인한다.
- 커밋을 둘로 나눠 각 훅 실행의 목록이 해당 커밋을 따르는지 확인한다. 부분 스테이징된 파일이 있으면 인덱스를 변경하기 전에 중단되는지 확인한다.
- 공백이 있는 경로, 이름이 바뀐 파일, 삭제만 있는 커밋, Windows에서 기존 인자 제한을 넘길 정도로 많은 파일을 포함한 커밋을 확인한다.
- 동일한 변경을 별도의 새 워크트리에 준비해 기존 훅과 제안 훅의 시간을 비교한다. Gradle 구성 시간과 Spotless 태스크 시간을 따로 기록한다. 목록을 구성 단계에서 읽으면 목록 변경에 따라 Configuration Cache 재사용이 줄 수 있으므로, 사용 중이라면 캐시 적중 여부도 함께 기록한다.

## 참고

- [Git diff 문서](https://git-scm.com/docs/git-diff)
- [Spotless Gradle 플러그인의 파일 선택](https://github.com/diffplug/spotless/tree/main/plugin-gradle#can-i-apply-spotless-to-specific-files)
- [Gradle 프로젝트별 캐시](https://docs.gradle.org/current/userguide/directory_layout.html)
- [Windows 명령줄 길이 제한](https://learn.microsoft.com/ko-kr/troubleshoot/windows-client/shell-experience/command-line-string-limitation)
