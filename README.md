# 하루 (Haru)

> 표시 이름은 **하루**, 코드명·번들은 `Oneul` / `com.oneul.app`.
> iOS 26 **Liquid Glass** 디자인의 아이폰 일정 앱.
> 하루를 한 줄의 빛나는 타임라인으로. 잠금화면·다이나믹 아일랜드·애플워치에 그날의 일정이 무지개 바로 떠오르고, 다음 일정까지 카운트다운이 흐릅니다.

---

## ✨ 주요 기능

### 일정 (애플 캘린더식 시간 그리드)
- **빈 곳 탭/꾹 → 추가**: 그 자리에 미리보기 블록이 뜨고, 절반 높이 시트에서 바로 편집
- **꾹 눌러 이동 / 위·아래 손잡이 당겨 시작·끝시간 조절**: 스크롤 중인 가벼운 터치는 무시되어 스크롤이 항상 우선, 가장자리에 대면 자동 스크롤
- **탭 = 하이라이트(빛나는 유리) → 한 번 더 탭 = 편집**, 겹친 일정은 탭하면 맨 앞으로
- **컨텍스트 메뉴**(꾹 눌렀다 떼기): 잘라내기·복사·복제·삭제 — 기기 언어로 표시
- **날짜 이동**: 좌우 스와이프 또는 줄 캘린더 탭(슬라이드), 날짜 바꿔도 스크롤 위치 유지
- **위로 스크롤하면 타임라인이 접혀** 그리드가 넓어짐
- 멀티데이(종일) 일정, 반복 일정, 2차 알림, 8개+ 일정 시 중간색 보간(빨강→보라)

### Live Activity · 다이나믹 아일랜드 · 애플워치
- 당일 일정을 시간순 색상 세그먼트(무지개 바)로, 전진하는 현재-시각 선 + 진행 중 일정 강조
- compact / expanded / minimal — 다음 일정 시각 + 카운트다운, 진행 중 표시
- 오늘이 비면 **가장 가까운 일정 있는 날**을 표시
- **애플워치 앱**(WatchConnectivity로 오늘 일정 전송)
- 서버 없이: 카운트다운은 시스템 자동 갱신, needle·현재일정은 앱 사용·일정 변경·백그라운드 작업(BGTask) 시 갱신

### AI 비서 (온디바이스)
- **Apple Intelligence(FoundationModels)** 기반 — 키·네트워크 불필요, 완전 온디바이스
- "내일 9시 팀 회의 추가, 금요일 약속 취소, 점심 1시로 옮겨줘" 같은 자연어로 **생성·수정·삭제** (미리보기 후 적용)
- 의미 슬롯만 모델이 채우고 **날짜·시각은 Swift가 결정론적으로 계산** → 작은 모델이어도 날짜 정확
- 큰 입력은 자동으로 조각조각 나눠 처리(날짜 맥락 이어받기), **음성 입력**(받아쓰기) 지원

### 학생 모드 (NEIS 연동)
- 학교 검색 → 학년·반 선택 → **시간표 가져오기**
- **선택과목 자동 판별**: 학년 전체 반을 분석해 "일부 반만 듣는 과목"을 선택과목으로 식별 → 체크 → 자동배치 → 미리보기에서 수정. 잘못 잡힌 과목은 **길게 눌러 공통으로 빼기**(영구 저장)
- **학사일정** 자동 반영: 방학은 멀티데이 1개로, 시험·행사는 개별 일정. 방학·공휴일·시험일(지필평가 포함)엔 수업 제외, 학기 끝까지만 생성
- **학년별 필터**(내 학년 학사 알림만), **급식표**(날짜 슬라이드), **D-Day**(시험/수능)
- **자동 갱신**: 앱 진입·백그라운드 작업 시 학사일정·시간표 멱등 재반영(2학기 자동 반영)

### 그 외
- **한국어 / English** 자동 현지화(기기 언어 기준)
- 라이트(화이트) / 다크(남색) / 시스템 외형
- 일정 장소 **길찾기**(네이버 지도 `nmap://` URL), 공휴일(양력 + 음력 설날·추석·부처님오신날)

---

## 🛠️ 기술 스택

- **UI**: SwiftUI (iOS 26), Liquid Glass / UIPageViewController(날짜 페이저)
- **데이터**: SwiftData (로컬)
- **위젯/워치 전달**: ActivityKit ContentState 푸시 + WatchConnectivity (App Group 없이 동작)
- **Live Activity**: ActivityKit + WidgetKit, 백그라운드 갱신 BGTaskScheduler
- **AI**: FoundationModels (Apple Intelligence, 온디바이스)
- **음성**: Speech (SFSpeechRecognizer) + AVAudioEngine
- **학사/급식**: NEIS 교육정보 개방 포털 Open API
- **워치**: watchOS 11, WatchConnectivity
- **프로젝트 생성**: [XcodeGen](https://github.com/yonigreenscape/XcodeGen) (`project.yml`)

> 외부 라이브러리 의존성 없음(순수 Apple 프레임워크). XcodeGen은 빌드 도구.

---

## ⚙️ 빌드

```bash
brew install xcodegen          # 최초 1회
cd Oneul
xcodegen generate              # project.yml → Oneul.xcodeproj 생성
open Oneul.xcodeproj           # Xcode 26+ 에서 빌드/실행
```

| 항목 | 요구 |
|---|---|
| 개발 환경 | **Xcode 26+** (iOS 26 SDK) |
| 실행 | iOS 26+ 기기/시뮬레이터, watchOS 11+ |
| AI·음성 | Apple Intelligence 지원 기기(온디바이스) |
| Live Activity / 푸시 / 워치 | Apple Developer Program(유료) |

### NEIS API 키 설정 (학생 기능)
학사일정·급식·시간표는 [NEIS 교육정보 개방 포털](https://open.neis.go.kr)의 무료 키가 필요합니다.
저장소의 `Oneul/Oneul/Features/School/NEIS.swift`에는 키가 빈 문자열(`""`)로 들어 있습니다 — 본인 키를 넣어 사용하세요.

```swift
enum NEISConfig {
    static let apiKey = "YOUR_NEIS_KEY"   // ← 본인 키
}
```

> NEIS 데이터 출처: 교육부·한국교육학술정보원 「나이스(NEIS) 교육정보 개방 포털」. 데이터는 출처 표시 조건으로 자유이용이 허락됩니다.
> 키 없이도 일정·AI·Live Activity 등 학생 기능 외 모든 기능은 동작합니다.

---

## 📁 프로젝트 구조

```
Oneul/
├── project.yml                 # XcodeGen 스펙(앱 + 위젯 + 워치)
├── Oneul/
│   ├── RootView.swift
│   ├── Design/                 # 외형·언어·공통 UI (AppChrome 등)
│   ├── Models/                 # ScheduleEvent, DayPlan, Holidays …
│   ├── LiveActivity/           # 컨트롤러·백그라운드 갱신
│   ├── Watch/                  # WatchConnectivity 송신
│   └── Features/
│       ├── Today/              # 시간 그리드·타임라인·D-Day
│       ├── Editor/             # 일정 편집·길찾기
│       ├── AI/                 # Apple Intelligence·음성
│       ├── School/             # NEIS 시간표·급식·선택과목
│       └── Settings/
├── OneulWidget/                # Live Activity / 다이나믹 아일랜드
├── OneulWatch/                 # watchOS 앱
└── Shared/                     # 앱↔위젯↔워치 공유 값 타입
```

---

## 📄 라이선스

미정 (Private). NEIS 데이터는 위 출처 표시 조건을 따릅니다.
