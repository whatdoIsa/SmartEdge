# SmartEdge 현재 파일 구조

## 디렉토리 구조
```
SmartEdge/
├── Core/
│   ├── Services/           # 시스템 API 래핑 서비스들
│   ├── Coordinators/       # 화면/상태 전환 관리  
│   └── Extensions/         # Swift extension 모음
├── Features/
│   ├── Notch/             # NotchView + NotchViewModel
│   ├── MusicPlayer/       # MusicPlayerView + MusicPlayerViewModel  
│   ├── HUD/               # HUDView + HUDViewModel
│   ├── Shelf/             # ShelfView + ShelfViewModel
│   ├── Calendar/          # CalendarView + CalendarViewModel
│   └── Settings/          # SettingsView + SettingsViewModel
├── Shared/
│   ├── Components/        # 재사용 SwiftUI 컴포넌트
│   ├── Models/            # 공유 데이터 모델  
│   └── Constants/         # 앱 전역 상수
└── Settings/              # 설정 관련 별도 모듈
```

## 현재 Swift 파일들

### Core/Services (핵심 서비스 레이어)
- `BatteryService.swift` ✅
- `BluetoothService.swift` ✅  
- `NotchWindowService.swift` 🔴 (override 에러)
- `ClipboardMonitorService.swift` ✅
- `ShelfService.swift` 🔄 (FileType 에러)
- `MediaService.swift` 🔄 (MainActor 경고)
- `MediaServiceAdapter.swift` 🔴 (타입 에러들)
- `NotchWindowManager.swift` ✅
- `SystemHUDService.swift` ✅

### Features (기능별 모듈)
- `Features/Notch/NotchView.swift` ✅
- `Features/Notch/NotchViewModel.swift` ✅
- `Features/MusicPlayer/MusicPlayerView.swift` ✅
- `Features/MusicPlayer/MusicPlayerViewModel.swift` ✅
- `Features/HUD/HUDView.swift` ✅  
- `Features/HUD/HUDViewModel.swift` ✅
- `Features/Shelf/ShelfView.swift` ✅
- `Features/Shelf/ShelfViewModel.swift` ✅
- `Features/Calendar/CalendarView.swift` ✅
- `Features/Calendar/CalendarViewModel.swift` ✅

### Settings (설정 모듈)
- `Settings/SettingsView.swift` ✅
- `Settings/SettingsViewModel.swift` ✅
- `Settings/Sidebar/SettingsSidebar.swift` ✅
- `Settings/Panels/*.swift` ✅ (11개 패널 모두 완성)
- `Settings/Components/*.swift` ✅

### Shared (공유 컴포넌트)
- `Shared/Components/*.swift` ✅
- `Shared/Models/*.swift` 🔄 (MediaData 누락)
- `Shared/Constants/*.swift` ✅

### Core/Threading  
- `Core/Threading/ThreadingSafetyGuide.swift` ✅

## 프로토콜 정의 상태

### 완료된 프로토콜
- NotchWindowManagerProtocol ✅
- SystemHUDServiceProtocol ✅  
- BatteryServiceProtocol ✅
- BluetoothServiceProtocol ✅

### 미완성 프로토콜
- MediaServiceProtocol 🔴 (MediaServiceDelegate 누락)
- ShelfServiceProtocol 🔄

## Xcode 프로젝트 설정
- 타겟: SmartEdge (단일 타겟)
- 스키마: SmartEdge
- 빌드 설정: Debug/Release
- 플랫폼: macOS (arm64, x86_64)
- 최소 배포 타겟: macOS 14.0