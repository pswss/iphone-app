import Foundation
import Observation
import SwiftData

/// One store identity per installation. A failed open never switches to an empty store.
@MainActor
@Observable
final class Persistence {
    private(set) var container: ModelContainer?

    init() { retry() }

    func retry() {
        do { container = try Self.makeContainer() }
        catch { container = nil }
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([ScheduleEvent.self, Memo.self, MemoAttachment.self, MemoCheckItem.self])
        // App Group availability is checked before constructing a CloudKit configuration:
        // missing entitlements can assert inside SwiftData instead of throwing.
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID) != nil
        let config = shared
            ? ModelConfiguration("Oneul", schema: schema,
                                 groupContainer: .identifier(AppConfig.appGroupID), cloudKitDatabase: .automatic)
            : ModelConfiguration("OneulLocal", schema: schema,
                                 groupContainer: .none, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
