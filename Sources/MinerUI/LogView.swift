import MinerCore
import SwiftUI

public struct LogView: View {
    @EnvironmentObject var model: AppModel

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.log) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Self.color(for: line.text))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .textSelection(.enabled)
                }
                .onChange(of: model.log.last?.id) { id in
                    if let id = id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                Text("\(model.foundBlocks.count) solved block(s) on record").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show Found Blocks") { model.revealFoundBlocks() }
                Button("Show Log File") { model.revealLogFile() }
            }
            .padding(8)
        }
    }

    /// Highlights found blocks and accepted shares, and problems.
    /// Green only for your own successes (a block you solved, an accepted share);
    /// other miners' blocks ("NEW NETWORK BLOCK") stay neutral.
    static func color(for text: String) -> Color {
        if text.contains("BLOCK SOLVED") || text.contains("BLOCK FOUND") || text.contains("Share accepted")
            || text.hasSuffix(" accepted") { return .green }
        if text.contains("Problem") || text.contains("rejected") || text.contains("ERROR") { return .orange }
        return .primary
    }
}
