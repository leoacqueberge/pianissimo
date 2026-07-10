//
//  PianissimoDesign.swift
//  Pianissimo
//

import SwiftUI

// MARK: - App mode

enum AppMode: String, CaseIterable, Identifiable {
    case full
    case pianoToMidi
    case playerOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Full pipeline"
        case .pianoToMidi: return "Piano to MIDI"
        case .playerOnly: return "MIDI player"
        }
    }

    var subtitle: String {
        switch self {
        case .full: return "Audio → MIDI → player"
        case .pianoToMidi: return "Transcription only"
        case .playerOnly: return "Open a MIDI file"
        }
    }

    var icon: String {
        switch self {
        case .full: return "pianokeys.inverse"
        case .pianoToMidi: return "waveform"
        case .playerOnly: return "play.rectangle"
        }
    }

    var engineMode: String { "both" }

    var opensPlayerOnSuccess: Bool { self == .full }

    func pipelineLabels(sourceType: AudioSourceType) -> [String] {
        switch (self, sourceType) {
        case (.full, .mixed):
            return ["Choose file", "Isolate piano", "Transcribe to MIDI", "Save & play"]
        case (.full, .pianoOnly):
            return ["Choose file", "Transcribe to MIDI", "Save & play"]
        case (.pianoToMidi, .mixed):
            return ["Choose file", "Isolate piano", "Transcribe to MIDI", "Save"]
        case (.pianoToMidi, .pianoOnly):
            return ["Choose file", "Transcribe to MIDI", "Save"]
        case (.playerOnly, _):
            return ["Open MIDI", "Practice"]
        }
    }

    var pipelineLabels: [String] {
        pipelineLabels(sourceType: .mixed)
    }

    var infoSteps: [(icon: String, title: String, detail: String)] {
        switch self {
        case .full:
            return [
                (
                    "waveform.badge.minus",
                    "Isolate the Piano",
                    "Your song is processed to remove voice and other instruments to keep only the piano track."
                ),
                (
                    "pianokeys",
                    "Waveform to MIDI",
                    "The piano track is converted to a MIDI file."
                ),
                (
                    "play.rectangle.on.rectangle",
                    "Learn and Play",
                    "The MIDI visualizer opens so you can learn and play your song."
                )
            ]
        case .pianoToMidi:
            return [
                (
                    "waveform.badge.minus",
                    "Isolate the Piano",
                    "Your song is processed to remove voice and other instruments to keep only the piano track."
                ),
                (
                    "pianokeys",
                    "Waveform to MIDI",
                    "The piano track is converted to a MIDI file and saved to your Music folder."
                )
            ]
        case .playerOnly:
            return [
                (
                    "pianokeys",
                    "MIDI Visualizer",
                    "Open a MIDI file to scroll through the score while you play on your keyboard."
                ),
                (
                    "metronome",
                    "Practice at Your Pace",
                    "Adjust speed, loop sections, and follow the falling notes."
                )
            ]
        }
    }
}

// MARK: - Audio source (mixed vs piano-only)

enum AudioSourceType: String, CaseIterable, Identifiable {
    case mixed
    case pianoOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed: return "Mixed track"
        case .pianoOnly: return "Piano only"
        }
    }

    var subtitle: String {
        switch self {
        case .mixed: return "Voice & instruments"
        case .pianoOnly: return "Skip isolation · faster"
        }
    }

    var icon: String {
        switch self {
        case .mixed: return "person.wave.2.fill"
        case .pianoOnly: return "pianokeys"
        }
    }

    var engineMode: String {
        switch self {
        case .mixed: return "both"
        case .pianoOnly: return "transcribe"
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

    /// Rough CPU estimate. Mixed: Demucs + transcription (~2.5×). Piano only: transcription (~1×).
    static func estimatedMinutes(
        duration: Double,
        useSegment: Bool,
        segmentStart: Double,
        segmentEnd: Double,
        sourceType: AudioSourceType = .mixed
    ) -> Int {
        let effective = useSegment ? max(1, segmentEnd - segmentStart) : max(1, duration)
        let multiplier = sourceType == .pianoOnly ? 1.0 : 2.5
        return max(1, Int(ceil((effective / 60.0) * multiplier)))
    }
}
