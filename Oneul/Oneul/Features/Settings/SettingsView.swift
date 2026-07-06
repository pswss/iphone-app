import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

private struct ConditionalGlass: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.glassCard(cornerRadius: 22) } else { content }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("userType") private var userType = "general"
    @Bindable private var lang = AppLanguage.shared
    @State private var showResetConfirm = false

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
            .confirmationDialog(lang.tr("정말 모든 데이터를 지울까요?"),
                                isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button(lang.tr("초기화"), role: .destructive) { resetAllData() }
                Button(lang.tr("취소"), role: .cancel) {}
            } message: {
                Text(lang.tr("이 기기의 모든 일정·학교 설정이 삭제됩니다. 되돌릴 수 없어요."))
            }
        }
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
            } catch {
                showImportSheet = false
                importMsg = lang.tr("캘린더 접근이 거부됐어요. 시스템 설정에서 허용해 주세요.")
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
            } catch {
                importMsg = lang.tr("가져오지 못했어요 — 주소를 확인해 주세요 (iCal 비공개 주소여야 해요).")
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
            Button(role: .destructive) { showResetConfirm = true } label: {
                HStack {
                    Label(lang.tr("모든 데이터 초기화"), systemImage: "trash").font(.subheadline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
    }

    /// 기기 내 모든 데이터 삭제 — 일정(SwiftData) + 학교·시간표·교시 설정(UserDefaults) + Live Activity.
    /// 언어·외형 같은 표시 설정은 남긴다.
    private func resetAllData() {
        try? context.delete(model: ScheduleEvent.self)
        try? context.save()
        let d = UserDefaults.standard
        ["userType", "neisOffice", "neisName", "neisCode", "neisKind", "neisGrade", "neisClass",
         "ttSetup", "ttGrade", "ttClass", "ttElectives", "ttCommonOverride", "lastSchoolRefresh", "neisApiKey"]
            .forEach { d.removeObject(forKey: $0) }
        for p in 1...PeriodSchedule.count {
            d.removeObject(forKey: "bell.\(p).start")
            d.removeObject(forKey: "bell.\(p).end")
        }
        #if os(iOS)
        Task { await LiveActivityController.shared.end() }
        #endif
        Haptics.notify(.success)
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
            Picker("", selection: $userType) {
                Text(lang.tr("일반")).tag("general")
                Text(lang.tr("학생")).tag("student")
            }
            .pickerStyle(.segmented)
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
                Text(opt.label)                       // Button 대신 탭 제스처 → 맥 포커스 링 원천 없음
                    .font(.subheadline).bold()
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .foregroundStyle(selection == opt.value ? Color.appOnAccent : .primary)
                    .background(selection == opt.value ? Color.appAccent : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = opt.value }
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
                ("", "Oneul does not collect your personal data or store it on any server. This policy explains what the app does with your information."),
                ("Your schedule", "All events you create are stored only on your device (SwiftData). They are never sent to us or any third party."),
                ("AI assistant", "The AI assistant runs fully on-device through Apple Intelligence. What you type or say never leaves your device."),
                ("Student features (NEIS)", "When you use student features, the school name, grade and class you enter are sent to the Ministry of Education's NEIS open data portal (via a relay server) to fetch your timetable, meals and academic calendar. No name, contact or other identifying information is sent. Only the results are saved on your device."),
                ("No tracking", "The app contains no third-party analytics or advertising SDKs and does not track you."),
                ("Permissions", "Location (when setting an event place), microphone and speech recognition (when adding events by voice) are used only while you use those features, and are processed on-device."),
                ("Deleting your data", "You can permanently erase all data on this device at any time from Settings → Reset all data.")
            ]
        } else {
            return [
                ("", "Oneul은 사용자의 개인정보를 수집하거나 서버에 저장하지 않습니다. 이 방침은 앱이 정보를 어떻게 다루는지 설명합니다."),
                ("일정 데이터", "사용자가 만든 모든 일정은 기기에만 저장됩니다(SwiftData). 당사나 제3자에게 전송되지 않습니다."),
                ("AI 비서", "AI 비서는 Apple Intelligence로 기기에서 완전히 동작합니다. 입력하거나 말한 내용은 기기를 벗어나지 않습니다."),
                ("학생 기능 (NEIS)", "학생 기능을 쓸 때, 입력한 학교명·학년·반이 시간표·급식·학사일정 조회를 위해 교육부 「나이스(NEIS) 교육정보 개방 포털」(중계 서버 경유)로 전송됩니다. 이름·연락처 등 개인 식별정보는 전송하지 않으며, 조회 결과만 기기에 저장됩니다."),
                ("추적 안 함", "제3자 분석·광고 SDK가 없으며 사용자를 추적하지 않습니다."),
                ("권한", "위치(일정 장소 지정 시), 마이크·음성 인식(음성으로 일정 입력 시)은 해당 기능을 쓸 때만 사용되며 기기에서 처리됩니다."),
                ("데이터 삭제", "설정 → 모든 데이터 초기화에서 이 기기의 모든 데이터를 언제든 영구 삭제할 수 있습니다.")
            ]
        }
    }
}

#Preview { SettingsView() }
