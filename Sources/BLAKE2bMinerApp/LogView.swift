import MinerCore
import SwiftUI

struct LogView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.log.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.contains("BLOCK") || line.contains("accepted") ? .green
                                                 : line.contains("Problem") || line.contains("rejected") ? .orange : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(10)
                    .textSelection(.enabled)
                }
                .onChange(of: model.log.count) { n in
                    if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
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
}
