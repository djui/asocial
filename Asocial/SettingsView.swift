import SwiftUI
import WebKit

struct SettingsView: View {
    @ObservedObject private var settings = FilterSettings.shared
    @ObservedObject private var stats = Stats.shared
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(stats.today)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing))
                            .contentTransition(.numericText())
                        Text(stats.today == 1 ? "distraction skipped today" : "distractions skipped today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                ForEach(Platform.allCases) { platform in
                    Section(platform.name) {
                        ForEach(platform.filters) { filter in
                            Toggle(isOn: Binding(get: { settings.isOn(filter) }, set: { settings.set(filter, on: $0) })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Hide \(filter.title)")
                                    Text(filter.detail).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Sign Out of Everything", role: .destructive) { confirmingSignOut = true }
                } footer: {
                    Text("Asocial keeps your sign-ins and settings on this device only. It has no server and collects nothing.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Link("Source on GitHub", destination: URL(string: "https://github.com/djui/asocial")!)
                    Link("Website", destination: URL(string: "https://djui.github.io/asocial/")!)
                } footer: {
                    Text("Asocial isn't affiliated with Instagram, YouTube, Facebook, Meta, or Google.")
                }
            }
            .navigationTitle("Asocial")
            .onAppear { stats.refresh() }
            .confirmationDialog("Sign out of every site in Asocial?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    WKWebsiteDataStore.default().removeData(
                        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
                    ) {
                        NotificationCenter.default.post(name: .asocialFiltersChanged, object: nil)
                    }
                }
            }
        }
    }
}
