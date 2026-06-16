# SmartEdge — Mac App Store 제출 가이드

App Store 배포 + 유료(Freemium IAP) 출시를 위한 단계별 체크리스트.
코드 측 준비(sandbox, AppleScript 음악, IAP)는 완료. 아래는 **App Store Connect / Xcode GUI 작업** 위주.

---

## 0. 사전 요건

- [x] Apple Developer Program 가입 ($99/년) — 완료 (Team ID T6245YXX47)
- [x] App Sandbox 활성화 + entitlements 정리 — 완료
- [x] 금지 API 제거 (MediaRemote/perl/CGEvent tap/DisplayServices) — 완료
- [ ] Xcode signing: Automatically manage signing + Team 선택 확인

---

## 1. App Store Connect — 앱 레코드 생성

1. https://appstoreconnect.apple.com → My Apps → **+** → New App
2. Platform: macOS
3. Name: **SmartEdge** (중복 시 "SmartEdge - Notch Utility" 등 대안)
4. Primary Language: Korean 또는 English
5. Bundle ID: `com.smartedge.app` (Developer Portal에 먼저 등록 필요할 수 있음)
6. SKU: `smartedge-mac-001` (임의 고유값)

---

## 2. In-App Purchase 상품 등록 (Pro)

App Store Connect → 앱 → Features → In-App Purchases → **+**
- Type: **Non-Consumable**
- Reference Name: SmartEdge Pro
- Product ID: **`com.smartedge.app.pro`** (코드/`.storekit`와 정확히 일치해야 함)
- Price: **Tier 8 ($7.99)** — 또는 원하는 가격
- Localization (한/영):
  - 표시 이름: "SmartEdge Pro"
  - 설명(en): "Unlock Shelf, Calendar, and Pomodoro."
  - 설명(ko): "선반, 캘린더, 뽀모도로 잠금 해제."
- 심사용 스크린샷 1장 (Pro 패널 캡처)
- **Small Business Program** 가입 시 수수료 30% → 15% (연매출 $100만 미만). 별도 신청 권장.

### 로컬 테스트 (제출 전)
Xcode → Edit Scheme → Run → Options → **StoreKit Configuration → SmartEdge.storekit** 선택
→ 앱 실행하면 실제 결제 없이 구매/복원 플로우 테스트 가능.

---

## 3. 메타데이터 (한/영)

### 앱 이름 / 부제
- 이름: **SmartEdge**
- 부제(30자): "노치를 워크스페이스로" / "Your notch, supercharged"

### 프로모션 텍스트 (170자)
> MacBook 노치를 음악 컨트롤, 캘린더, 파일 선반으로 활용하세요. 무료로 시작하고 Pro로 더 많은 기능을.

### 설명 (한국어)
> SmartEdge는 MacBook 노치를 음악 컨트롤·캘린더·파일 보관함을 모아놓은 마이크로 워크스페이스로 바꿔주는 메뉴바 앱입니다.
>
> [무료]
> · 음악 — 재생 중인 곡 정보 + 컨트롤 (Apple Music / Spotify)
> · 시계 + 기본 노치 UI
>
> [Pro 일회성 구매]
> · 선반 — 드래그 한 번으로 파일 임시 보관 + AirDrop / 공유
> · 캘린더 — 다가오는 일정을 노치에서 미리 알림
> · 뽀모도로 — 집중 타이머 + 세션 통계
>
> [요구 사항]
> · macOS 13 Ventura 이상
> · 음악 기능은 Apple Music / Spotify 데스크톱 앱 + 자동화(Automation) 권한 필요

### 설명 (English) — 위 내용 영문 번역

### 키워드 (100자, 쉼표)
`notch,menubar,music,calendar,shelf,airdrop,pomodoro,productivity,macbook,clipboard`

### 카테고리
- Primary: Productivity
- Secondary: Utilities

### 지원 URL / 마케팅 URL
랜딩 페이지 (GitHub Pages 무료 가능) — 출시 전 준비

---

## 4. 개인정보 (Privacy)

### Privacy Nutrition Label (App Store Connect → App Privacy)
- 수집 데이터: **없음** (No data collected) — 분석/추적 없음을 권장
- (Webhook/Slack 연동 사용 시 해당 데이터 흐름 명시)

### Info.plist usage descriptions (이미 포함됨, 검토만)
- `NSAppleEventsUsageDescription` — 음악 앱 제어 (Automation)
- `NSCalendarsUsageDescription` — 일정 표시
- `NSBluetoothAlwaysUsageDescription` — 연결 기기 상태

---

## 5. 심사 노트 (App Review Notes) — 중요

리뷰어가 기능을 이해/테스트할 수 있도록 반드시 작성:

> SmartEdge controls Apple Music and Spotify via AppleScript (Apple Events)
> to display now-playing info and transport controls in the MacBook notch.
> The `com.apple.security.automation.apple-events` entitlement +
> NSAppleEventsUsageDescription are used for this. On first launch the app
> requests Automation permission for Music/Spotify; please grant it to see
> the music feature.
>
> To test Pro features (Shelf / Calendar / Pomodoro), use the In-App
> Purchase "SmartEdge Pro". A sandbox tester account can purchase it.
>
> The app is a menu-bar (LSUIElement) utility; its UI appears in the notch
> area and via the menu-bar icon, not as a standard window.

심사용 데모 계정: 불필요 (로그인 없음). Pro는 sandbox 테스터로 구매 테스트.

---

## 6. 스크린샷

필수: 1280×800 또는 1440×900 (16:10), 최소 1장 권장 5장.
콘텐츠 가이드는 [MARKETING.md](MARKETING.md) 참고:
1. 음악 컨트롤 노치 확장
2. 캘린더 알림 (Pro)
3. 선반 드래그앤드롭 (Pro)
4. 뽀모도로 (Pro)
5. Settings / Pro 패널

라이트·다크 모드 둘 다 준비 권장.

---

## 7. 앱 아이콘

- 1024×1024 마스터 → Asset Catalog AppIcon (모든 크기)
- 디자인 방향: [MARKETING.md](MARKETING.md) §1 참고 (노치 실루엣 모티프)
- **아이콘 없으면 제출 불가** — 출시 전 필수

---

## 8. Archive + 업로드

1. Xcode → Product → Destination → **Any Mac**
2. Product → **Archive** (Release config)
3. Organizer → **Validate App** (사전 검증 — entitlement/서명 문제 조기 발견)
4. **Distribute App** → App Store Connect → Upload
5. App Store Connect에서 빌드 선택 → 메타데이터/IAP 첨부 → **제출**

---

## 9. 제출 전 최종 체크리스트

- [ ] 앱 아이콘 (1024 + 전체 크기)
- [ ] 스크린샷 5장 (라이트/다크)
- [ ] IAP 상품 `com.smartedge.app.pro` 생성 + 가격
- [ ] Small Business Program 신청 (15% 수수료)
- [ ] 메타데이터 (이름/부제/설명/키워드 한+영)
- [ ] Privacy nutrition label
- [ ] 심사 노트 (Automation + IAP 설명)
- [ ] 지원 URL (랜딩 페이지)
- [ ] Localization .strings를 Xcode에 등록 (Add Files — `localization-pending`)
- [ ] AppleScript 음악 + Pro 구매 실기기 테스트 통과
- [ ] Validate App 통과
- [ ] Archive 업로드

---

## 알려진 리뷰 리스크 + 대비

| 리스크 | 대비 |
|---|---|
| Automation(Apple Events) 사용 | 심사 노트에 명확히 설명 + usage description. 정당한 기능이라 통과 사례 많음 (음악 위젯류) |
| 노치 오버레이 윈도우 레벨 | 표준 NSWindow 레벨. screen-saver 레벨 같은 비표준이면 사유 설명 |
| LSUIElement (윈도우 없는 앱) | 심사 노트에 메뉴바/노치 UI임을 명시 |
| IAP 기능 잠금 | Pro 패널 + 복원 버튼 필수 (구현됨) |

---

*이 문서는 자동 생성 초안입니다. App Store Connect 화면/정책은 수시 변경되니 실제 제출 시 최신 화면 기준으로 진행하세요.*
