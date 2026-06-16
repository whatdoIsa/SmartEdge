# SmartEdge 프로젝트 메모리

## 프로젝트 개요
- **이름**: SmartEdge (BoringNotch 클론)
- **타입**: macOS 노치 유틸리티 앱  
- **기술스택**: SwiftUI + AppKit, MVVM + Coordinator + Service Layer
- **타겟**: macOS 14 Sonoma+, Apple Silicon + Intel
- **아키텍처**: Protocol-first 설계, 의존성 역전 원칙

## 현재 진행상황 (2026-05-22)
- **Phase**: 중급 구현 단계 (Core 서비스 통합)
- **상태**: NotchWindowManager 완성, 빌드 에러 감소 중 
- **마지막 작업**: ServiceContainer 순환 의존성 해결
- **현재 빌드 에러**: ~10개 (초기 23개에서 감소)

## 해결된 주요 문제들 ✅
1. **NotchView 초기화 에러**: viewModel 파라미터 문제 해결
2. **ServiceContainer 순환 의존성**: lazy initialization으로 해결
3. **SystemHUDService 프로토콜 준수**: 인터페이스 정합성 확보
4. **Preview 에러들**: SwiftUI 미리보기 관련 수정
5. **NotchWindowManager**: NSWindow 커스텀화 완료

## 현재 남은 빌드 에러들 🔴

### 1. MediaServiceAdapter 관련 (우선순위: 높음)
```
MediaServiceAdapter.swift:4:59: error: 'MediaServiceDelegate' is not a member type
MediaServiceAdapter.swift:75:27: error: cannot find type 'MediaData' in scope
MediaServiceAdapter.swift:8:13: error: type 'MediaServiceAdapter' does not conform to protocol 'MediaServiceProtocol'
```
**원인**: MediaServiceDelegate와 MediaData 타입 정의 누락
**해결방안**: 프로토콜 정의 완성 및 타입 통합

### 2. NotchWindowService override 문제 (우선순위: 중간)
```
NotchWindowService.swift:176:19: error: method does not override any method from its superclass
NotchWindowService.swift:182:19: error: method does not override any method from its superclass
NotchWindowService.swift:188:19: error: method does not override any method from its superclass
```
**원인**: 상속 관계에서 부모 클래스 메서드와 불일치
**해결방안**: 상속 구조 재검토 및 메서드 시그니처 정정

### 3. Threading/MainActor 경고들 (우선순위: 낮음)
```
warning: conformance crosses into main actor-isolated code and can cause data races
```
**원인**: Swift 6 language mode의 엄격한 MainActor 분리
**해결방안**: @MainActor 어노테이션 추가 및 비동기 처리 개선

### 4. ShelfService 관련 (우선순위: 낮음)
- FileType/QLPreviewPanel 에러들
- QuickLook 프레임워크 통합 문제

## 아키텍처 완성도

### Core/Services/ (80% 완성)
- ✅ NotchWindowManager: 완료
- ✅ SystemHUDService: 완료
- ✅ BatteryService, BluetoothService: 완료
- 🔴 MediaService/MediaServiceAdapter: 에러 있음
- 🔄 ShelfService: 부분적 에러

### Features/ (60% 완성)
- ✅ Notch/: View-ViewModel 연결 완료
- ✅ MusicPlayer/: 기본 구조 완료 (MediaService 의존성 대기)
- ✅ HUD/: 기본 구조 완료
- 🔄 Shelf/: ShelfService 의존성 대기
- ✅ Calendar/: 완료
- ✅ Settings/: 완료

### Shared/ (90% 완성)
- ✅ Components/: 재사용 SwiftUI 컴포넌트들
- ✅ Models/: 공유 데이터 모델
- ✅ Constants/: 앱 전역 상수

### Settings/ (95% 완성)
- ✅ 모든 설정 패널 완료
- ✅ SettingsView/ViewModel 완료

## 우선순위 해결 작업

### 1단계: Core 에러 해결
1. **MediaServiceAdapter 의존성/타입 에러 해결**
   - MediaServiceDelegate 프로토콜 정의
   - MediaData 모델 생성
   - 프로토콜 준수 관계 정정

2. **NotchWindowService 상속 문제 수정**
   - 부모 클래스와 메서드 시그니처 일치
   - override 키워드 정정

### 2단계: Framework 통합
3. **MediaRemote 프레임워크 통합**
   - Private framework 동적 로딩 구현
   - Runtime symbol loading 처리

4. **ShelfService FileType 에러 수정**
   - QuickLook 프레임워크 올바른 통합
   - FileType 열거형 정의

### 3단계: 품질 개선  
5. **Swift 6 MainActor isolation 경고 해결**
   - @MainActor 어노테이션 체계적 적용
   - 비동기 처리 개선

## 기술적 도전 과제

### 해결해야 할 시스템 레벨 이슈
- **MediaRemote**: Private framework, 직접 import 불가 → 동적 로딩 필요
- **IOKit HUD 인터셉트**: macOS 버전별 동작 차이 존재
- **NSWindow level 설정**: .screenSaver 레벨 필요, entitlements 확인
- **XPC Helper**: 향후 권한 분리를 위한 별도 타겟 (향후 작업)

### 성능 고려사항
- 노치 hover 감지 최적화
- 미디어 정보 실시간 업데이트 효율성
- 메모리 관리 (특히 이미지/음악 메타데이터)

## 다음 세션 복구 가이드

### 프로젝트 재시작 시 확인사항
1. **현재 브랜치**: main 브랜치에서 작업 중
2. **Xcode 프로젝트**: SmartEdge.xcodeproj 열기
3. **빌드 타겟**: macOS (arm64/x86_64)
4. **에러 확인**: `xcodebuild -project SmartEdge.xcodeproj -scheme SmartEdge build`

### 우선 해결 파일들
- `SmartEdge/Core/Services/MediaServiceAdapter.swift`
- `SmartEdge/Core/Services/NotchWindowService.swift`  
- `SmartEdge/Shared/Models/` (MediaData 모델 추가 필요)
- `SmartEdge/Core/Services/Protocols/` (프로토콜 정리 필요)

### 아키텍처 원칙 준수
- Dependency Direction: View → ViewModel → Service → System API
- Protocol-first 설계 유지
- 파일당 하나의 타입 원칙
- `@MainActor` UI 업데이트 필수 명시

## 프로젝트 성공 기준
- [ ] 빌드 에러 0개 달성
- [ ] 기본 노치 표시 및 호버 반응 구현
- [ ] 음악 재생 정보 표시 및 컨트롤
- [ ] 시스템 HUD 인터셉트 (볼륨/밝기)
- [ ] 기본 설정 UI 완성
- [ ] macOS 14+ 안정적 동작

**마지막 업데이트**: 2026-05-22 19:56 KST