# Multi-Display & Spotify Polling — Manual Verification Protocol

이 문서는 G2/H3/I1/J2/K1 변경사항을 사용자가 실제 하드웨어 (외부 모니터, Spotify 계정)
에서 검증하기 위한 단계별 가이드입니다. 컴파일/링크는 통과했지만 하드웨어 의존 동작은
자동 검증 불가하므로 수동으로 확인해야 합니다.

## 준비

1. **Console.app 열기** → 좌측 상단 검색창에 `subsystem:com.smartedge.app` 입력 → 실시간
   로그 모니터링 모드 진입. (Bundle ID가 다르면 그 값으로 대체)
2. SmartEdge를 정상 실행. 메뉴바 아이콘이 보이면 OK.
3. Settings 창 열기: 메뉴바 아이콘 → Settings → "Notch Display" 패널 선택.

---

## Test 1: 외부 모니터에서 노치 위치 정확성 (G2 W6)

**가설**: 보조 디스플레이의 screen origin을 더하지 않으면 노치가 primary 디스플레이로
옮겨감. W6 수정으로 항상 선택된 디스플레이의 올바른 좌표에 배치되어야 함.

**절차**:
1. 외부 모니터를 연결 (HDMI/DisplayPort/USB-C, 디스플레이 배치는 상관 없음)
2. Console.app에서 `Notch placed on display` 검색
3. 출력 예시:
   ```
   Notch placed on display 69734400 safeAreaTop=0.0 frame={{1920, 1080}, {200, 32}}
   ```
4. **확인 포인트**:
   - `frame={{x, y}, ...}`의 x, y가 선택된 디스플레이의 origin과 일관성 있는지
   - 외부 모니터 좌측 배치(`{-1920, 0}`) 시: x가 음수로 시작
   - 외부 모니터 하단 배치(`{0, -1080}`) 시: y가 음수 영역까지 포함

5. **NotchSettingsPanel → Display Diagnostics** 섹션 열기 → 각 디스플레이 카드의
   "Frame" 값이 OSLog frame과 일관성 있는지 비교.

**실패 케이스**: 외부 모니터에 연결했는데 노치가 MacBook 화면에만 보이거나 잘못된
위치 → W6 수정이 적용되지 않은 것. `screenFrame.origin.x/y` 누락 의심.

---

## Test 2: 케이블 재연결 시 sticky displayID (H3)

**가설**: `lastUsedDisplayID` 캐싱으로 cable disconnect/reconnect 시 같은 물리 모니터에
노치가 유지됨. `NSScreen.screens` 배열 순서가 바뀌어도 영향 없어야 함.

**절차**:
1. 노치가 어떤 디스플레이에 표시 중인지 확인 (Console.app의 displayID 값을 기록).
   예: `display 69734400`
2. **케이블 분리** → Console.app에 `Notch: no eligible screens; hiding window.` 또는
   다른 디스플레이로 옮겨갔다는 로그 확인.
3. **케이블 재연결** → 같은 displayID로 복귀하는지 확인:
   ```
   Notch placed on display 69734400 safeAreaTop=... frame=...
   ```
4. **외부 노치 있는 MacBook (예: 다른 M-series) 연결** 시나리오: 처음 선택된 디스플레이가
   계속 유지되는지. lastUsedDisplayID가 비어있을 때만 새 선택 발생.

**실패 케이스**: 케이블 재연결 시 displayID가 매번 바뀜 → `lastUsedDisplayID` 캐싱 누락 의심.

---

## Test 3: 외부 모니터 표시 옵션 토글 (I1)

**가설**: `showOnNonNotchDisplays` false 설정 + 외부 모니터만 연결 → 노치 숨김. true로
다시 전환 시 즉시 표시 (재시작 불필요).

**절차**:
1. NotchSettingsPanel → Appearance → "Show on monitors without a hardware notch" 토글 끄기.
2. Console.app:
   ```
   Notch: showOnNonNotchDisplays toggle → false; re-evaluating placement.
   ```
3. MacBook lid를 닫지 않은 상태에서는 노치 그대로 표시 (MacBook에 hardware notch 있음). OK.
4. **Clamshell 모드 진입** (lid 닫기) → MacBook 화면 꺼짐 + 외부 모니터만 남음:
   - 토글 false → 노치 사라짐 (`hiding window` 로그)
   - 토글 true로 재설정 → 즉시 외부 모니터 menu bar 아래에 노치 표시
5. **clamshell 없이도 검증 가능**: 외부 모니터만 활성 상태로 설정 (Display Arrangement
   에서 mirroring 끄고 외부 모니터를 "사용 안 함" 해제) → 동일 동작.

**실패 케이스**: 토글 변경 시 로그는 나오는데 노치 상태 변화 없음 → KVO 키 이름 매칭
이슈 (`@objc dynamic var showOnNonNotchDisplays`가 UserDefaults 키와 정확히 일치하는지).

---

## Test 4: Display Diagnostics UI 실시간 갱신 (J2)

**가설**: NotchSettingsPanel 하단 Display Diagnostics 섹션이
`NSApplication.didChangeScreenParametersNotification`을 구독해 자동 갱신.

**절차**:
1. Settings 열어둔 상태로 Display Diagnostics 섹션 스크롤.
2. 외부 모니터 케이블 분리/연결.
3. **확인**: 카드 리스트가 자동으로 갱신되는지 (별도 새로고침 버튼 클릭 없이).
4. 각 카드 필드 검증:
   - `Display ID`: 0이 아닌 양수
   - `Frame`: NSScreen.frame 값
   - `Safe area top`: MacBook 노치 보유 디스플레이는 ≥ 30pt, 외부 모니터는 0.0
   - `notch` 배지가 hardware notch 있는 디스플레이에만 표시
   - `main` 배지가 NSScreen.main에만 표시

---

## Test 5: Spotify 폴링 lifecycle (K1)

**가설**: SpotifyPollingCoordinator가 noth expanded + musicPlayer content + signedIn
일 때만 폴링. 그 외 모든 상태에서는 즉시 정지.

**전제**: Spotify Developer Console에서 Client ID 발급 + Settings → Integrations
에서 Sign In 완료.

**절차**:
1. Console.app 필터: `category:Media`
2. 노치 collapsed 상태 → Spotify Sign In 완료 후:
   - 폴링 시작 로그 **없어야 함** (notch expanded 아니므로)
3. 메뉴바 아이콘 → 음악 노치 열기 (`MusicPlayer` content) → expanded 상태로 전환:
   ```
   Spotify polling: START (expanded=true music=true signedIn=true)
   ```
4. 15초 단위로 `Spotify ... fetch player state` 류 로그 확인 (별도 트레이스가 SpotifyService
   내부에는 없지만, network log로 `/me/player` 요청 확인 가능)
5. 노치 collapsed로 전환 (다른 곳 클릭):
   ```
   Spotify polling: STOP (expanded=false music=true signedIn=true)
   ```
6. 음악 노치 → 다른 노치(예: Pomodoro)로 전환:
   ```
   Spotify polling: STOP (expanded=true music=false signedIn=true)
   ```
7. Settings → Sign Out:
   ```
   Spotify polling: STOP (expanded=... music=... signedIn=false)
   ```

**실패 케이스**: STOP 로그가 나오지 않거나, 조건이 false인데 fetchPlayerState
요청이 계속 발생 → CombineLatest3 구독 누수 또는 task.cancel() 누락.

---

## Test 6: I2 augmented Now Playing badge

**가설**: MediaRemote가 title/artist를 null로 반환하는 케이스에 SpotifyService.playerState
가 보강. "Spotify" capsule 배지 표시.

**절차**:
1. Spotify 데스크톱 앱 시작 + 곡 재생 + SmartEdge에 sign in.
2. Spotify 노치 열기 → "Now Playing" 표시 확인.
3. MediaRemote가 정상이면 일반 표시 (배지 없음). 시뮬레이션 어려움.
4. **MediaRemote null 케이스 재현**: 일부 웹 브라우저 (Safari에서 YouTube 재생 후
   탭 닫기 등)에서 stale 상태 유지될 때 가능.

**예상 동작**: title이 빈 상태일 때 Spotify 데이터로 채워지고 녹색 "Spotify" 배지 표시.

---

## 정직 보고 — 검증의 한계

- Test 1-2: 외부 모니터 + 케이블 swap 필수.
- Test 3: clamshell 모드 진입이 가장 확실, 그 외엔 Display Arrangement 조작으로 우회.
- Test 5: Spotify Premium 계정 필요 (Web API의 transfer/play 엔드포인트는 Premium 한정).
- Test 6: MediaRemote 누락 케이스 재현이 비결정적. "발생하지 않음" 자체가 검증 결과로 인정 가능.

## 발견 시 회신

각 Test의 결과(Pass/Fail/N/A)와 Fail의 경우 Console.app 로그 발췌를 함께 보고하면
세션 재개 시 원인 분석 + 추가 수정 가능합니다.
