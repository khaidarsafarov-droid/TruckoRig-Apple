import Foundation

/// Screens a home-screen widget (or a `truckorig://` URL) is allowed to open.
///
/// The allow-list matches Android `WidgetDeepLink.sanitizeIncomingRoute`: unknown values open
/// the journal, and a blank value is not a deep link. Opening one of these never writes data.
public enum WidgetRoute: String, Equatable, Sendable {
    case home
    case camera
    case scanner
    case addDiesel = "add_diesel"
    case analytics
    case weeklyGoal = "weekly_goal"
    case addLoad = "add_load"
}

/// Builds and parses `truckorig://` links used by `Link` / `widgetURL`.
public enum WidgetDeepLink {

    public static let scheme = "truckorig"

    public static func url(for route: WidgetRoute) -> URL {
        URL(string: "\(scheme)://\(route.rawValue)")!
    }

    /// `nil` when the URL is not ours. A recognized scheme with an unknown path opens home.
    public static func route(from url: URL) -> WidgetRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let combined: String
        if host.isEmpty {
            combined = path
        } else if host == "app" {
            combined = path
        } else if path.isEmpty {
            combined = host
        } else {
            combined = "\(host)/\(path)"
        }
        return sanitize(combined)
    }

    /// Blank input is not a deep link. Anything else that is not on the list opens home.
    public static func sanitize(_ raw: String?) -> WidgetRoute? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        switch trimmed {
        case "home":
            return .home
        case "camera", "attach_pick/camera":
            return .camera
        case "scanner", "attach_pick/scanner":
            return .scanner
        case "diesel", "add_diesel":
            return .addDiesel
        case "analytics", "stats":
            return .analytics
        case "weekly_goal":
            return .weeklyGoal
        case "add_load":
            return .addLoad
        case "journal_this_week":
            return .home
        default:
            return .home
        }
    }
}
