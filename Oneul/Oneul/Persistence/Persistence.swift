import Foundation
import SwiftData

/// SwiftData 컨테이너 생성.
///
/// 우선순위: App Group + iCloud(CloudKit) 동기화 → 로컬 전용.
///
/// 중요: SwiftData는 entitlement(App Group/iCloud)가 없을 때 **던지는 에러가 아니라 내부 assertion으로 크래시**할 수 있습니다.
/// `try?`로는 못 막으므로, App Group 컨테이너 접근 가능 여부를 **먼저 확인**해서 그때만 클라우드 설정을 씁니다.
/// (무료 계정/캐퍼빌리티 미설정 환경에서도 크래시 없이 로컬로 동작)
enum Persistence {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([ScheduleEvent.self])
        var configs: [ModelConfiguration] = []

        // App Group 사용 가능할 때만(=entitlement 존재) 공유 저장소 + iCloud 동기화 시도.
        let appGroupAvailable = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID) != nil

        if appGroupAvailable {
            configs.append(
                ModelConfiguration(
                    "Oneul",
                    schema: schema,
                    groupContainer: .identifier(AppConfig.appGroupID),
                    cloudKitDatabase: .automatic
                )
            )
        }

        // 로컬 전용(엔타이틀먼트 불필요) — 항상 마지막 폴백.
        configs.append(ModelConfiguration("OneulLocal", schema: schema))

        for config in configs {
            if let container = try? ModelContainer(for: schema, configurations: [config]) {
                return container
            }
        }

        // 최후의 폴백.
        return try! ModelContainer(for: schema)
    }
}
