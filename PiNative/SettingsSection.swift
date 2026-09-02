import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case projects
    case models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .projects: "Projects"
        case .models: "Models"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .projects: "folder"
        case .models: "sparkles"
        }
    }
}
