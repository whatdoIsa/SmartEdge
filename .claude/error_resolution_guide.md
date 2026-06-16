# 에러 해결 가이드

## 현재 빌드 에러 분석 및 해결 방안

### 1. MediaServiceAdapter 에러들 (최고 우선순위)

#### 에러 1: MediaServiceDelegate 타입 미정의
```
error: 'MediaServiceDelegate' is not a member type of protocol 'SmartEdge.MediaServiceProtocol'
```
**파일**: `MediaServiceAdapter.swift:4`
**해결방안**:
```swift
// Core/Services/Protocols/MediaServiceProtocol.swift에 추가 필요
protocol MediaServiceDelegate: AnyObject {
    func mediaPlaybackStateDidChange(_ isPlaying: Bool)
    func mediaInfoDidChange(_ mediaInfo: MediaData?)
}

// MediaServiceProtocol 내부에 typealias 추가
protocol MediaServiceProtocol {
    typealias MediaServiceDelegate = SmartEdge.MediaServiceDelegate
    // ... 기존 내용
}
```

#### 에러 2: MediaData 타입 누락
```
error: cannot find type 'MediaData' in scope
```
**파일**: `MediaServiceAdapter.swift:75, 78, 89`
**해결방안**: `Shared/Models/MediaData.swift` 생성
```swift
struct MediaData {
    let title: String?
    let artist: String?
    let album: String?
    let artwork: NSImage?
    let duration: TimeInterval
    let currentTime: TimeInterval
    let isPlaying: Bool
}
```

#### 에러 3: 프로토콜 준수 실패
```
error: type 'MediaServiceAdapter' does not conform to protocol 'MediaServiceProtocol'
```
**해결방안**: MediaServiceAdapter에서 누락된 메서드들 구현

### 2. NotchWindowService override 에러들

#### 에러 패턴
```
error: method does not override any method from its superclass
```
**파일**: `NotchWindowService.swift:176, 182, 188`

**분석**: NotchWindowService가 상속하는 부모 클래스에 해당 메서드가 없음
**해결방안**:
1. 부모 클래스 확인 후 메서드 시그니처 맞추기
2. 또는 override 키워드 제거하고 새로운 메서드로 정의

### 3. MainActor 경고들 (Swift 6 호환성)

#### 경고 패턴
```
warning: conformance crosses into main actor-isolated code and can cause data races
```

**해결방안**:
```swift
// 클래스 레벨에서 @MainActor 지정
@MainActor
class MediaService: MediaServiceProtocol {
    // 구현
}

// 또는 개별 메서드에 적용
nonisolated func someBackgroundMethod() async {
    // 백그라운드 작업
}
```

### 4. ShelfService 관련 에러들

#### FileType 관련 에러
**원인**: QuickLook 프레임워크 import 및 타입 정의 문제
**해결방안**:
```swift
import QuickLook
import UniformTypeIdentifiers

// FileType 열거형 정의
enum FileType: String, CaseIterable {
    case image, document, video, audio, archive
    
    var utType: UTType {
        switch self {
        case .image: return .image
        case .document: return .plainText
        case .video: return .movie
        case .audio: return .audio
        case .archive: return .archive
        }
    }
}
```

## 해결 작업 순서

### Phase 1: 타입 정의 완성 (30분)
1. `Shared/Models/MediaData.swift` 생성
2. `Core/Services/Protocols/MediaServiceDelegate.swift` 정의
3. MediaServiceProtocol에 typealias 추가

### Phase 2: 프로토콜 준수 수정 (45분)  
1. MediaServiceAdapter의 누락 메서드 구현
2. MediaService와 MediaServiceAdapter 간 타입 일치
3. delegate 설정 로직 수정

### Phase 3: 상속 관계 정정 (30분)
1. NotchWindowService 부모 클래스 확인
2. override 메서드들의 시그니처 맞추기
3. 불필요한 override 키워드 제거

### Phase 4: MainActor 정리 (15분)
1. UI 관련 클래스들에 @MainActor 추가
2. 백그라운드 작업은 nonisolated로 분리
3. async/await 패턴 일관성 확보

## 테스트 전략

### 빌드 검증
```bash
xcodebuild -project SmartEdge.xcodeproj -scheme SmartEdge build
```

### 기능 검증 체크리스트
- [ ] 앱 실행 (크래시 없음)
- [ ] 노치 창 표시 확인
- [ ] 호버 반응 테스트  
- [ ] 설정 패널 열기 확인
- [ ] 미디어 정보 표시 (기본 더미 데이터라도)

## 코딩 스탠다드 준수사항

### 필수 지켜야 할 원칙
- Dependency Direction: View → ViewModel → Service → System API
- Protocol-first 설계 유지
- 파일당 하나의 타입 원칙 
- `@MainActor` UI 업데이트 필수
- `async/await` 사용, completion handler 금지
- `guard let` 우선, `if let` 중첩 금지

### 금지사항
- 불필요한 주석 추가
- 이모티콘 사용
- 역방향 의존성 생성
- completion handler 패턴 사용