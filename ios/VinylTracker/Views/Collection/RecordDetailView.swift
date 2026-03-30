import SwiftUI

struct RecordDetailView: View {
    let record: Record

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                coverArtHeader

                VStack(alignment: .leading, spacing: 20) {
                    titleBlock
                    Divider()
                    metadataGrid
                    if let notes = record.notes, !notes.isEmpty {
                        notesBlock(notes)
                    }
                    if let mbid = record.mbid {
                        mbidBlock(mbid)
                    }
                }
                .padding()
            }
        }
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var coverArtHeader: some View {
        Group {
            if let urlStr = record.primaryImageUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                    default:
                        placeholderSquare
                    }
                }
            } else {
                placeholderSquare
            }
        }
        .clipShape(Rectangle())
    }

    private var placeholderSquare: some View {
        Rectangle()
            .foregroundStyle(.secondary.opacity(0.12))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.title)
                .font(.title2.bold())
            Text(record.artist)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            metadataRow("Year",       value: record.year.map(String.init))
            metadataRow("Genre",      value: record.genre)
            metadataRow("Condition",  value: record.condition?.displayName)
            metadataRow("Added",      value: record.dateAdded.formatted(date: .abbreviated, time: .omitted))
        }
    }

    @ViewBuilder
    private func metadataRow(_ label: String, value: String?) -> some View {
        GridRow {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value ?? "—")
                .font(.subheadline)
        }
    }

    private func notesBlock(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(.secondary)
            Text(notes)
                .font(.body)
        }
    }

    private func mbidBlock(_ mbid: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MusicBrainz ID")
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(.secondary)
            Text(mbid)
                .font(.caption)
                .foregroundStyle(.blue)
                .textSelection(.enabled)
        }
    }
}
