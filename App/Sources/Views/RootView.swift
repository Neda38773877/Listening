import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case meetings, words, review, search, dashboard, settings
}

struct RootView: View {
    @State private var tab: AppTab = .meetings
    @EnvironmentObject private var inbox: ImportInbox

    var body: some View {
        TabView(selection: $tab) {
            Tab("Meetings", systemImage: "waveform", value: AppTab.meetings) {
                MeetingListView()
            }
            Tab("Words", systemImage: "character.book.closed", value: AppTab.words) {
                WordListView()
            }
            Tab("Review", systemImage: "rectangle.stack", value: AppTab.review) {
                ReviewHomeView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchView()
            }
            Tab("Progress", systemImage: "chart.bar", value: AppTab.dashboard) {
                DashboardView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background(TranslationHost())
        .onChange(of: inbox.showImport) { _, show in if show { tab = .meetings } }
    }
}
