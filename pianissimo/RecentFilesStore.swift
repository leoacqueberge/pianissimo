//
//  RecentFilesStore.swift
//  Pianissimo
//

import Foundation
import Combine

final class RecentFilesStore: ObservableObject {
    @Published private(set) var audioFiles: [URL] = []
    @Published private(set) var midiFiles: [URL] = []

    private let audioKey = "recentAudioFiles"
    private let midiKey = "recentMIDIFiles"
    private let limit = 5

    init() {
        audioFiles = load(key: audioKey)
        midiFiles = load(key: midiKey)
    }

    func addAudio(_ url: URL) {
        audioFiles = prepend(url, to: audioFiles)
        save(audioFiles, key: audioKey)
    }

    func addMIDI(_ url: URL) {
        midiFiles = prepend(url, to: midiFiles)
        save(midiFiles, key: midiKey)
    }

    private func prepend(_ url: URL, to list: [URL]) -> [URL] {
        var next = list.filter { $0 != url }
        next.insert(url, at: 0)
        return Array(next.prefix(limit))
    }

    private func load(key: String) -> [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: key) else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func save(_ urls: [URL], key: String) {
        UserDefaults.standard.set(urls.map(\.path), forKey: key)
    }
}
