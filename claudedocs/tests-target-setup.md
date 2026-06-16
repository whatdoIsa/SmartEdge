# Tests 타겟 추가 가이드 (사용자 수행 — Xcode GUI 1회)

이 프로젝트에는 5개의 XCTest 파일이 작성되어 있지만, Xcode 프로젝트에는 아직 테스트
타겟이 없습니다. CI 친화적인 방법(`project.pbxproj` 직접 편집)은 프로젝트 파일 손상
위험이 커서, 30초짜리 Xcode GUI 작업으로 처리하는 것이 가장 안전합니다.

## 작성된 테스트 파일

```
Tests/
├── MediaServiceTests.swift          (기존)
├── KeychainStorageTests.swift       (M1 신규 — 7개 케이스)
├── SettingsKeysTests.swift          (M1 신규 — 4개 케이스)
├── PKCEGeneratorTests.swift         (M1 신규 — 9개 케이스)
├── WebhookServiceTests.swift        (M1 신규 — 5개 케이스, URLProtocol 스텁)
└── WebhookCoordinatorTests.swift    (M1 신규 — 4개 케이스, UserDefaults 격리)
```

총 29 + α 케이스. PKCE / Keychain / WebhookService / WebhookCoordinator / SettingsKeys
모두 커버.

## 1회 GUI 작업

1. Xcode에서 `SmartEdge.xcodeproj` 열기.
2. 좌측 Project Navigator에서 최상위 `SmartEdge` 프로젝트 아이콘 선택 →
   가운데 패널에서 **TARGETS** 섹션 하단의 `+` 버튼 클릭.
3. **macOS → Unit Testing Bundle** 선택 → Next.
4. 설정:
   - Product Name: `SmartEdgeTests`
   - Team / Organization Identifier: 기존 SmartEdge 타겟과 동일
   - Language: Swift
   - **Project**: SmartEdge
   - **Target to be Tested**: SmartEdge
   - Finish.
5. Xcode가 기본 `SmartEdgeTests/` 폴더와 더미 파일을 생성. 그 더미 파일은 삭제하고:
6. Project Navigator에서 우클릭 → **Add Files to "SmartEdge"...** →
   `Tests/` 폴더의 6개 `.swift` 파일 선택 → **Add to targets: ✅ SmartEdgeTests** (메인
   SmartEdge 타겟은 체크 해제) → Add.
7. ⌘U로 테스트 실행.

## 빌드 설정 (자동 적용되지만 확인)

- **Deployment Target**: macOS 13.0 (메인 타겟과 동일해야 `@testable import` 작동)
- **Test Host**: $(BUILT_PRODUCTS_DIR)/SmartEdge.app/Contents/MacOS/SmartEdge
- **Bundle Loader**: $(TEST_HOST)

이 두 값은 Xcode가 "Target to be Tested = SmartEdge" 선택 시 자동 설정합니다.

## 예상 결과

```
Test Suite 'KeychainStorageTests' passed
  ✓ testSetAndGetString
  ✓ testOverwriteString
  ✓ testEmptyStringDeletes
  ...
Test Suite 'PKCEGeneratorTests' passed
  ✓ testCodeVerifierLength
  ✓ testCodeChallengeIsSHA256OfVerifier
  ...
Test Suite 'SettingsKeysTests' passed
  ✓ testAllUserSettingsHasNoDuplicates
  ✓ testAllUserSettingsCountMatchesExpected
  ...

Executed 29 tests, with 0 failures
```

## 트러블슈팅

**`@testable import SmartEdge` 에러**: SmartEdge 메인 타겟의 Build Settings에서
`ENABLE_TESTABILITY = YES`인지 확인. Debug 빌드에서는 기본 YES.

**KeychainStorageTests 실패**: macOS 키체인 접근 권한 — 테스트 실행 시 시스템이
"keychain access?" 다이얼로그를 표시할 수 있음. Always Allow.

**WebhookServiceTests 실패**: URLProtocol 스텁이 작동하려면 URLSession을 직접 생성
해야 함 (`.shared` 인스턴스에는 등록 불가). 테스트 코드가 이미 그렇게 구성됨.

## 향후 자동화

CI 환경에서는 `xcodebuild test -scheme SmartEdge -destination 'platform=macOS'`로
실행. GitHub Actions 워크플로우 예시는 GitHub 공개 준비 단계에서 추가 예정.
