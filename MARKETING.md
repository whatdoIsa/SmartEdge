# SmartEdge — 마케팅 자료 가이드

## 1. 앱 아이콘

### 디자인 사양
- 형식: macOS `.icns` (Asset Catalog `AppIcon.appiconset`)
- 필요 크기: 16, 32, 64, 128, 256, 512, 1024 (각 1x + 2x)
- 컬러 모드: sRGB
- 모서리: macOS가 자동 둥글림 — squircle mask 미리 적용 금지

### 디자인 방향
CLAUDE.md 명시 디자인 철학 (TOSS / Airbnb / Tinder)에 기반:
- **TOSS 미니멀**: 단순한 기하학적 모티프, 글래스/그라데이션 과용 금지
- **Airbnb 따뜻함**: 차가운 회색/검정 단색보다 살짝 따뜻한 톤
- **Tinder 직관성**: 한눈에 "노치/엣지/연결" 의미가 전달되어야

### 시도해볼 컨셉
1. **노치 실루엣 + 미니 카드** — 검정 둥근 노치 모양 안에 작은 흰색 카드(콘텐츠 표현)
2. **그라데이션 칼날(Edge)** — 화면 상단의 엣지(edge)를 추상화. SmartEdge 이름과 호응
3. **음표 + 노치** — 음악 컨트롤이 핵심 기능이라 명확. 다만 음악 앱으로 오인 위험

추천: **1번** (노치 실루엣). 앱의 정체성을 가장 직설적으로 표현.

### 도구
- Figma (무료) — 빠른 iteration, vector export
- Sketch — macOS native, .icns plugin 풍부
- Bakery / Iconmaker 같은 macOS 전용 앱

---

## 2. App Store / 랜딩 페이지 스크린샷

### 필요 사이즈
**Mac App Store** (필수):
- 1280×800, 1440×900, 2560×1600, 2880×1800 중 1세트 (5장 권장)
- 화면 비율 16:10

**랜딩 페이지** (선택):
- 1920×1200 hero
- 1440×900 feature carousel

### 스크린샷 컨텐츠 가이드 (5장 기준)
1. **Hero — 음악 컨트롤 노치 확장**: 인기 트랙 재생 중 노치가 펴진 모습. 캡션: "당신의 노치, 새로운 컨트롤 센터"
2. **HUD intercept**: F11 누른 순간 노치에 슬라이더 표시. 캡션: "거슬리는 시스템 HUD, 노치 안으로"
3. **Calendar**: 1시간 내 다가오는 일정이 노치에 떠 있는 모습. 캡션: "다음 일정, 한눈에"
4. **Shelf drag-drop**: Finder에서 파일을 노치로 드래그하는 순간. 캡션: "잠시 보관할 파일, 노치에 던지세요"
5. **Settings 패널**: 깔끔한 설정 화면. 캡션: "당신의 노치, 당신의 방식"

### 촬영 팁
- 시스템 모드 라이트 + 다크 둘 다 준비 (사용자 환경 따라 다름)
- 배경 wallpaper는 단순한 그라데이션 (Big Sur "Color" 시리즈 추천 — Apple 마케팅과 톤 일치)
- 메뉴바 아이콘은 항상 보이게 (앱 정체성)
- 노치는 카메라 노치와 정확히 정렬된 모습 강조

---

## 3. 랜딩 페이지 카피라이팅 초안

### Hero
> **노치, 이제 단순한 카메라가 아닙니다.**
> SmartEdge는 MacBook 노치를 음악, 알림, 캘린더, 파일을 한곳에서 다루는 마이크로 워크스페이스로 바꿉니다.

### Feature 1 — Music
> **재생 중인 음악을 노치 위에.**
> Apple Music, YouTube, Spotify — 어디서 재생하든 노치 위에 트랙 정보가 떠오릅니다. 호버 한 번으로 컨트롤 + 가사. (Spotify는 별도 연동 — 추후 지원 예정)

### Feature 2 — System HUD
> **볼륨/밝기, 화면 가운데서 가리지 않게.**
> 시스템 기본 HUD는 항상 작업 중인 화면을 덮습니다. SmartEdge는 그 자리를 노치로 옮겨 시야를 비웁니다.

### Feature 3 — Calendar
> **다음 회의, 노치에서 알려드립니다.**
> 캘린더와 자동 동기화. 회의 시작 직전에 노치가 살짝 펴지면서 알려줍니다. 놓치지 않으면서도, 강요하지 않게.

### Feature 4 — Shelf
> **잠시 둘 곳이 필요한 파일, 노치에.**
> Finder에서 노치로 파일을 끌어다 놓으세요. AirDrop, 메시지, 클립보드 — 어디로든 한 번에 보낼 수 있습니다.

### Pricing
> **무료로 시작하세요.**
> SmartEdge는 기본 기능 무료. 추후 Pro 플랜은 사용자 의견을 모은 뒤 결정합니다.

### Footer CTA
> **MacBook Pro / Air (M1 이상)에서 사용 가능합니다.**
> [다운로드] — macOS 13 Ventura 이상

---

## 4. App Store Metadata

### 앱 이름
- Display: **SmartEdge**
- Subtitle (30자): "노치를 워크스페이스로"
- Bundle: `com.smartedge.app`

### 카테고리
- Primary: Productivity
- Secondary: Utilities

### Keywords (영문, 쉼표 구분, 100자)
notch, menubar, hud, music, calendar, shelf, airdrop, productivity, macbook, focus

### 한국어 설명 (단축, App Store description 한국어 필드)
> SmartEdge는 MacBook 노치를 음악 컨트롤, 시스템 HUD, 캘린더, 파일 보관함을 모아놓은 마이크로 워크스페이스로 바꿔주는 macOS 메뉴바 앱입니다.
>
> **주요 기능**
> · 음악 컨트롤 — 재생 중인 곡 정보 + 컨트롤 (Apple Music / YouTube / 시스템 미디어)
> · 시스템 HUD — 볼륨/밝기/키보드 백라이트를 노치로
> · 캘린더 — 다가오는 일정 알림
> · 선반 — 드래그 한 번으로 파일 임시 보관 + AirDrop / 메시지 공유
>
> **요구 사항**
> · macOS 13 Ventura 이상
> · Apple Silicon 권장 (Intel Mac도 지원, 노치 없는 모델은 메뉴바 모드)

### 한국어 키워드 (선택)
노치, 메뉴바, 음악, 캘린더, 클립보드, AirDrop, 생산성

---

## 5. PR / 소셜 자료 (선택)

### Twitter / X 초기 트윗
> SmartEdge가 베타 출시되었습니다.
> MacBook 노치를 음악 컨트롤, 시스템 HUD, 캘린더, 파일 선반으로 쓸 수 있는 메뉴바 유틸리티입니다.
> 다운로드: [링크]
> #macOS #IndieDev

### Product Hunt 등록 시 콘텐츠
- Tagline (60자): "Turn your MacBook notch into a productivity hub"
- 첫 댓글 (maker comment): 개발 동기 + 베타 피드백 요청

---

## 6. 출시 전 체크리스트

- [ ] AppIcon.appiconset 1024×1024 마스터 + 모든 크기 export
- [ ] 5장 스크린샷 (라이트/다크 각 1세트)
- [ ] 랜딩 페이지 hero copy + 4개 feature copy 확정
- [ ] App Store metadata (이름, 부제, 키워드, 설명) 입력
- [ ] 한국어/영어 카피 검수 (외부 리뷰 권장)
- [ ] 첫 Twitter/PH 게시물 초안

---

*이 문서는 LLM이 자동 생성한 초안입니다. 실제 카피/디자인은 사용자 검수 후 사용해주세요.*
