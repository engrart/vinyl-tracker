import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class CollectionViewModel: ObservableObject {
    @Published var records: [Record] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var searchText = ""
    @Published var selectedGenre: String?

    private let api = APIClient.shared

    var availableGenres: [String] {
        Array(Set(records.compactMap(\.genre))).sorted()
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            records = try await api.fetchRecords(
                search: searchText.isEmpty ? nil : searchText,
                genre:  selectedGenre
            )
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func delete(record: Record) async {
        do {
            try await api.deleteRecord(id: record.id.uuidString)
            records.removeAll { $0.id == record.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - View

struct CollectionView: View {
    @StateObject private var vm = CollectionViewModel()

    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.records.isEmpty {
                    ProgressView("Loading collection…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.records.isEmpty && !vm.isLoading {
                    ContentUnavailableView(
                        "No Records Yet",
                        systemImage: "music.note.list",
                        description: Text("Tap Add to scan your first record.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(vm.records) { record in
                                NavigationLink(destination: RecordDetailView(record: record)) {
                                    RecordCardView(record: record)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await vm.delete(record: record) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("My Collection (\(vm.records.count))")
            .searchable(text: $vm.searchText, prompt: "Search artist or title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    genreFilterMenu
                }
            }
            .overlay(alignment: .bottom) {
                if let error = vm.error {
                    Text(error)
                        .font(.caption)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task { await vm.load() }
        .onChange(of: vm.searchText)   { _, _ in Task { await vm.load() } }
        .onChange(of: vm.selectedGenre) { _, _ in Task { await vm.load() } }
    }

    private var genreFilterMenu: some View {
        Menu {
            Button {
                vm.selectedGenre = nil
            } label: {
                Label("All Genres", systemImage: vm.selectedGenre == nil ? "checkmark" : "")
            }
            if !vm.availableGenres.isEmpty {
                Divider()
                ForEach(vm.availableGenres, id: \.self) { genre in
                    Button {
                        vm.selectedGenre = genre
                    } label: {
                        Label(genre, systemImage: vm.selectedGenre == genre ? "checkmark" : "")
                    }
                }
            }
        } label: {
            Image(systemName: vm.selectedGenre != nil
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle")
        }
    }
}

// MARK: - Card

struct RecordCardView: View {
    let record: Record

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            coverImage
                .frame(height: 155)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(record.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let year = record.year {
                    Text(String(year))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let urlString = record.primaryImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .foregroundStyle(.secondary.opacity(0.15))
            .overlay {
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
    }
}
