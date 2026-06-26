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

    var pipelineLabels: [String] {
        switch self {
        case .full:
            return ["Choose file", "Isolate piano", "Transcribe to MIDI", "Save & play"]
        case .pianoToMidi:
            return ["Choose file", "Isolate piano", "Transcribe to MIDI", "Save"]
        case .playerOnly:
            return ["Open MIDI", "Practice"]
        }
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

    static let shared = HomeTheme(palette: .light)

    var background: Color { palette.background }
    var cardFill: Color { Color.white.opacity(0.92) }
    var cardStroke: Color { palette.toolbarBorder }
    var accent: Color { palette.accent }
    var text: Color { palette.text }
    var subtleText: Color { palette.subtleText }
    var dropzoneFill: Color { palette.accent.opacity(0.06) }
    var dropzoneActiveFill: Color { palette.accent.opacity(0.14) }
    var divider: Color { palette.toolbarBorder }
    var success: Color { Color(red: 0.18, green: 0.62, blue: 0.38) }
    var mono: Font { .system(.caption, design: .monospaced) }
}

// MARK: - Time helpers

enum PianissimoFormatters {
    static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Rough CPU estimate: ~2.5× audio duration for Demucs + transcription.
    static func estimatedMinutes(
        duration: Double,
        useSegment: Bool,
        segmentStart: Double,
        segmentEnd: Double
    ) -> Int {
        let effective = useSegment ? max(1, segmentEnd - segmentStart) : max(1, duration)
        return max(1, Int(ceil((effective / 60.0) * 2.5)))
    }
}
