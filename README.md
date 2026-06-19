# 오늘 (Oneul) — 스케줄 & Live Activity

> 작업 제목(working title). iOS 26 **Liquid Glass** 디자인의 아이폰 전용 일정 앱.
> 일정이 있는 당일, **잠금화면과 다이나믹 아일랜드에 그날의 일정이 무지개 바로 떠오르고**, 다음 일정까지 카운트다운이 실시간으로 흐릅니다.

<p align="center"><i>일정을 입력하면, 오늘 하루가 한 줄의 빛나는 타임라인이 됩니다.</i></p>

---

## ✨ 주요 기능

| | 기능 | 설명 |
|---|---|---|
| 📅 | **스케줄 관리** | 일정 추가·수정·삭제, 주간/오늘 보기 (SwiftData) |
| 🌈 | **무지개 Live Activity 바** | 당일 일정을 시간 순 색상(빨→보) 세그먼트로, 전진하는 현재-시각 선 + 진행 중 일정 강조 |
| 🏝️ | **다이나믹 아일랜드** | compact/expanded/minimal — 다음 일정 시각 + 라이브 카운트다운 |
| 🧊 | **Liquid Glass UI** | iOS 26 `glassEffect` 기반의 애플식 반투명 디자인. 라이트=화이트 / 다크=남색 포인트 |
| ☁️ | **iCloud 동기화** | 아이폰 ↔ 아이패드 일정·알림 공유 (SwiftData + CloudKit) |
| 🤖 | **AI 일정 생성 (Claude)** | "내일 9시 회의, 점심 12시 반…" 자연어를 말하면 Claude가 일정표로 변환 |
| 🔔 | **로컬 알림** | 일정 시작 전 알림 (서버 불필요) |

> **다음 일정 카운트다운은 서버 없이** `Text(timerInterval:)` / `ProgressView(timerInterval:)`로 시스템이 자동 갱신합니다.
> 앱을 장시간 닫아둔 채 "강조 칸 자동 전환"까지 100% 정밀하게 하려면 향후 APNs 푸시 서버를 덧붙입니다(범위 밖).

---

## 🎨 디자인 미리보기 (Phase 0)

실제 앱 제작 전, 전체 디자인을 **버릴 용도의 웹 목업**으로 만들어 빠르게 검토합니다.

```bash
cd mockup
python3 -m http.server 8765
# 브라우저에서 http://localhost:8765
```

목업에 담긴 화면: ① 메인 스케줄 ② 일정 추가 시트 ③ 잠금화면 무지개 바 ④ 다이나믹 아일랜드 3상태 ⑤ AI(Claude) 일정 생성.
무지개 바의 전진하는 선·현재 칸 강조는 하루를 빠르게 돌려 애니메이션으로 보여줍니다.

---

## 🛠️ 기술 스택

- **UI**: SwiftUI (iOS 26), Liquid Glass (`glassEffect`, `GlassEffectContainer`)
- **데이터**: SwiftData + iCloud(CloudKit) 동기화, 앱↔위젯 공유용 App Group
- **Live Activity**: ActivityKit + WidgetKit (Widget Extension 타깃)
- **알림**: UserNotifications (로컬)
- **AI**: Claude API (Anthropic) — 자연어 → 구조화된 일정. 모델 `claude-opus-4-8`

### Claude 연동 메모
Swift용 공식 Anthropic SDK가 없어 **REST(`POST https://api.anthropic.com/v1/messages`)**로 직접 호출합니다.
- 헤더: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`
- 구조화 출력(`output_config.format` JSON Schema)으로 일정 배열을 받아 SwiftData에 저장
- **API 키는 코드에 넣지 않고 기기 Keychain에 저장**. 정식 배포 시엔 키 노출을 막는 중계 서버 방식이 더 안전(향후).

---

## ⚙️ 요구 사항

| 항목 | 요구 |
|---|---|
| 개발 환경 | **Xcode 26+** (iOS 26 SDK), macOS 26+ |
| 실행 기기/시뮬레이터 | iOS 26+. 다이나믹 아일랜드 미리보기는 iPhone 15 Pro 등 |
| iCloud 동기화 | **Apple Developer Program ($99/년)** — CloudKit·App Group 사용에 필요 |
| AI 기능 | Anthropic API 키 |

> ⚠️ 이 저장소에는 아직 빌드 산출물이 없습니다. 소스를 Xcode에서 열어 빌드/실행합니다(단계별 안내 제공 예정).

---

## 🗺️ 로드맵

- [x] **Phase 0** — Liquid Glass 디자인 목업(웹, localhost)
- [ ] **Phase 1** — Xcode 프로젝트 스캐폴드 (SwiftUI 앱 + Widget Extension, SwiftData + CloudKit, App Group)
- [ ] **Phase 2** — 일정 관리 UI + Liquid Glass 스타일
- [ ] **Phase 3** — Live Activity(무지개 바) + 다이나믹 아일랜드 + 로컬 알림
- [ ] **Phase 4** — iCloud 동기화 확인 (아이폰 ↔ 아이패드)
- [ ] **Phase 5** — AI(Claude) 자연어 일정 생성
- [ ] *향후* — APNs 푸시로 백그라운드 자동 갱신

---

## 📁 프로젝트 구조 (현재)

```
.
├── README.md          # 이 파일
└── mockup/            # Phase 0 디자인 목업 (웹, throwaway)
    ├── index.html
    ├── styles.css
    └── app.js
```

> Xcode 프로젝트(`Oneul/`, Widget Extension 등)는 Phase 1에서 추가됩니다.

---

## 📄 라이선스

미정 (Private).
