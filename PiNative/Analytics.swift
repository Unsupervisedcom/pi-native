import Foundation
import PostHog

@MainActor
protocol AnalyticsControlling: AnyObject {
    var isEnabled: Bool { get }

    func setEnabled(_ isEnabled: Bool)
    func track(_ event: AnalyticsEvent)
}

@MainActor
protocol AnalyticsClient: AnyObject {
    func capture(name: String, properties: [String: String])
    func setEnabled(_ isEnabled: Bool)
}

enum PiLoadFailureStage: String, Equatable {
    case processStart = "process_start"
    case sessionLoad = "session_load"
}

enum AnalyticsFailureKind: String, CaseIterable, Equatable {
    case processLifecycle = "process_lifecycle"
    case requestTimedOut = "request_timed_out"
    case invalidResponse = "invalid_response"
    case writeFailed = "write_failed"
    case launchFailed = "launch_failed"
    case unknown

    static func classifyLoadFailure(_ error: Error, stage: PiLoadFailureStage) -> Self {
        guard let clientError = error as? PiRPCClient.ClientError else {
            return stage == .processStart ? .launchFailed : .unknown
        }
        switch clientError {
        case .processAlreadyRunning, .processNotRunning, .processExited:
            return .processLifecycle
        case .requestTimedOut:
            return .requestTimedOut
        case .invalidResponse:
            return .invalidResponse
        case .writeFailed:
            return .writeFailed
        case .requestCancelled:
            return .unknown
        }
    }

    static func classifyHandledFailure(_ error: Error) -> Self {
        guard let clientError = error as? PiRPCClient.ClientError else { return .unknown }
        switch clientError {
        case .requestTimedOut:
            return .requestTimedOut
        case .invalidResponse:
            return .invalidResponse
        case .writeFailed:
            return .writeFailed
        case .processAlreadyRunning, .processNotRunning, .processExited, .requestCancelled:
            return .unknown
        }
    }
}

struct PiLoadFailure: Equatable {
    let stage: PiLoadFailureStage
    let failureKind: AnalyticsFailureKind

    init(stage: PiLoadFailureStage, error: Error) {
        self.stage = stage
        failureKind = AnalyticsFailureKind.classifyLoadFailure(error, stage: stage)
    }
}

enum PiOperationArea: String, CaseIterable, Equatable {
    case modelSelection = "model_selection"
    case effortSelection = "effort_selection"
    case promptSubmission = "prompt_submission"
    case extensionUIResponse = "extension_ui_response"
}

struct HandledPiOperationFailure: Equatable {
    let area: PiOperationArea
    let failureKind: AnalyticsFailureKind

    init(area: PiOperationArea, error: Error) {
        self.area = area
        failureKind = AnalyticsFailureKind.classifyHandledFailure(error)
    }
}

enum AnalyticsEvent: Equatable {
    case appOpened
    case chatStarted
    case promptSubmitted
    case settingsOpened
    case rightPaneOpened(RightPaneMode)
    case piLoadFailed(PiLoadFailure, isProjectChat: Bool)
    case handledException(HandledPiOperationFailure)

    var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .chatStarted: "chat_started"
        case .promptSubmitted: "prompt_submitted"
        case .settingsOpened: "settings_opened"
        case .rightPaneOpened: "right_pane_opened"
        case .piLoadFailed: "pi_load_failed"
        case .handledException: "handled_exception"
        }
    }

    /// This deliberate allowlist prevents user-generated and local-workspace
    /// data from being added to analytics payloads.
    var properties: [String: String] {
        switch self {
        case .rightPaneOpened(let pane): ["pane": pane.rawValue]
        case .piLoadFailed(let failure, let isProjectChat): [
            "stage": failure.stage.rawValue,
            "failure_kind": failure.failureKind.rawValue,
            "is_project_chat": isProjectChat ? "true" : "false"
        ]
        case .handledException(let failure): [
            "area": failure.area.rawValue,
            "failure_kind": failure.failureKind.rawValue
        ]
        case .appOpened, .chatStarted, .promptSubmitted, .settingsOpened: [:]
        }
    }
}

@MainActor
final class AnalyticsService: ObservableObject, AnalyticsControlling {
    static let preferenceKey = "analytics.isEnabled"

    @Published private(set) var isEnabled: Bool

    private let isConfigured: Bool
    private let client: (any AnalyticsClient)?
    private let defaults: UserDefaults

    init(
        apiKey: String?,
        defaults: UserDefaults = .standard,
        client: (any AnalyticsClient)? = nil
    ) {
        self.defaults = defaults
        let normalizedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isConfigured = normalizedKey.hasPrefix("phc_")
        isEnabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
        self.client = isConfigured ? (client ?? PostHogAnalyticsClient(apiKey: normalizedKey)) : nil
        self.client?.setEnabled(isEnabled)
    }

    func setEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else { return }
        self.isEnabled = isEnabled
        defaults.set(isEnabled, forKey: Self.preferenceKey)
        client?.setEnabled(isEnabled)
    }

    func track(_ event: AnalyticsEvent) {
        guard isConfigured, isEnabled else { return }
        client?.capture(name: event.name, properties: event.properties)
    }
}

@MainActor
final class PostHogAnalyticsClient: AnalyticsClient {
    static func configuration(apiKey: String) -> PostHogConfig {
        let configuration = PostHogConfig(projectToken: apiKey, host: "https://us.i.posthog.com")
        configuration.captureApplicationLifecycleEvents = false
        configuration.errorTrackingConfig.autoCapture = false
        return configuration
    }

    init(apiKey: String) {
        PostHogSDK.shared.setup(Self.configuration(apiKey: apiKey))
    }

    func capture(name: String, properties: [String: String]) {
        PostHogSDK.shared.capture(name, properties: properties)
    }

    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }
}

@MainActor
enum AppAnalytics {
    static let shared = AnalyticsService(
        apiKey: Bundle.main.object(forInfoDictionaryKey: "PostHogProjectAPIKey") as? String
    )
}
