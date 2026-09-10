//
//  PianissimoDesign.swift
//  Pianissimo
//

import SwiftUI

// MARK: - App mode

enum AppMode: String, CaseIterable, Identifiable {
    case mixedTrack
    case pianoOnly
    case playerOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixedTrack: return "From a song"
        case .pianoOnly: return "From piano"
        case .playerOnly: return "MIDI player"
        }
    }

    var subtitle: String {
        switch self {
        case .mixedTrack: return "Isolate piano, then transcribe"
        case .pianoOnly: return "Piano audio → MIDI"
        case .playerOnly: return "Open a score"
        }
    }

    var icon: String {
        switch self {
        case .mixedTrack: return "person.wave.2.fill"
        case .pianoOnly: return "pianokeys.inverse"
        case .playerOnly: return "play.rectangle"
        }
    }

    var engineMode: String {
        switch self {
        case .mixedTrack: return "both"
        case .pianoOnly: return "transcribe"
        case .playerOnly: return "transcribe"
        }
    }

    var isolatesPiano: Bool { self == .mixedTrack }
    var opensPlayerOnSuccess: Bool { self != .playerOnly }

    var pipelineLabels: [String] {
        switch self {
        case .mixedTrack:
            return ["Choose file", "Isolate piano", "Transcribe to MIDI", "Save & play"]
        case .pianoOnly:
            return ["Choose file", "Transcribe to MIDI", "Save & play"]
        case .playerOnly:
            return ["Open MIDI", "Practice"]
        }
    }

    func stepIndex(for phase: ProcessingPhase) -> Int {
        let isolate = isolatesPiano
        switch phase {
        case .idle:
            return 0
        case .preparing:
            return 1
        case .separating:
            return isolate ? 1 : 1
        case .transcribing:
            return isolate ? 2 : 1
        case .saving, .done:
            return max(0, pipelineLabels.count - 1)
        case .failed:
            return max(0, pipelineLabels.count - 1)
        }
    }

}

// MARK: - Processing phase

enum ProcessingPhase: Int, Comparable {
    case idle = 0
    case preparing = 1
    case separating = 2
    case transcribing = 3
    case saving = 4
    case done = 5
    case failed = 6

    static func < (lhs: ProcessingPhase, rhs: ProcessingPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Home theme (aligned with MIDI player palette)

struct HomeTheme {
    let palette: PianoPalette
    let isDark: Bool

    init(isDark: Bool) {
        self.isDark = isDark
        palette = isDark ? .dark : .light
    }

    var background: Color { palette.background }
    var cardFill: Color { palette.toolbarBg }
    var cardStroke: Color { palette.toolbarBorder }
    var accent: Color { palette.accent }
    var text: Color { palette.text }
    var subtleText: Color { palette.subtleText }
    var dropzoneFill: Color { palette.accent.opacity(isDark ? 0.10 : 0.06) }
    var dropzoneActiveFill: Color { palette.accent.opacity(isDark ? 0.22 : 0.14) }
    var divider: Color { palette.toolbarBorder }
    var success: Color { isDark ? Color(red: 0.35, green: 0.78, blue: 0.52) : Color(red: 0.18, green: 0.62, blue: 0.38) }
    var mono: Font { .system(.caption, design: .monospaced) }
}

private struct HomeThemeKey: EnvironmentKey {
    static let defaultValue = HomeTheme(isDark: false)
}

extension EnvironmentValues {
    var homeTheme: HomeTheme {
        get { self[HomeThemeKey.self] }
        set { self[HomeThemeKey.self] = newValue }
    }
}

// MARK: - Appearance

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let storageKey = "appAppearance"
    static let legacyDarkKey = "isDarkTheme"

    static func migrateFromLegacyThemeIfNeeded() {
        guard UserDefaults.standard.object(forKey: storageKey) == nil else { return }
        if UserDefaults.standard.bool(forKey: legacyDarkKey) {
            UserDefaults.standard.set(AppAppearance.dark.rawValue, forKey: storageKey)
        }
    }
}

private struct AppAppearanceModifier: ViewModifier {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance.colorScheme)
    }
}

extension View {
    func appAppearance() -> some View {
        modifier(AppAppearanceModifier())
    }
}

enum SegmentLimits {
    static let minDuration: Double = 3
}

// MARK: - Time helpers

enum PianissimoFormatters {
    static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Rough estimate. Mixed: Demucs + transcription (~2.5×). Piano only: transcription (~1×).
    static func estimatedMinutes(
        duration: Double,
        useSegment: Bool,
        segmentStart: Double,
        segmentEnd: Double,
        isolatesPiano: Bool
    ) -> Int {
        let effective = useSegment ? max(1, segmentEnd - segmentStart) : max(1, duration)
        let multiplier = isolatesPiano ? 2.5 : 1.0
        return max(1, Int(ceil((effective / 60.0) * multiplier)))
    }
}
