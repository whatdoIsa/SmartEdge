# App Store Connect 메타데이터 — 복붙용 최종본

모든 필드는 App Store Connect 글자 수 제한 내로 검증됨 (괄호 안은 글자 수/제한).
App Store Connect → 앱 → (언어별) App Information / Version Information 에 그대로 붙여넣기.

---

## 공통

- **앱 이름 (Name, ≤30)**: `SmartEdge`
- **Bundle ID**: `com.smartedge.app`
- **SKU**: `smartedge-mac-001`
- **Primary Category**: Productivity
- **Secondary Category**: Utilities
- **Price**: Free (앱 본체 무료, Pro는 In-App Purchase)
- **In-App Purchase**: SmartEdge Pro — `com.smartedge.app.pro` — Non-Consumable — $7.99 (Tier 8)

---

## 한국어 (Korean)

**부제 (Subtitle, 15/30)**
```
노치를 나만의 워크스페이스로
```

**프로모션 텍스트 (Promotional Text, 60/170)**
```
MacBook 노치를 음악 컨트롤·캘린더·파일 선반으로. 무료로 시작하고 Pro로 더 많은 기능을 누리세요.
```

**설명 (Description)**
```
SmartEdge는 MacBook의 노치를 음악 컨트롤, 캘린더, 파일 보관함을 한곳에 모은 마이크로 워크스페이스로 바꿔주는 메뉴바 앱입니다.

■ 무료
· 음악 — 재생 중인 곡 정보와 컨트롤 (Apple Music · Spotify)
· 시계와 기본 노치 UI

■ SmartEdge Pro (일회성 구매)
· 선반 — 드래그 한 번으로 파일을 노치에 임시 보관, AirDrop·메시지로 바로 공유
· 캘린더 — 다가오는 일정을 노치에서 미리 알림
· 뽀모도로 — 집중 타이머와 세션 통계

■ 이렇게 쓰세요
· 노치에 마우스를 올리면 펼쳐집니다
· 메뉴바 아이콘으로 모든 기능과 설정에 접근
· ⇧⌘V로 클립보드 기록 호출

■ 요구 사항
· macOS 13 Ventura 이상
· 음악 기능은 Apple Music 또는 Spotify 데스크톱 앱과 자동화(Automation) 권한이 필요합니다

SmartEdge Pro는 자동 갱신되지 않는 일회성 구매입니다.
```

**키워드 (Keywords, 위 영문과 동일 사용 권장 — 한국어 키워드 원하면 아래)**
```
노치,메뉴바,음악,캘린더,클립보드,에어드랍,뽀모도로,생산성,맥북,선반
```

---

## English

**Subtitle (24/30)**
```
Your notch, supercharged
```

**Promotional Text (112/170)**
```
Turn your MacBook notch into a control center for music, calendar, and files. Free to start, Pro to unlock more.
```

**Description**
```
SmartEdge turns your MacBook's notch into a micro-workspace that brings music controls, your calendar, and a file shelf together in one place.

■ Free
· Music — now-playing info and controls (Apple Music · Spotify)
· Clock and the core notch UI

■ SmartEdge Pro (one-time purchase)
· Shelf — drop files onto the notch to stash them, then send via AirDrop or Messages
· Calendar — upcoming events surfaced right in the notch
· Pomodoro — focus timer with session stats

■ How to use
· Hover the notch to expand it
· Reach every feature and setting from the menu-bar icon
· Press ⇧⌘V for clipboard history

■ Requirements
· macOS 13 Ventura or later
· Music features need the Apple Music or Spotify desktop app plus Automation permission

SmartEdge Pro is a one-time purchase and does not auto-renew.
```

**Keywords (82/100)**
```
notch,menubar,music,calendar,shelf,airdrop,pomodoro,clipboard,productivity,macbook
```

---

## 심사 노트 (App Review Notes) — 영문 권장

```
SmartEdge is a menu-bar (LSUIElement) utility. Its UI appears in the
MacBook notch area and via the menu-bar icon, not as a standard window.

Music: SmartEdge controls Apple Music and Spotify via AppleScript
(Apple Events) to show now-playing info and transport controls in the
notch. It uses the com.apple.security.automation.apple-events entitlement
plus NSAppleEventsUsageDescription. On first launch the app requests
Automation permission for Music/Spotify — please approve it to see the
music feature working.

In-App Purchase: "SmartEdge Pro" (com.smartedge.app.pro) unlocks Shelf,
Calendar, and Pomodoro. Use a sandbox tester account to verify the
purchase and the "Restore Purchases" button in Settings → SmartEdge Pro.

No account/login required.
```

---

## App Privacy (Nutrition Label)

- **Data Collection**: None (No data collected) 권장
- 추적/분석 SDK 없음. (Slack/webhook 연동을 켠 경우에만 해당 데이터 흐름 신고)

---

*글자 수는 2026-06 기준 App Store Connect 제한으로 검증됨. 실제 입력 시 화면의 카운터로 재확인 권장.*
