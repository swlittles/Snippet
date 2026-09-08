import SwiftUI

struct StorageSettingsView: View {
    @ObservedObject var history: History
    @EnvironmentObject var theme: ThemeStore
    @AppStorage("historyRetentionDays", store: AppEnvironment.defaults) private var savedDays = 0
    @AppStorage("historyRetentionLimit", store: AppEnvironment.defaults) private var savedLimit = 0
    @State private var days = 0
    @State private var limit = 0
    @State private var confirmCleanup = false
    private var policy: HistoryRetention { HistoryRetention(days: days, limit: limit) }
    private var removalCount: Int { history.clips.count - policy.retaining(history.clips, now: Date()).count }
    private var hasChanges: Bool { days != savedDays || limit != savedLimit }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your library stays on this Mac").font(.headline)
            Text("No account required. Clipboard history is kept until you delete it, unless you choose a cleanup rule below. Snippets and favorites are always kept.").font(.caption).foregroundStyle(theme.secondary)
            Picker("Keep clipboard history", selection: $days) {
                Text("Forever").tag(0)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
            }.pointerCursor()
            Picker("Maximum ordinary clips", selection: $limit) {
                Text("Unlimited").tag(0)
                Text("500").tag(500)
                Text("1,000").tag(1000)
                Text("5,000").tag(5000)
                Text("10,000").tag(10000)
            }.pointerCursor()
            Text("Favorites do not count toward either limit. Lowering a limit can permanently remove ordinary clips.").font(.caption).foregroundStyle(theme.secondary)
            Button("Save cleanup rules") {
                if removalCount > 0 { confirmCleanup = true } else { save() }
            }.disabled(!hasChanges).pointerCursor()
            Divider()
            Text("\(history.clips.count.formatted()) clips stored locally · iCloud sync is not enabled.").font(.caption).foregroundStyle(theme.secondary)
        }
        .onAppear { days = savedDays; limit = savedLimit }
        .alert("Apply cleanup rules?", isPresented: $confirmCleanup) {
            Button("Remove \(removalCount) clips", role: .destructive) { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These rules will remove \(removalCount) ordinary clips now and apply to future history. Favorites and snippets will be kept.")
        }
    }
    private func save() {
        savedDays = days
        savedLimit = limit
        history.prune()
    }
}
