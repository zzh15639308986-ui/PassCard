import ActivityKit
import Foundation

/// Live Activities are the whole point of the app: this is the surface that puts
/// a boarding pass on the Lock Screen without unlocking.
@MainActor
enum LiveActivityController {
    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static var runningCount: Int {
        Activity<PassActivityAttributes>.activities.count
    }

    static func start(for pass: Pass) throws {
        guard isSupported else {
            throw LiveActivityError.disabled
        }
        guard Activity<PassActivityAttributes>.activities.count < 5 else {
            throw LiveActivityError.tooMany
        }
        // Replacing rather than stacking keeps one pass from showing twice.
        end(for: pass.id)

        let attributes = PassActivityAttributes(passID: pass.id, kindLabel: pass.type.label)
        let state = PassActivityAttributes.ContentState(pass)
        _ = try Activity<PassActivityAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil)
    }

    /// Call after the underlying pass changed, otherwise the Lock Screen keeps
    /// showing the fields captured at pin time.
    static func refresh(for pass: Pass) {
        guard let activity = activity(for: pass.id) else { return }
        let state = PassActivityAttributes.ContentState(pass)
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func end(for passID: UUID) {
        guard let activity = activity(for: passID) else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func endAll() {
        for activity in Activity<PassActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func activity(for passID: UUID) -> Activity<PassActivityAttributes>? {
        Activity<PassActivityAttributes>.activities.first { $0.attributes.passID == passID }
    }
}

enum LiveActivityError: LocalizedError {
    case disabled
    case tooMany

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "系统里关掉了实时活动。到「设置 → 凭证卡 → 实时活动」打开后再试。"
        case .tooMany:
            return "锁屏上已经有 5 张卡片了。先取消一张再固定新的。"
        }
    }
}
