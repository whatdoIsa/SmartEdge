# BoringNotch Clone — AI Team Orchestrator

## Project Overview
macOS menubar/notch utility app built with SwiftUI + AppKit.
Target: macOS 13 Ventura + macOS 14 Sonoma 양쪽 지원, Apple Silicon + Intel.
Architecture: MVVM + Coordinator + Service Layer.

## Tech Stack
- Language: Swift 5.9+
- UI: SwiftUI (components) + AppKit (NSWindow control)
- Xcode: 16+
- Minimum Deployment: macOS 13.0 (Ventura)
- macOS 14+ 전용 API 사용 금지. 필요 시 `if #available(macOS 14.0, *)` 분기 또는 macOS 13 호환 API 사용.
  - 예: `.windowBackground` → `Color(NSColor.windowBackgroundColor)`
  - 예: `EKAuthorizationStatus.fullAccess` → `.authorized`
  - 예: `onChange(of:initial:_:)` 3-arg → `onChange(of:) { newValue in ... }` 2-arg
- No third-party dependencies unless explicitly approved

## Architecture Rules (MUST FOLLOW)
```
App
├── Core/
│   ├── Services/          ← 시스템 API 래핑 (비즈니스 로직 없음)
│   ├── Coordinators/      ← 화면/상태 전환 관리
│   └── Extensions/        ← Swift extension 모음
├── Features/
│   ├── Notch/             ← NotchView + NotchViewModel
│   ├── MusicPlayer/       ← MusicPlayerView + MusicPlayerViewModel
│   ├── HUD/               ← HUDView + HUDViewModel
│   ├── Shelf/             ← ShelfView + ShelfViewModel
│   ├── Calendar/          ← CalendarView + CalendarViewModel
│   └── Settings/          ← SettingsView + SettingsViewModel
├── Shared/
│   ├── Components/        ← 재사용 SwiftUI 컴포넌트
│   ├── Models/            ← 공유 데이터 모델
│   └── Constants/         ← 앱 전역 상수
└── XPCHelper/             ← 권한 분리 프로세스
```

## Dependency Direction (절대 역방향 금지)
```
View → ViewModel → Service → System API
View는 ViewModel만 참조
ViewModel은 Service만 참조
Service는 시스템 프레임워크만 참조
```

## Coding Standards
- 불필요한 주석 금지. 코드가 self-explanatory해야 함
- 이모티콘 금지
- `guard let` 우선, `if let` 중첩 금지
- `weak self` 클로저에서 필수
- Protocol-first 설계: 구체 타입보다 프로토콜 노출
- `@MainActor` UI 업데이트에 항상 명시
- `async/await` 사용, completion handler 금지

## File Naming
- ViewModel: `{Feature}ViewModel.swift`
- View: `{Feature}View.swift`
- Service: `{Name}Service.swift`
- Protocol: `{Name}Protocol.swift`
- 파일 하나에 타입 하나 (extension 제외)

---

## Agent Routing Rules

### Parallel dispatch — 아래 조건 모두 충족 시
- 작업 간 파일 의존성 없음
- 공유 상태 없음
- 명확한 파일 경계 존재
- 각 작업이 독립 완결 가능

### Sequential dispatch — 아래 중 하나라도 해당 시
- 작업 B가 작업 A의 결과물에 의존
- 공유 파일을 두 작업이 동시에 수정
- 범위 불명확, 선행 탐색 필요

### Agent 선택 기준
| 요청 유형 | 담당 Agent |
|---|---|
| 파일 구조, 프로토콜 설계, 의존성 | ios-architect |
| Service 구현, ViewModel 로직 | feature-engineer |
| SwiftUI 컴포넌트, 애니메이션 | ui-designer |
| 코드 리뷰, 버그, 엣지케이스 | qa-reviewer |
| NSWindow, AppKit 시스템 연동 | system-integrator |

### 병렬 실행 예시
```
독립 서비스 구현 → feature-engineer × N (병렬)
독립 뷰 구현    → ui-designer × N (병렬)
아키텍처 설계 후 → feature-engineer + ui-designer (병렬)
```

### 순차 실행 예시
```
ios-architect (구조 확정)
  → feature-engineer (Service 구현)
    → ui-designer (View 구현)
      → qa-reviewer (리뷰)
```

---

## Feature Implementation Priority
1. NotchWindowManager — NSWindow 커스텀, 노치 위치, 호버
2. MediaService — Now Playing, 재생 컨트롤
3. MusicPlayerView — 비주얼라이저 포함
4. SystemHUDService — 볼륨/밝기 인터셉트
5. ShelfFeature — 드래그앤드롭, AirDrop
6. CalendarService + View
7. BatteryService + BluetoothService
8. SettingsView
9. XPCHelper 분리

## Known Technical Risks (에이전트 주의사항)
- MediaRemote: private framework, 직접 import 불가 → 동적 로딩 필요
- IOKit HUD 인터셉트: macOS 버전별 동작 차이 존재
- NSWindow level 설정: `.screenSaver` 레벨 필요, entitlements 확인
- XPC: 별도 타겟으로 반드시 분리
- Sandbox: 일부 기능은 App Sandbox 비활성화 필요

## Communication Protocol Between Agents
- 각 에이전트는 작업 완료 시 변경된 파일 목록과 공개 인터페이스(프로토콜)를 명시
- 다음 에이전트는 해당 인터페이스만 참조, 구현 내부 참조 금지
- 충돌 발생 시 ios-architect에게 에스컬레이션
