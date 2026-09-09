# 오늘 · Oneul

**일정을 문장으로 입력하고, 지금과 다음 일정을 한눈에 확인하는 Apple 기기용 일정 앱.**

“내일 오전 9시 회의”, “매주 수요일 오후 7시 운동”처럼 입력한 내용을 확인한 뒤 일정으로 적용합니다. 하루의 시간표는 색상 타임라인으로 보여 주고, 위젯·Live Activity·Apple Watch로 다음 일정을 이어서 확인할 수 있습니다.

[제품 소개](https://oneul-privacy.pswss.workers.dev/) · [기기별 다운로드](https://oneul-privacy.pswss.workers.dev/download) · [App Store](https://apps.apple.com/kr/app/oneul-calendar/id6788308943) · [개인정보 처리방침](https://oneul-privacy.pswss.workers.dev/privacy)

## 화면

저장소에 포함된 제품 소개용 캡처입니다. 현재 빌드의 모든 상태를 보여 주는 이미지는 아닙니다.

<p>
  <img src="Oneul/server/privacy-page/public/assets/iphone-timeline.jpg" width="230" alt="오늘 iPhone 앱의 시간별 일정 그리드">
  <img src="Oneul/server/privacy-page/public/assets/iphone-ai.jpg" width="230" alt="문장을 일정으로 바꾸는 오늘 앱의 입력 화면">
</p>

## 주요 기능

| 영역 | 기능 |
| --- | --- |
| 오늘 | 일간·주간 일정, 색상 타임라인, 현재·다음 일정, D-Day |
| 일정 편집 | 시간 그리드에서 추가·이동·길이 조절, 반복·종일·여러 날 일정, 복사·삭제 |
| 자연어 입력 | 규칙 우선 해석, 필요한 경우 Apple Intelligence 보완, 적용 전 미리보기 |
| 사진 가져오기 | 기기 내 Vision으로 시간표의 글자·표를 읽어 일정 후보 생성 |
| 학생 기능 | NEIS 학교·학년·반 설정, 시간표·선택과목 검토, 학사일정·급식 |
| 메모 | 메모·체크 항목·첨부파일 |
| 연결 | Apple Calendar·Google iCal 가져오기, 위젯, Live Activity, Watch |
| Mac | 주간 일정, 사이드바, 메뉴 막대 일정·입력, 별도 Settings 화면 |

한국어·영어와 시스템·라이트·다크 외형을 지원합니다. 학교를 설정하지 않아도 일반 일정과 메모를 사용할 수 있습니다.

## 처음 사용할 때

1. 오늘 화면의 `+` 또는 AI 탭에서 일정을 입력합니다.
2. 날짜·시각·반복 범위를 미리보기에서 확인한 뒤 적용합니다.
3. 필요할 때 알림을 허용하고 홈·잠금화면에 위젯을 추가합니다.
4. 학생 기능이 필요하면 학교·학년·반을 선택하고 시간표를 검토합니다.

사진과 자연어에서 읽은 내용은 수정할 수 있는 후보입니다. 선택과목 분류도 개인 수강 정보를 직접 조회하는 기능이 아니므로 최종 배치를 확인해야 합니다.

## 지원 범위

현재 프로젝트 설정의 마케팅 버전은 `1.1`, 빌드 번호는 `1`입니다. 실제 배포 상태는 다운로드 안내와 App Store에서 확인하세요.

| 대상 | 프로젝트의 최소 OS | 비고 |
| --- | --- | --- |
| iPhone·iPad | iOS / iPadOS 26.0 | SwiftUI 앱 |
| Apple Watch | watchOS 11.0 | iPhone 동반 앱·컴플리케이션 |
| Mac | macOS 26.0 | 네이티브 앱 타깃 포함 |

기본 규칙 파서와 사진 시간표 인식은 Apple Intelligence를 요구하지 않습니다. 모델이 필요한 고급 해석은 지원 기기·언어·시스템 설정에 영향을 받습니다. 현재 다운로드 페이지 소스에는 공개 Mac 설치 파일 URL이 설정되어 있지 않습니다. 소스 빌드와 서명·공증된 설치 파일 배포는 별개입니다.

## 자연어와 사진 처리

```text
문장 입력 → 규칙 파서 → 필요할 때 Apple Intelligence → 미리보기 → 저장
사진 선택 → 기기 내 Vision OCR·표 해석 ────────────────┘
```

[FastScheduleParser.swift](Oneul/Oneul/Features/AI/FastScheduleParser.swift)가 지원되는 생성·수정·삭제 표현을 먼저 처리합니다. [AppleIntelligenceClient.swift](Oneul/Oneul/Features/AI/AppleIntelligenceClient.swift)는 규칙으로 처리하지 못한 입력을 보완합니다. 모델은 의미를 추출하고 실제 날짜·시각 계산은 Swift 코드가 맡습니다.

일정 적용은 저장 결과를 확인하고, 삭제 후에는 잠시 실행 취소를 제공합니다. AI 기능을 사용한다고 모든 입력이 모델에 전달되는 것은 아닙니다. 현재 입력 화면은 텍스트와 사진 중심이며, 별도의 마이크 버튼은 제공하지 않습니다.

## 데이터가 저장되고 이동하는 곳

| 기능 | 데이터 경로 |
| --- | --- |
| 일정·메모 | SwiftData. 사용 가능한 구성에서는 App Group·개인 CloudKit, 컨테이너 생성 실패 시 다른 저장 구성으로 폴백 |
| 위젯 | App Group 공유 스냅샷 |
| Watch | WatchConnectivity로 일정 스냅샷 전달 |
| 자연어·사진 인식 | 기기 내 규칙·Vision·Foundation Models |
| 학생 기능 | 학교·학년·반 등 조회 조건을 NEIS 프록시 또는 NEIS에 요청 |
| Live Activity 서버 푸시 | 활성화된 경우 임의 기기 ID·APNs 토큰·당일 표시 상태를 Cloudflare Worker에 전달 |
| 캘린더 가져오기 | 사용자 요청으로 Apple Calendar를 읽거나 지정한 Google iCal URL에 요청 |

푸시 Worker는 등록 내용을 최대 3일 TTL로 저장합니다. 기기 내 갱신, WidgetKit 타임라인, 서버 푸시가 역할을 나눕니다. 실제 표시 시점은 OS의 백그라운드·푸시 정책에 영향을 받으며 초 단위 갱신을 보장하지 않습니다.

**문서 정합성 과제:** 공개 웹 정책은 CloudKit과 Live Activity 전송을 설명하지만, 앱 안의 정책과 `PrivacyInfo.xcprivacy`에는 여전히 “기기에만 저장 / 수집 없음”에 해당하는 내용이 남아 있습니다. 다음 배포 전에 실제 데이터 흐름과 함께 정리해야 합니다. README 수정으로 앱 안의 정책까지 바뀌지는 않습니다.

## 소스 빌드

macOS, 필요한 Apple SDK를 포함한 Xcode, XcodeGen이 필요합니다. 기기 실행과 iCloud·App Group·푸시는 자신의 서명 설정과 프로비저닝을 사용해야 합니다.

```bash
git clone https://github.com/pswss/iphone-app.git
cd iphone-app/Oneul
cp docs/Secrets.swift.example Oneul/Secrets.swift
```

`Oneul/Secrets.swift`의 값을 로컬에서 설정합니다. 예제의 `example.com` 주소와 빈 등록 키에서는 서버 푸시가 비활성화됩니다. 실제 비밀이 들어 있는 파일은 Git에서 제외됩니다.

| 설정 | 용도 |
| --- | --- |
| `pushServerURL` | 직접 운영하는 Live Activity Worker 주소 |
| `pushRegisterKey` | Worker의 `REG_KEY`와 일치하는 등록 키 |
| `neisProxyBase` | NEIS 프록시의 `/hub/` 기본 주소 |
| `neisBakedKey` | 프록시를 쓰지 않을 때의 직접 조회 키. 배포 앱에는 프록시 방식 권장 |

[project.yml](Oneul/project.yml)의 개발 팀·번들 ID, entitlements의 iCloud·App Group 식별자, [AppConfig.swift](Oneul/Shared/AppConfig.swift)의 App Group 식별자를 자신의 구성에 맞춥니다. Watch 동반 앱 식별자와 푸시 Worker topic도 같은 구성으로 맞춰야 합니다.

```bash
xcodegen generate
open Oneul.xcodeproj
```

`Oneul`, `OneulMac`, `OneulWatch` 스킴 중 실행 대상을 선택합니다. 타깃·소스 구성의 원본은 `project.yml`입니다. Xcode에서만 바꾼 프로젝트 구조는 재생성 시 사라질 수 있습니다.

## 검사

아래 명령은 저장소 안 `Oneul/` 디렉터리 기준입니다.

```bash
for script in harness/run_*contract.sh; do
  bash "$script" || exit 1
done
bash harness/run_series_edit.sh
```

계약 검사는 접근성 액션, 조밀한 일정 배치, 학교 흐름, Mac AI 팝오버, Watch 시간 상태의 소스 조건을 확인합니다. Swift 하네스는 별도의 실행 검증입니다. 일부 하네스는 `/Applications/Xcode-beta.app` 경로를 사용하므로 설치 환경에 맞춰 확인해야 합니다.

서명 없이 컴파일을 점검하는 예:

```bash
xcodebuild -project Oneul.xcodeproj -scheme Oneul \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Oneul.xcodeproj -scheme OneulMac \
  -configuration Debug -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

컴파일과 소스 검사만으로 실기기 동기화·VoiceOver·큰 글자·Live Activity 동작이 검증되지는 않습니다. 잠금화면, 날짜 변경, 오프라인, 반복 일정 삭제·복구는 별도 실기기 확인 대상입니다.

## 프로젝트 구조

```text
Oneul/
├── Oneul/                # Today, AI, School, Memo, Editor, Settings
├── Shared/               # 공유 설정·색상·표시 상태·Watch payload
├── OneulWidget/          # 홈/잠금화면 위젯·Live Activity
├── OneulWatch/           # Watch 앱
├── OneulWatchWidget/     # 컴플리케이션
├── harness/              # 실행 하네스·소스 계약 검사
├── ci_scripts/           # Xcode Cloud 설정 생성
├── server/push-worker/   # APNs 중계 Worker
├── server/privacy-page/  # 제품·다운로드·정책·지원 웹사이트
└── project.yml           # XcodeGen 원본
proxy/                    # NEIS 프록시 Worker
```

Xcode Cloud는 [ci_post_clone.sh](Oneul/ci_scripts/ci_post_clone.sh)에서 `ONEUL_PUSH_SERVER_URL_HEX`, `ONEUL_PUSH_REGISTER_KEY`, `ONEUL_NEIS_PROXY_BASE_HEX`로 `Secrets.swift`를 생성합니다. 실제 값은 CI의 Secret 설정에 보관합니다. APNs 키와 NEIS 키도 각 Worker의 비밀 설정으로 관리합니다.

과거 `SETUP.md`와 일부 설계 문서에는 이전 AI·키 설정이 남아 있으므로 현재 설치는 이 README와 실제 소스를 기준으로 합니다. 변경 시 지켜야 할 디자인 규칙은 [CLAUDE.md](CLAUDE.md)에 있습니다.

## 라이선스와 데이터 출처

별도 `LICENSE` 파일은 아직 없습니다. NEIS 데이터 출처는 교육부·한국교육학술정보원의 나이스 교육정보 개방 포털입니다. 외부 데이터·자산을 재사용할 때는 각 제공처의 이용 조건을 확인해야 합니다.
