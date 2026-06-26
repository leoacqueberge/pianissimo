//
//  MIDIData.swift
//  Pianissimo
//
//  Parseur Standard MIDI File (SMF) maison + modèle de notes.
//  Aucune dépendance externe : on lit le binaire et on convertit les
//  ticks en secondes via la carte de tempo du fichier.
//

import Foundation

/// Une note jouable, exprimée en secondes (prête pour l'affichage et la synchro).
struct MIDINote: Identifiable, Equatable {
    let id = UUID()
    var pitch: Int        // numéro MIDI 0...127 (un piano = 21...108)
    var start: Double     // secondes
    var duration: Double  // secondes
    var velocity: Int     // 0...127
    var track: Int        // index de piste d'origine

    var end: Double { start + duration }
}

/// Résultat du parsing d'un fichier MIDI.
struct ParsedMIDI {
    var notes: [MIDINote]
    var duration: Double
}

enum MIDIParseError: LocalizedError {
    case notAFile
    case badHeader
    case truncated

    var errorDescription: String? {
        switch self {
        case .notAFile: return "File not found."
        case .badHeader: return "Invalid MIDI header (missing MThd)."
        case .truncated: return "Corrupted or truncated MIDI file."
        }
    }
}

enum MIDIFile {

    /// Parse un fichier .mid depuis une URL.
    static func parse(url: URL) throws -> ParsedMIDI {
        guard let data = try? Data(contentsOf: url) else { throw MIDIParseError.notAFile }
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> ParsedMIDI {
        let bytes = [UInt8](data)
        var cursor = 0

        func need(_ n: Int) throws {
            if cursor + n > bytes.count { throw MIDIParseError.truncated }
        }
        func read32() throws -> Int {
            try need(4)
            let v = (Int(bytes[cursor]) << 24) | (Int(bytes[cursor + 1]) << 16)
                  | (Int(bytes[cursor + 2]) << 8) | Int(bytes[cursor + 3])
            cursor += 4
            return v
        }
        func read16() throws -> Int {
            try need(2)
            let v = (Int(bytes[cursor]) << 8) | Int(bytes[cursor + 1])
            cursor += 2
            return v
        }

        // En-tête "MThd"
        try need(4)
        guard bytes[0] == 0x4D, bytes[1] == 0x54, bytes[2] == 0x68, bytes[3] == 0x64 else {
            throw MIDIParseError.badHeader
        }
        cursor = 4
        let headerLen = try read32()
        _ = try read16() // format
        let numTracks = try read16()
        let division = try read16()
        // On gère le cas standard PPQ (ticks par noire). Le SMPTE est rare ici.
        let ppq: Double = (division & 0x8000) == 0 ? Double(division) : 480
        // Sauter d'éventuels octets d'en-tête supplémentaires.
        cursor = 8 + headerLen

        struct RawNote { var pitch: Int; var onTick: Int; var offTick: Int; var velocity: Int; var track: Int }
        var rawNotes: [RawNote] = []
        var tempoEvents: [(tick: Int, usPerQuarter: Int)] = []
        var maxTick = 0

        for trackIndex in 0..<numTracks {
            if cursor + 8 > bytes.count { break }
            // Chunk "MTrk"
            let isTrack = bytes[cursor] == 0x4D && bytes[cursor + 1] == 0x54
                && bytes[cursor + 2] == 0x72 && bytes[cursor + 3] == 0x6B
            cursor += 4
            let trackLen = try read32()
            let trackEnd = min(cursor + trackLen, bytes.count)
            if !isTrack { cursor = trackEnd; continue }

            var absTick = 0
            var runningStatus: UInt8 = 0
            // notes en cours d'appui : clé = (canal << 8 | pitch) -> pile de (tick, vel)
            var openNotes: [Int: [(tick: Int, vel: Int)]] = [:]

            func readVarLen() throws -> Int {
                var value = 0
                while true {
                    try need(1)
                    let b = bytes[cursor]; cursor += 1
                    value = (value << 7) | Int(b & 0x7F)
                    if b & 0x80 == 0 { break }
                }
                return value
            }

            while cursor < trackEnd {
                let delta = try readVarLen()
                absTick += delta

                try need(1)
                var status = bytes[cursor]
                if status < 0x80 {
                    // Running status : l'octet courant est une donnée, pas un statut.
                    status = runningStatus
                } else {
                    cursor += 1
                }

                if status == 0xFF {
                    // Méta-événement
                    try need(1)
                    let metaType = bytes[cursor]; cursor += 1
                    let len = try readVarLen()
                    try need(len)
                    if metaType == 0x51, len == 3 {
                        let us = (Int(bytes[cursor]) << 16) | (Int(bytes[cursor + 1]) << 8) | Int(bytes[cursor + 2])
                        tempoEvents.append((tick: absTick, usPerQuarter: us))
                    }
                    cursor += len
                    runningStatus = 0
                } else if status == 0xF0 || status == 0xF7 {
                    // SysEx : on saute
                    let len = try readVarLen()
                    try need(len)
                    cursor += len
                    runningStatus = 0
                } else {
                    let type = status & 0xF0
                    let channel = Int(status & 0x0F)
                    runningStatus = status
                    switch type {
                    case 0x90, 0x80: // note on / note off
                        try need(2)
                        let pitch = Int(bytes[cursor]); let vel = Int(bytes[cursor + 1])
                        cursor += 2
                        let key = (channel << 8) | pitch
                        let isNoteOn = (type == 0x90) && vel > 0
                        if isNoteOn {
                            openNotes[key, default: []].append((tick: absTick, vel: vel))
                        } else {
                            if var stack = openNotes[key], !stack.isEmpty {
                                let on = stack.removeFirst()
                                openNotes[key] = stack
                                rawNotes.append(RawNote(pitch: pitch, onTick: on.tick,
                                                        offTick: absTick, velocity: on.vel,
                                                        track: trackIndex))
                            }
                        }
                        maxTick = max(maxTick, absTick)
                    case 0xA0, 0xB0, 0xE0: // 2 octets de données
                        try need(2); cursor += 2
                    case 0xC0, 0xD0: // 1 octet de donnée
                        try need(1); cursor += 1
                    default:
                        // Statut inconnu : on s'arrête sur cette piste pour éviter la dérive.
                        cursor = trackEnd
                    }
                }
            }

            // Fermer les notes restées ouvertes en fin de piste.
            for (key, stack) in openNotes {
                let pitch = key & 0xFF
                for on in stack {
                    rawNotes.append(RawNote(pitch: pitch, onTick: on.tick,
                                            offTick: maxTick, velocity: on.vel,
                                            track: trackIndex))
                }
            }

            cursor = trackEnd
        }

        // Construire la carte de tempo (segments cumulés en secondes).
        let segs = buildTempoSegments(tempoEvents, ppq: ppq)
        func ticksToSeconds(_ tick: Int) -> Double {
            var chosen = segs[0]
            for s in segs {
                if s.tick <= tick { chosen = s } else { break }
            }
            return chosen.sec + Double(tick - chosen.tick) * chosen.usPerQ / 1_000_000.0 / ppq
        }

        var notes: [MIDINote] = []
        notes.reserveCapacity(rawNotes.count)
        for r in rawNotes {
            let start = ticksToSeconds(r.onTick)
            let end = ticksToSeconds(max(r.offTick, r.onTick))
            notes.append(MIDINote(pitch: r.pitch, start: start,
                                  duration: max(0.02, end - start),
                                  velocity: r.velocity, track: r.track))
        }
        notes.sort { $0.start < $1.start }

        let totalDuration = max(notes.map { $0.end }.max() ?? 0, ticksToSeconds(maxTick))
        return ParsedMIDI(notes: notes, duration: totalDuration)
    }

    private struct TempoSeg { let tick: Int; let sec: Double; let usPerQ: Double }

    private static func buildTempoSegments(_ events: [(tick: Int, usPerQuarter: Int)],
                                           ppq: Double) -> [TempoSeg] {
        var evs = events.sorted { $0.tick < $1.tick }
        if evs.first?.tick != 0 {
            evs.insert((tick: 0, usPerQuarter: 500_000), at: 0) // 120 BPM par défaut
        }
        var segs: [TempoSeg] = []
        for (i, e) in evs.enumerated() {
            if i == 0 {
                segs.append(TempoSeg(tick: e.tick, sec: 0, usPerQ: Double(e.usPerQuarter)))
            } else {
                let prev = segs[i - 1]
                let sec = prev.sec + Double(e.tick - prev.tick) * prev.usPerQ / 1_000_000.0 / ppq
                segs.append(TempoSeg(tick: e.tick, sec: sec, usPerQ: Double(e.usPerQuarter)))
            }
        }
        return segs
    }
}
