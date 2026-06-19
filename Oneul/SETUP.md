# 오늘 (Oneul) — Xcode 셋업 가이드

이 폴더에는 `xcodegen`으로 생성된 **`Oneul.xcodeproj`**와 전체 SwiftUI 소스가 들어 있습니다.
아래 순서대로 하면 시뮬레이터에서 실행됩니다. (Swift 좀 해본 분 기준, 막히면 단계 번호로 물어보세요.)

> ⚠️ 저(Claude)는 이 맥에 Xcode가 없어 **빌드/실행은 못 했습니다.** 코드는 꼼꼼히 작성했지만,
> 처음 빌드 시 서명/캐퍼빌리티 관련 소소한 설정은 Xcode에서 한 번 잡아줘야 할 수 있어요.

---

## 0. 준비물
- **Xcode 26+** (App Store에서 설치, iOS 26 SDK 포함)
- iCloud 동기화·위젯 데이터 공유까지 쓰려면 **Apple Developer Program($99/년)**.
  무료 계정도 빌드/실행은 되지만 iCloud는 자동으로 **로컬 전용**으로 떨어집니다.

## 1. 프로젝트 열기
```bash
open "Oneul.xcodeproj"
```
> 소스를 추가/삭제하거나 `project.yml`을 바꾸면, 이 폴더에서 `xcodegen generate`를 다시 돌리세요.

## 2. 서명(Signing) — 두 타깃 모두
좌측 네비게이터 최상단 **Oneul** 프로젝트 클릭 → TARGETS에서 **각각** 설정:

1. **Oneul** (앱) → *Signing & Capabilities* 탭
   - **Team**: 본인 팀 선택
   - **Bundle Identifier**: 기본 `com.oneul.app`. 이미 쓰는 ID면 충돌하니, 본인만의 값으로 바꾸세요(예: `com.<당신>.oneul`).
2. **OneulWidget** (위젯) → 같은 방식. Bundle ID는 **앱 ID 뒤에 `.widget`** 형태로(예: `com.<당신>.oneul.widget`).

> Bundle ID 접두사를 바꿨다면 아래 4가지도 함께 맞춰야 합니다(전부 같은 접두사):
> App Group `group.<...>`, iCloud 컨테이너 `iCloud.<...>`, `Oneul.entitlements`, `OneulWidget.entitlements`.
> 처음엔 **그냥 기본값(com.oneul.app)으로 두고 Team만 선택**하는 게 가장 쉽습니다.

## 3. 캐퍼빌리티 확인
entitlements 파일에 이미 설정돼 있어, 자동 서명이면 Xcode가 대부분 잡아줍니다. *Signing & Capabilities*에서 확인:

- **Oneul (앱)**: `iCloud` → **CloudKit** 체크 + 컨테이너 `iCloud.com.oneul.app`,
  `App Groups` → `group.com.oneul.app`.
- **OneulWidget**: `App Groups` → `group.com.oneul.app`.

> 무료 계정이면 iCloud/App Groups 캐퍼빌리티가 막혀 있을 수 있어요. 그땐 앱이 **로컬 저장**으로 동작합니다(정상).
> 빨간 에러가 나면 해당 캐퍼빌리티의 컨테이너/그룹을 `+`로 추가하거나, 막혔으면 일단 무시하고 로컬로 실행하세요.

## 4. 실행
- 상단 기기 선택에서 **iPhone 15 Pro**(또는 16 Pro) 시뮬레이터 선택 → ▶︎ Run.
  - 다이나믹 아일랜드는 **Pro 모델**에서만 보입니다.
- 앱이 뜨면 **오늘** 탭에서 ＋로 일정을 몇 개 추가(시간은 **오늘**로).

## 5. Live Activity / 다이나믹 아일랜드 보기
- 오늘 일정이 있으면 자동으로 Live Activity가 시작됩니다.
- **잠금화면**: 시뮬레이터에서 `Cmd+L`(또는 Device ▸ Lock) → 무지개 바 + 카운트다운 확인.
- **다이나믹 아일랜드**: 홈으로 나가면(스와이프 업) 상단 알약에 다음 일정/카운트다운 표시.
- 처음엔 시스템 알림 권한과 "Live Activities 허용"이 필요할 수 있어요(설정 ▸ 오늘 ▸ Live Activities).

## 6. AI(Claude) 일정 생성
1. **설정** 탭 → Anthropic API 키 입력 후 저장(기기 Keychain에 저장됨).
2. **AI** 탭 → "내일 9시 회의, 12시 반 점심, 3시 헬스장 1시간…"처럼 입력 → **Claude로 일정 만들기**.
3. 생성된 일정 확인 후 **전체 추가** → 오늘 탭/타임라인에 반영.

> 키가 없으면 AI 탭에서 안내가 뜹니다. 키는 코드/리포에 들어가지 않습니다.

---

## 디자인: Liquid Glass 전환(선택)
현재 글래스 카드는 어디서나 안정적으로 컴파일되도록 **`.ultraThinMaterial`** 기반입니다.
iOS 26의 진짜 Liquid Glass로 바꾸려면 **한 파일만** 고치면 됩니다 — `Oneul/Design/Glass.swift`의
`GlassCard.body`를:
```swift
content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
```
로 교체하고, 배포 타깃을 **iOS 26.0**으로 올리세요(프로젝트 설정 또는 `project.yml`의 `deploymentTarget`).

## 알려진 한계 (설계상)
- 앱을 **오래 닫아두면** 무지개 바의 "현재 칸 강조"가 다음 칸으로 자동 전환되는 정밀도는 떨어집니다
  (카운트다운/진행선은 시스템이 계속 갱신). 앱 진입/알림 탭 시 즉시 보정됩니다.
  완전 자동화는 향후 **APNs 푸시 서버**로 보강(범위 밖).
- iCloud 동기화는 **유료 개발자 계정**에서 캐퍼빌리티가 켜져 있어야 동작합니다.

## 폴더 구조
```
Oneul/
├── project.yml            # XcodeGen 정의 (소스 추가 후 `xcodegen generate`)
├── Oneul.xcodeproj        # 생성된 프로젝트
├── Oneul.entitlements / OneulWidget.entitlements
├── Generated/             # 자동 생성 Info.plist (건드릴 필요 없음)
├── Shared/                # 앱·위젯 공통 (Live Activity 속성, 무지개 팔레트)
├── Oneul/                 # 앱 타깃
│   ├── OneulApp.swift, RootView.swift
│   ├── Models/ (ScheduleEvent, DayPlan)
│   ├── Persistence/ (SwiftData + CloudKit)
│   ├── Design/ (Theme, Glass, 배경)
│   ├── Features/Today · Editor · Settings · AI
│   ├── LiveActivity/ (LiveActivityController)
│   └── Notifications/
└── OneulWidget/           # 위젯 확장 (Live Activity + 다이나믹 아일랜드)
```
