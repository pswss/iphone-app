import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("userType") private var userType = "general"
    @AppStorage("neisApiKey") private var neisKey = ""   // 사용자별 NEIS 키(배포 시 키 미포함)
    @Bindable private var lang = AppLanguage.shared

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

                        sectionTitle(lang.tr("정보"))
                        infoCard
                    }
                    .padding(16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(lang.tr("설정"))
        }
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

                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.tr("NEIS API 키")).font(.subheadline)
                    SecureField(lang.tr("발급받은 키 붙여넣기"), text: $neisKey)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Link(lang.tr("무료 키 발급받기 (open.neis.go.kr)"),
                         destination: URL(string: "https://open.neis.go.kr")!)
                        .font(.caption2)
                }
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

    // MARK: 정보 (데이터 출처 표기)
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lang.tr("데이터 출처")).font(.subheadline).bold()
            Text(lang.tr("학사일정·급식·시간표: 나이스(NEIS) 교육정보 개방 포털 (교육부)"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 22)
    }
}

#Preview { SettingsView() }
