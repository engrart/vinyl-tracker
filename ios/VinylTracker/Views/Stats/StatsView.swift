import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var records: [Record] = []
    @Published var isLoading = false

    private let api = APIClient.shared

    var totalCount: Int { records.count }

    var byGenre: [(label: String, count: Int)] {
        grouped(by: \.genre)
    }

    var byDecade: [(label: String, count: Int)] {
        Dictionary(grouping: records.compactMap(\.year).map { ($0 / 10) * 10 }, by: { $0 })
            .map { (label: "\($0.key)s", count: $0.value.count) }
            .sorted { $0.label < $1.label }
    }

    var topArtists: [(label: String, count: Int)] {
        Array(grouped(by: \.artist).prefix(10))
    }

    func load() async {
        isLoading = true
        records = (try? await api.fetchRecords()) ?? []
        isLoading = false
    }

    private func grouped(by keyPath: KeyPath<Record, String?>) -> [(label: String, count: Int)] {
        Dictionary(grouping: records.compactMap { $0[keyPath: keyPath] }, by: { $0 })
            .map { (label: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private func grouped(by keyPath: KeyPath<Record, String>) -> [(label: String, count: Int)] {
        Dictionary(grouping: records.map { $0[keyPath: keyPath] }, by: { $0 })
            .map { (label: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}

// MARK: - View

struct StatsView: View {
    @StateObject private var vm = StatsViewModel()

    var body: some View {
        NavigationStack {
            List {
                // Summary cards
                Section {
                    HStack(spacing: 12) {
                        StatTile(value: "\(vm.totalCount)", label: "Records",   icon: "music.note.list")
                        StatTile(value: "\(vm.byGenre.count)",   label: "Genres", icon: "music.quarternote.3")
                        StatTile(value: "\(vm.topArtists.count)", label: "Artists", icon: "person.2.fill")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !vm.byGenre.isEmpty {
                    Section("By Genre") {
                        ForEach(vm.byGenre, id: \.label) { item in
                            CountRow(label: item.label, count: item.count, total: vm.totalCount)
                        }
                    }
                }

                if !vm.byDecade.isEmpty {
                    Section("By Decade") {
                        ForEach(vm.byDecade, id: \.label) { item in
                            CountRow(label: item.label, count: item.count, total: vm.totalCount)
                        }
                    }
                }

                if !vm.topArtists.isEmpty {
                    Section("Top Artists") {
                        ForEach(Array(vm.topArtists.enumerated()), id: \.offset) { idx, item in
                            HStack {
                                Text("\(idx + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 20)
                                Text(item.label)
                                Spacer()
                                Text("\(item.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .overlay {
                if vm.isLoading { ProgressView() }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - Subviews

struct StatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CountRow: View {
    let label: String
    let count: Int
    let total: Int

    private var fraction: Double {
        total > 0 ? Double(count) / Double(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                Capsule()
                    .foregroundStyle(.quaternary)
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .foregroundStyle(Color.accentColor)
                            .frame(width: geo.size.width * fraction, height: 4)
                    }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }
}
