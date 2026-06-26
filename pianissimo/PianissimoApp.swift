//
//  PianissimoApp.swift
//  Pianissimo
//
//  Created by Léo  Acqueberge  on 6/23/26.
//

import SwiftUI
import Combine

/// Dossiers par défaut pour l'enregistrement des fichiers produits.
enum PianissimoPaths {
    static var musicDirectory: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music")
    }

    static func outputDirectory() -> URL {
        let dir = musicDirectory.appendingPathComponent("Pianissimo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// État partagé entre la fenêtre principale et la fenêtre du lecteur MIDI.
final class AppModel: ObservableObject {
    static let playerWindowID = "midiPlayer"
    /// Fichier MIDI à ouvrir dans le lecteur (nil = lecteur vide).
    @Published var playerURL: URL?
}

@main
struct PianissimoApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var recentFiles = RecentFilesStore()

    var body: some Scene {
        WindowGroup("Pianissimo") {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(recentFiles)
        }
        .windowResizability(.contentSize)

        // Fenêtre indépendante (non modale) pour le lecteur MIDI.
        Window("MIDI Player", id: AppModel.playerWindowID) {
            MIDIPlayerWindowView()
                .environmentObject(appModel)
        }
        .defaultSize(width: 1000, height: 660)
    }
}

/// Contenu de la fenêtre du lecteur : relit l'URL partagée et sait se fermer.
struct MIDIPlayerWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MIDIPlayerView(url: appModel.playerURL) { dismiss() }
    }
}
