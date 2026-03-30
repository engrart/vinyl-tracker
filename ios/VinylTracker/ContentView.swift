import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CollectionView()
                .tabItem {
                    Label("Collection", systemImage: "square.grid.2x2.fill")
                }

            AddRecordView()
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
