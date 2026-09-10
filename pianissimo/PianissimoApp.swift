//
//  PianissimoApp.swift
//  Pianissimo
//
//  Created by Léo  Acqueberge  on 6/23/26.
//

import SwiftUI
import Combine
import AppKit

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

/// Une seule instance du lecteur, ouverte à la demande (pas au lancement).
enum MIDIPlayerWindow: String, Codable, Hashable {
    case main
}

@main
struct PianissimoApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var recentFiles = RecentFilesStore()

    init() {
        AppAppearance.migrateFromLegacyThemeIfNeeded()
        PlayerWindowFullscreen.startObserving()
    }

    var body: some Scene {
        WindowGroup("Pianissimo") {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(recentFiles)
                .appAppearance()
        }
        .windowResizability(.automatic)
        .defaultSize(width: 520, height: 640)

        WindowGroup("MIDI Player", id: AppModel.playerWindowID, for: MIDIPlayerWindow.self) { _ in
            MIDIPlayerWindowView()
                .environmentObject(appModel)
                .appAppearance()
        } defaultValue: {
            .main
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 660)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
        }
    }
}

struct MIDIPlayerWindowView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        MIDIPlayerView(url: appModel.playerURL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PlayerWindowFullscreenProbe())
    }
}

/// `Window` SwiftUI est une fenêtre utilitaire : le bouton vert zoome au lieu
/// du plein écran. On force le comportement d'une fenêtre principale.
enum PlayerWindowFullscreen {
    static func startObserving() {
        _ = observers
    }

    private static let observers: [NSObjectProtocol] = {
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSApplication.didBecomeActiveNotification
        ]
        return names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                NSApp.windows.forEach(configureIfNeeded)
            }
        }
    }()

    static func configureIfNeeded(_ window: NSWindow) {
        let id = window.identifier?.rawValue ?? ""
        let title = window.title
        let looksLikePlayer = title == "MIDI Player"
            || id.localizedCaseInsensitiveContains("midiPlayer")
            || id.localizedCaseInsensitiveContains("MIDI Player")
        guard looksLikePlayer else { return }
        configure(window)
    }

    static func configure(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        behavior.remove(.fullScreenAuxiliary)
        behavior.remove(.fullScreenNone)
        behavior.insert(.fullScreenPrimary)
        behavior.insert(.fullScreenAllowsTiling)
        if window.collectionBehavior != behavior {
            window.collectionBehavior = behavior
        }
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        window.standardWindowButton(.zoomButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.alphaValue = 1
    }
}

private struct PlayerWindowFullscreenProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.install()
    }

    private final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func install() {
            guard let window else { return }
            PlayerWindowFullscreen.configure(window)
            DispatchQueue.main.async {
                PlayerWindowFullscreen.configure(window)
            }
        }
    }
}
