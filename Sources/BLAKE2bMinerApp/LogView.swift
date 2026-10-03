import MinerCore
import SwiftUI

struct LogView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.log) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: line.text))
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
        .frame(minWidth: 620, minHeight: 360)
    }

    /// Highlights found blocks and accepted shares, and problems.
    private func color(for text: String) -> Color {
        if text.contains("BLOCK") || text.contains("accepted") { return .green }
        if text.contains("Problem") || text.contains("rejected") { return .orange }
        return .primary
    }
}
