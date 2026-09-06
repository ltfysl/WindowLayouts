import Foundation

@Observable
@MainActor
final class LayoutStore {
    private(set) var layouts: [SavedLayout] = []

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Layouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("layouts.json")
        load()
    }

    func add(_ layout: SavedLayout) {
        layouts.append(layout)
        persist()
    }

    func update(_ layout: SavedLayout) {
        guard let index = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        layouts[index] = layout
        persist()
    }

    func delete(_ layout: SavedLayout) {
        layouts.removeAll { $0.id == layout.id }
        persist()
    }

    func duplicate(_ layout: SavedLayout) {
        var copy = layout
        copy.id = UUID()
        copy.name = layout.name + " copy"
        copy.createdAt = .now
        layouts.append(copy)
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? decoder.decode([SavedLayout].self, from: data) else { return }
        layouts = stored
    }

    private func persist() {
        guard let data = try? encoder.encode(layouts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
