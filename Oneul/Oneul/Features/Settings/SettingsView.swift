import SwiftUI
import SwiftData
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

private struct ConditionalGlass: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.glassCard(cornerRadius: 22) } else { content }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("userType") private var userType = "general"
    @Bindable private var lang = AppLanguage.shared
    @State private var showResetConfirm = false
    @State private var resetError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sectionTitle(lang.tr("언어"))
                        languageCard

                        sectionTitle(lang.tr("사용자 유형"))
                        userTypeCard

                        sectionTitle(lang.tr("외형"))
                        appearanceCard

                        sectionTitle(lang.tr("알림 설정"))
                        notificationCard

                        #if os(macOS)
                        sectionTitle(lang.tr("메뉴 막대"))
                        menuBarCard
                        #endif

                        sectionTitle(lang.tr("가져오기"))
                        calendarImportCard

                        sectionTitle(lang.tr("개인정보"))
                        privacyCard

                        Text(lang.tr("AI: Apple Intelligence(온디바이스) · 학사일정·급식·시간표: 나이스(NEIS) 교육정보 개방 포털(교육부)"))   // AI·출처 합친 그냥 글자
                            .font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 6)

                        Text("Oneul \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(lang.tr("설정"))
        }
    }

    #if os(macOS)
    // MARK: 메뉴 막대 아이콘 켜기/끄기
    @AppStorage("menuBarTimeline") private var menuBarTimeline = true
    @AppStorage("menuBarAI") private var menuBarAI = true

    private var menuBarCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label(lang.tr("타임라인"), systemImage: "calendar.day.timeline.left")
                Spacer()
                Toggle(lang.tr("타임라인"), isOn: $menuBarTimeline).labelsHidden().tint(Color.appAccent)
            }
            HStack {
                Label("AI", systemImage: "sparkles")
                Spacer()
                Toggle("AI", isOn: $menuBarAI).labelsHidden().tint(Color.appAccent)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
    }
    #endif

    // MARK: 알림 — 권한 상태 + 시험 전날 알림 끄기/시각 변경
    @Environment(\.scenePhase) private var scenePhase
    @State private var notifStatus: UNAuthorizationStatus?
    @AppStorage("examEveEnabled") private var examEveEnabled = true
    @AppStorage("examEveMinutes") private var examEveMinutes = 20 * 60   // 자정 기준 분 (기본 20:00)

    private var examEveTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: examEveMinutes / 60, minute: examEveMinutes % 60,
                                  second: 0, of: Date()) ?? Date()
        } set: { new in
            let c = Calendar.current.dateComponents([.hour, .minute], from: new)
            examEveMinutes = (c.hour ?? 20) * 60 + (c.minute ?? 0)
        }
    }

    private var notificationCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(lang.tr("권한")).foregroundStyle(.secondary)
                Spacer()
                switch notifStatus {
                case .denied:
                    Button(lang.tr("거부됨 — 설정에서 허용")) { openSystemNotificationSettings() }
                        .font(.subheadline).tint(Color.appAccentText)
                case .notDetermined:
                    Button(lang.tr("알림 허용")) {
                        UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound]) { _, _ in refreshNotifStatus() }
                    }
                    .font(.subheadline).tint(Color.appAccentText)
                case .some:
                    Text(lang.tr("허용됨")).foregroundStyle(.secondary)
                case nil:
                    Text("")
                }
            }
            Divider()
            HStack {
                Text(lang.tr("시험 전날 알림"))
                Spacer()
                Toggle(lang.tr("시험 전날 알림"), isOn: $examEveEnabled).labelsHidden().tint(Color.appAccent)
            }
            if examEveEnabled {
                HStack {
                    Text(lang.tr("알림 시각")).foregroundStyle(.secondary)
                    Spacer()
                    DatePicker(lang.tr("알림 시각"), selection: examEveTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
        .onAppear(perform: refreshNotifStatus)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshNotifStatus() }   // 시스템 설정에서 돌아오면 상태 갱신
        }
        .onChange(of: examEveEnabled) { rescheduleNotifications() }
        .onChange(of: examEveMinutes) { rescheduleNotifications() }
    }

    private func refreshNotifStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { notifStatus = s.authorizationStatus }
        }
    }

    /// 권한 거부 시 시스템 설정의 이 앱 알림 화면으로 딥링크.
    private func openSystemNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.oneul.app") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// 시험 전날 알림 설정 변경 즉시 반영.
    private func rescheduleNotifications() {
        let events = (try? context.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
        NotificationManager.shared.reschedule(for: events)
    }

    // MARK: 애플 캘린더 가져오기(EventKit) — 기존 일정 이사 경로
    @State private var importing = false
    @State private var importMsg: String?

    @State private var showImportSheet = false
    @AppStorage("googleICSURL") private var googleURL = ""
    private enum ImportSource { case apple, google }
    @State private var confirmSource: ImportSource?   // 실행 전 확인

    private var calendarImportCard: some View {
        Button { showImportSheet = true } label: {
            HStack {
                Text(lang.tr("캘린더")).font(.body)
                Spacer()
                Image(systemName: "square.and.arrow.down")   // '가져오기' 텍스트 대신 임포트 아이콘
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.appAccentText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 16)
        .glassCard(cornerRadius: 22)
        .sheet(isPresented: $showImportSheet) { calendarImportSheet }
        .alert(importMsg ?? "", isPresented: Binding(get: { importMsg != nil },
                                                     set: { if !$0 { importMsg = nil } })) {
            Button(lang.tr("완료"), role: .cancel) {}
        }
    }

    // 애플스러운 선택 시트 — 소스 두 개(애플/구글)
    private var calendarImportSheet: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        importSourceRow(icon: "applelogo", tint: .primary,
                                        title: lang.tr("Apple 캘린더"),
                                        subtitle: lang.tr("이 기기의 캘린더에서 90일치")) {
                            confirmSource = .apple   // 실행 전 한 번 더 확인
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            importSourceRow(icon: "globe", tint: Color(red: 0.26, green: 0.52, blue: 0.96),
                                            title: lang.tr("Google 캘린더"),
                                            subtitle: lang.tr("비밀 iCal 주소(.ics)로"), chevron: false) {}
                            TextField(lang.tr("https://calendar.google.com/…/basic.ics"), text: $googleURL)
                                .textFieldStyle(.plain)
                                .font(.caption)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                #endif
                            Text(lang.tr("구글 캘린더 → 설정 → 내 캘린더 → 'iCal 형식의 비공개 주소'를 붙여넣으세요."))
                                .font(.caption2).foregroundStyle(.secondary)
                            Button {
                                confirmSource = .google   // 실행 전 한 번 더 확인
                            } label: {
                                if importing { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
                                else { Text(lang.tr("가져오기")).font(.subheadline.bold()).frame(maxWidth: .infinity) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(googleURL.trimmingCharacters(in: .whitespaces).isEmpty || importing)
                        }
                        .padding(18)   // Apple 행과 동일 — 두 카드 아이콘 선두 정렬
                        .glassCard(cornerRadius: 22)
                    }
                    .padding(16)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(lang.tr("캘린더 가져오기"))
            .navBarInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.tr("닫기")) { showImportSheet = false }
                }
            }
            .confirmationDialog(
                confirmSource == .google ? lang.tr("Google 캘린더에서 가져올까요?")
                                         : lang.tr("Apple 캘린더에서 가져올까요?"),
                isPresented: Binding(get: { confirmSource != nil },
                                     set: { if !$0 { confirmSource = nil } }),
                titleVisibility: .visible
            ) {
                Button(lang.tr("가져오기")) {
                    let src = confirmSource; confirmSource = nil
                    if src == .google { runGoogleImport() } else { runAppleImport() }
                }
                Button(lang.tr("취소"), role: .cancel) { confirmSource = nil }
            } message: {
                Text(lang.tr("오늘부터 90일치 일정을 추가해요. 이미 있는 일정(같은 제목·시각)은 건너뜁니다."))
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
    }

    private func importSourceRow(icon: String, tint: Color, title: String, subtitle: String,
                                 chevron: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.title3).bold()
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if importing && chevron { ProgressView().controlSize(.small) }
                else if chevron { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(chevron ? 18 : 0)
        .modifier(ConditionalGlass(on: chevron))
    }

    private func runAppleImport() {
        importing = true
        Task { @MainActor in
            defer { importing = false }
            do {
                let n = try await CalendarImport.run(context: context)
                showImportSheet = false
                importMsg = String(format: lang.tr("일정 %d개를 가져왔어요 (오늘부터 90일)"), n)
            } catch CalendarImport.ImportError.persistence {
                showImportSheet = false
                importMsg = lang.tr("가져온 일정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.")
            } catch CalendarImport.ImportError.denied {
                showImportSheet = false
                importMsg = lang.tr("캘린더 접근이 거부됐어요. 시스템 설정에서 허용해 주세요.")
            } catch {
                showImportSheet = false
                importMsg = lang.tr("Apple 캘린더를 가져오지 못했어요. 잠시 후 다시 시도해 주세요.")
            }
        }
    }

    private func runGoogleImport() {
        importing = true
        Task { @MainActor in
            defer { importing = false }
            do {
                let r = try await CalendarImport.runGoogleICS(urlString: googleURL, context: context)
                showImportSheet = false
                importMsg = r.skippedRecurring > 0
                    ? String(format: lang.tr("일정 %d개를 가져왔어요 · 반복 일정 %d개는 아직 지원하지 않아요"), r.added, r.skippedRecurring)
                    : String(format: lang.tr("일정 %d개를 가져왔어요 (오늘부터 90일)"), r.added)
            } catch CalendarImport.GoogleError.persistence {
                importMsg = lang.tr("가져온 일정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.")
            } catch CalendarImport.GoogleError.badURL {
                importMsg = lang.tr("가져오지 못했어요 — 주소를 확인해 주세요 (iCal 비공개 주소여야 해요).")
            } catch CalendarImport.GoogleError.empty {
                importMsg = lang.tr("가져올 일정을 찾지 못했어요. iCal 비공개 주소인지 확인해 주세요.")
            } catch CalendarImport.GoogleError.fetch {
                importMsg = lang.tr("캘린더를 불러오지 못했어요. 인터넷 연결과 주소를 확인해 주세요.")
            } catch {
                importMsg = lang.tr("캘린더를 불러오지 못했어요. 인터넷 연결과 주소를 확인해 주세요.")
            }
        }
    }


    // MARK: 개인정보 (처리방침 · 데이터 초기화)
    private var privacyCard: some View {
        VStack(spacing: 10) {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                HStack {
                    Label(lang.tr("개인정보 처리방침"), systemImage: "hand.raised")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .tint(.primary)
            Divider().opacity(0.3)
            if showResetConfirm {   // 버튼 바로 위 인라인 확인(2단계) — 팝업 위치 문제 해소
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.tr("정말 모든 데이터를 지울까요?"))
                        .font(.subheadline).bold().foregroundStyle(.red)
                    Text(lang.tr("이 기기의 모든 일정·학교 설정이 삭제됩니다. 되돌릴 수 없어요."))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button(role: .destructive) {
                            if resetAllData() {
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { showResetConfirm = false }
                            }
                        } label: {
                            Text(lang.tr("초기화")).font(.subheadline.bold())
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent).tint(.red)
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { showResetConfirm = false }
                        } label: {
                            Text(lang.tr("취소")).font(.subheadline)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button(role: .destructive) {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { showResetConfirm.toggle() }   // 1차: 확인 펼침
            } label: {
                HStack {
                    Label(lang.tr("모든 데이터 초기화"), systemImage: "trash").font(.subheadline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
        .alert(resetError ?? "", isPresented: Binding(get: { resetError != nil },
                                                       set: { if !$0 { resetError = nil } })) {
            Button(lang.tr("확인"), role: .cancel) {}
        }
    }

    /// 기기 내 모든 데이터 삭제 — 일정·메모(SwiftData) + 학교·시간표·교시 설정(UserDefaults) + Live Activity.
    /// 언어·외형 같은 표시 설정은 남긴다.
    private func resetAllData() -> Bool {
        let resetContext = ModelContext(context.container)
        resetContext.autosaveEnabled = false
        do {
            try resetContext.delete(model: ScheduleEvent.self)
            try resetContext.delete(model: Memo.self)
            try resetContext.delete(model: MemoAttachment.self)   // 일괄 삭제는 cascade를 안 타므로 명시 삭제
            try resetContext.delete(model: MemoCheckItem.self)
            try resetContext.save()
        } catch {
            resetError = lang.tr("데이터를 초기화하지 못했어요. 잠시 후 다시 시도해 주세요.")
            return false
        }
        let d = UserDefaults.standard
        ["userType", "neisOffice", "neisName", "neisCode", "neisKind", "neisGrade", "neisClass",
         "ttSetup", "ttGrade", "ttClass", "ttElectives", "ttCommonOverride", "lastSchoolRefresh", "neisApiKey",
         "sourceTombstones",   // 안 지우면 초기화 후 같은 학교 재등록 시 과거 삭제 수업이 빠진 시간표가 생성됨
         "promoSnoozeYear"]    // 진급 안내 스누즈도 초기 상태로
            .forEach { d.removeObject(forKey: $0) }
        for p in 1...PeriodSchedule.count {
            d.removeObject(forKey: "bell.\(p).start")
            d.removeObject(forKey: "bell.\(p).end")
        }
        #if os(iOS)
        Task { await LiveActivityController.shared.end() }
        #endif
        Haptics.notify(.success)
        return true
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.caption).bold().foregroundStyle(.secondary).padding(.leading, 4)
    }

    // MARK: 사용자 유형
    private var userTypeCard: some View {
        VStack(spacing: 10) {
            #if os(macOS)
            FullWidthSegments(selection: $userType,
                              options: [(lang.tr("일반"), "general"), (lang.tr("학생"), "student")])
            #else
            Picker(lang.tr("사용자 유형"), selection: $userType) {
                Text(lang.tr("일반")).tag("general")
                Text(lang.tr("학생")).tag("student")
            }
            .labelsHidden().pickerStyle(.segmented)
            #endif
            if userType == "student" {
                NavigationLink {
                    SchoolSetupView()
                } label: {
                    HStack {
                        Label(lang.tr("학교 설정 · 시간표 가져오기"), systemImage: "graduationcap")
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .tint(.primary)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
    }

    // MARK: 언어
    private var languageCard: some View {
        Group {
            #if os(macOS)
            FullWidthSegments(selection: $lang.code, options: [("한국어", "ko"), ("English", "en")])
            #else
            Picker(lang.tr("언어"), selection: $lang.code) {
                Text("한국어").tag("ko")
                Text("English").tag("en")
            }
            .labelsHidden().pickerStyle(.segmented)   // 섹션 헤더가 이미 '언어'
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .glassCard(cornerRadius: 22)
    }

    // MARK: 외형
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if os(macOS)
            FullWidthSegments(selection: $appearanceRaw,
                              options: Appearance.allCases.map { (lang.tr($0.label), $0.rawValue) })
            #else
            Picker(lang.tr("외형"), selection: $appearanceRaw) {
                ForEach(Appearance.allCases) { a in Text(lang.tr(a.label)).tag(a.rawValue) }
            }
            .labelsHidden().pickerStyle(.segmented)
            #endif
            Text(lang.tr("‘시스템’은 기기 설정(다크/라이트)을 따릅니다."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 22)
    }

}

/// 맥용 풀폭 세그먼트 컨트롤 — macOS 기본 segmented는 폭을 안 채워서 직접 그림(각 칸이 균등하게 꽉 참).
struct FullWidthSegments: View {
    @Binding var selection: String
    let options: [(label: String, value: String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                Button { selection = opt.value } label: {
                    Text(opt.label)
                        .font(.subheadline).bold()
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .foregroundStyle(selection == opt.value ? Color.appOnAccent : .primary)
                        .background(selection == opt.value ? Color.appAccent : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == opt.value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - 개인정보 처리방침 (인앱)

struct PrivacyPolicyView: View {
    @Bindable private var lang = AppLanguage.shared

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                        VStack(alignment: .leading, spacing: 6) {
                            if !sec.0.isEmpty {
                                Text(sec.0).font(.headline)
                            }
                            Text(sec.1).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(lang.tr("개인정보 처리방침"))
        .navBarInline()
    }

    // (제목, 본문) 쌍 — 언어별 전체 텍스트.
    private var sections: [(String, String)] {
        if lang.isEnglish {
            return [
                ("", "Oneul works without a Oneul account. This policy explains where data is stored and when optional features send it outside your device."),
                ("Your schedule", "Schedules, memos, checklist items and attachments are stored on your device and, when available, synced through your personal iCloud (CloudKit private database). The developer cannot browse your private CloudKit database."),
                ("Live Activity push", "To update the Lock Screen while the app is closed, a random device ID, push tokens and today’s display data (titles, times and display state) are sent to Oneul’s Cloudflare server. Records expire within 3 days of registration and are used only for push delivery, without ads or analytics."),
                ("AI assistant", "Schedule interpretation runs on-device using rules and, on supported devices, Apple Intelligence. Photo text recognition uses on-device Vision. Voice transcription uses Apple Speech Recognition under Apple’s privacy policy."),
                ("Student features (NEIS)", "When you use student features, the school name, grade and class you enter are sent to the Ministry of Education's NEIS open data portal (via a relay server) to fetch your timetable, meals and academic calendar. No name, contact or other identifying information is sent. Only the results are saved on your device."),
                ("No tracking", "The app contains no third-party analytics or advertising SDKs and does not track you."),
                ("Permissions", "Location or place search text may be sent to Apple Maps when choosing a place. The microphone is used while dictating. Apple Calendar is read only when you request an import. A private Google iCal URL is stored in device settings and requested directly from Google."),
                ("Deleting your data", "Settings → Reset all data removes local schedules and memos. Deletions may sync to your personal iCloud. Temporary push records expire within 3 days of registration.")
            ]
        } else {
            return [
                ("", "Oneul은 별도의 Oneul 계정 없이 동작합니다. 이 방침은 자료의 저장 위치와 선택 기능을 사용할 때 기기 밖으로 전송되는 정보를 설명합니다."),
                ("일정 데이터", "일정·메모·체크 항목·첨부파일은 기기에 저장되며, iCloud를 사용할 수 있으면 개인 CloudKit 비공개 데이터베이스에 동기화됩니다. 개발자는 이 비공개 데이터베이스를 열람할 수 없습니다."),
                ("라이브 액티비티 푸시", "앱을 닫아도 잠금화면을 갱신하기 위해 임의 기기 식별자·푸시 토큰·당일 표시 자료(제목·시각·표시 상태)가 Oneul의 Cloudflare 서버에 전송됩니다. 등록 후 최대 3일 안에 삭제하며 푸시 전송에만 사용하고 광고·분석에는 쓰지 않습니다."),
                ("AI 비서", "일정 해석은 기기 내 규칙과 지원 기기의 Apple Intelligence로 처리합니다. 사진의 글자는 기기 내 Vision으로 인식합니다. 음성 변환에는 Apple 음성 인식이 사용되며 Apple 개인정보 정책이 적용됩니다."),
                ("학생 기능 (NEIS)", "학생 기능을 쓸 때, 입력한 학교명·학년·반이 시간표·급식·학사일정 조회를 위해 교육부 「나이스(NEIS) 교육정보 개방 포털」(중계 서버 경유)로 전송됩니다. 이름·연락처 등 개인 식별정보는 전송하지 않으며, 조회 결과만 기기에 저장됩니다."),
                ("추적 안 함", "제3자 분석·광고 SDK가 없으며 사용자를 추적하지 않습니다."),
                ("권한", "장소를 선택할 때 현재 위치 또는 장소 검색어가 Apple 지도에 전달될 수 있습니다. 마이크는 음성 입력 중에만 사용합니다. 요청한 경우에만 Apple 캘린더를 읽으며, Google 비공개 iCal URL은 기기 설정에 저장하고 Google에 직접 요청합니다."),
                ("데이터 삭제", "설정 → 모든 데이터 초기화에서 기기의 일정과 메모를 삭제합니다. 삭제 내용은 개인 iCloud에도 동기화될 수 있습니다. 푸시 서버의 임시 자료는 등록 후 최대 3일 안에 삭제됩니다.")
            ]
        }
    }
}

#Preview { SettingsView() }
