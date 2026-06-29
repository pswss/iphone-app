import SwiftUI
import SwiftData

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

                        sectionTitle(lang.tr("개인정보"))
                        privacyCard

                        Text(lang.tr("학사일정·급식·시간표: 나이스(NEIS) 교육정보 개방 포털 (교육부)"))   // 출처(그냥 글자)
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 6)
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
        Task { await LiveActivityController.shared.end() }
        Haptics.notify(.success)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.caption).bold().foregroundStyle(.secondary).padding(.leading, 4)
    }

    // MARK: 사용자 유형
    private var userTypeCard: some View {
        VStack(spacing: 10) {
            Picker("", selection: $userType) {
                Text(lang.tr("일반")).tag("general")
                Text(lang.tr("학생")).tag("student")
            }
            .pickerStyle(.segmented)
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
        Picker(lang.tr("언어"), selection: $lang.code) {
            Text("한국어").tag("ko")
            Text("English").tag("en")
        }
        .pickerStyle(.segmented)
        .padding(14)
        .glassCard(cornerRadius: 22)
    }

    // MARK: 외형
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(lang.tr("외형"), selection: $appearanceRaw) {
                ForEach(Appearance.allCases) { a in Text(lang.tr(a.label)).tag(a.rawValue) }
            }
            .pickerStyle(.segmented)
            Text(lang.tr("‘시스템’은 기기 설정(다크/라이트)을 따릅니다."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
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
        .navigationBarTitleDisplayMode(.inline)
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
