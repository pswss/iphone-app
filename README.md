# 오늘 (Oneul)

> iOS 26 **Liquid Glass** 디자인의 아이폰 전용 일정 앱.
> 하루를 한 줄의 빛나는 타임라인으로. 잠금화면·다이나믹 아일랜드에 그날의 일정이 무지개 바로 떠오르고, 다음 일정까지 카운트다운이 실시간으로 흐릅니다.

---

## ✨ 주요 기능

### 일정 (애플 캘린더식 시간 그리드)
- **빈 곳 탭 → 추가**: 탭한 자리에 1시간짜리 미리보기 블록이 뜨고, 절반 높이 시트에서 바로 편집
- **꾹 눌러 이동 / 아래 손잡이 당겨 끝시간 조절**: 스크롤 중인 가벼운 터치는 무시되어 스크롤이 항상 우선
- **탭 = 하이라이트(빛나는 유리 효과) → 한 번 더 탭 = 편집**, 겹친 일정은 탭하면 맨 앞으로
- **위로 스크롤하면 타임라인 위젯이 접혀** 그리드가 넓어짐(아이폰)
- 멀티데이(종일) 일정, 반복 일정, 2차 알림

### Live Activity & 다이나믹 아일랜드
- 당일 일정을 시간순 색상 세그먼트(무지개 바)로, 전진하는 현재-시각 선 + 진행 중 일정 강조
- compact / expanded / minimal — 다음 일정 시각 + 라이브 카운트다운
- 카운트다운은 서버 없이 시스템이 자동 갱신

### AI 비서 (온디바이스)
- **Apple Intelligence(FoundationModels)** 기반 — 키·네트워크 불필요, 완전 온디바이스
- "내일 9시 팀 회의 추가, 금요일 약속 취소, 점심 1시로 옮겨줘" 같은 자연어로 일정 **생성·수정·삭제**
- **음성 입력**(받아쓰기)으로 말해서 일정 추가

### 학생 모드 (NEIS 연동)
- 학교 검색 → 학년·반 선택 → **시간표 가져오기**
- **선택과목 자동 판별**: 학년 전체 반을 분석해 "일부 반만 듣는 과목"을 선택과목으로 식별 → 체크 → 자동배치 → 미리보기에서 수정
- **학사일정** 자동 반영: 방학은 멀티데이 1개로, 시험·행사는 개별 일정. 방학·공휴일·시험일엔 수업 제외, 학기 끝까지만 생성
- **학년별 필터**: 내 학년에 해당하는 학사 알림만 표시
- **급식표**(날짜 슬라이드), **D-Day 카운트다운**(시험/수능)
- **일일 자동 갱신**: 앱 진입 시 학사일정·시간표를 멱등 재반영(2학기 데이터가 올라오면 자동 갱신)

### 그 외
- **한국어 / English 자동 현지화** (기기 언어 기준, 설정에서 변경 가능)
- 라이트(화이트) / 다크(남색) / 시스템 외형
- iCloud 동기화(SwiftData + CloudKit), 아이폰 ↔ 아이패드

---

## 🛠️ 기술 스택

- **UI**: SwiftUI (iOS 26), Liquid Glass
- **데이터**: SwiftData (+ iCloud / CloudKit), 앱↔위젯 App Group
- **Live Activity**: ActivityKit + WidgetKit
- **AI**: FoundationModels (Apple Intelligence, 온디바이스)
- **음성**: Speech (SFSpeechRecognizer) + AVAudioEngine
- **학사/급식**: NEIS 교육정보 개방 포털 Open API
- **알림**: UserNotifications (로컬)
- **프로젝트 생성**: [XcodeGen](https://github.com/yonigreenscape/XcodeGen) (`project.yml`)

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
| 실행 | iOS 26+ 기기/시뮬레이터 |
| AI·음성 | Apple Intelligence 지원 기기(온디바이스) |
| iCloud / Live Activity | Apple Developer Program |

### NEIS API 키 설정 (학생 기능)
학사일정·급식·시간표는 [NEIS 교육정보 개방 포털](https://open.neis.go.kr)의 무료 키가 필요합니다.
저장소의 `Oneul/Oneul/Features/School/NEIS.swift`에는 키가 빈 문자열(`""`)로 들어 있습니다 — 본인 키를 넣어 사용하세요.

```swift
enum NEISConfig {
    static let apiKey = "YOUR_NEIS_KEY"   // ← 본인 키
}
```

> 키 없이도 일정·AI·Live Activity 등 학생 기능 외 모든 기능은 동작합니다.

---

## 📁 프로젝트 구조

```
Oneul/
├── project.yml                 # XcodeGen 스펙
├── Oneul/
│   ├── RootView.swift
│   ├── Design/                 # 외형·언어·공통 UI (AppChrome 등)
│   ├── Models/                 # ScheduleEvent, DayPlan, Holidays …
│   └── Features/
│       ├── Today/              # 시간 그리드·타임라인·D-Day
│       ├── Editor/             # 일정 편집
│       ├── AI/                 # Apple Intelligence·음성
│       ├── School/             # NEIS 시간표·급식·선택과목
│       └── Settings/
├── OneulWidget/                # Live Activity / 다이나믹 아일랜드
└── Shared/                     # 앱↔위젯 공유
```

---

## 📄 라이선스

미정 (Private).
