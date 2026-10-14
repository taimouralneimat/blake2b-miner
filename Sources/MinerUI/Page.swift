import Foundation

/// A page of the main window, listed in its sidebar.
public enum Page: String, CaseIterable, Identifiable {
    case overview, earnings, pools, mining, performance, node, diagnostics, log, about

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .earnings: return "Earnings"
        case .pools: return "Pools"
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
        case .earnings: return "bitcoinsign.circle"
        case .pools: return "person.3"
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
        (nil, [.overview, .earnings, .pools]),
        ("Settings", [.mining, .performance, .node]),
        ("Tools", [.diagnostics, .log]),
        (nil, [.about]),
    ]
}
