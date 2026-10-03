import Foundation

/// A page of the main window, listed in its sidebar.
public enum Page: String, CaseIterable, Identifiable {
    case overview, mining, performance, node, diagnostics, log, about

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .mining: return "Mining"
        case .performance: return "Performance"
        case .node: return "Node"
        case .diagnostics: return "Diagnostics"
        case .log: return "Log"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .mining: return "cube"
        case .performance: return "speedometer"
        case .node: return "server.rack"
        case .diagnostics: return "stethoscope"
        case .log: return "text.alignleft"
        case .about: return "info.circle"
        }
    }

    /// Sidebar groups, in order.
    static let groups: [(title: String?, pages: [Page])] = [
        (nil, [.overview]),
        ("Settings", [.mining, .performance, .node]),
        ("Tools", [.diagnostics, .log]),
        (nil, [.about]),
    ]
}
