//
//  HomeComponents.swift
//  Pianissimo
//

import SwiftUI

// MARK: - Mode cards

struct ModeCardPicker: View {
    @Binding var selection: AppMode
    var disabled: Bool

    private let theme = HomeTheme.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.text)

            VStack(spacing: 8) {
                ForEach(AppMode.allCases) { mode in
                    ModeCard(
                        mode: mode,
                        isSelected: selection == mode,
                        disabled: disabled
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selection = mode
                        }
                    }
                }
            }
        }
    }
}

private struct ModeCard: View {
    let mode: AppMode
    let isSelected: Bool
    let disabled: Bool
    let action: () -> Void

    private let theme = HomeTheme.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.accent : theme.subtleText)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.text)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.subtleText)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? theme.accent.opacity(0.10) : theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? theme.accent.opacity(0.45) : theme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Drop zone

struct AudioDropzone: View {
    let selectedFileURL: URL?
    let fileDuration: Double?
    let isTargeted: Bool
    let isProcessing: Bool
    let useSegment: Bool
    let segmentStart: Double
    let segmentEnd: Double
    let onTap: () -> Void

    private let theme = HomeTheme.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedFileURL == nil ? "arrow.down.circle" : "music.note")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isTargeted || selectedFileURL != nil ? theme.accent : theme.subtleText)
                .symbolEffect(.bounce, value: isTargeted)

            if let file = selectedFileURL {
                Text(file.lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let duration = fileDuration {
                    Text("duration: \(PianissimoFormatters.formatTime(duration))")
                        .font(theme.mono)
                        .foregroundStyle(theme.subtleText)
                }

                if useSegment, fileDuration != nil {
                    SegmentPreviewBar(
                        duration: fileDuration ?? 1,
                        start: segmentStart,
                        end: segmentEnd
                    )
                    .frame(height: 6)
                    .padding(.horizontal, 8)
                }

                Text("Ready — set the portion, then start")
                    .font(.caption)
                    .foregroundStyle(theme.accent)

                Text("click to change file")
                    .font(.caption2)
                    .foregroundStyle(theme.subtleText)
            } else {
                Text("drop your song here")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                Text("mp3 · wav · m4a · webm · mp4")
                    .font(.caption)
                    .foregroundStyle(theme.subtleText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 148)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isTargeted ? theme.dropzoneActiveFill : theme.dropzoneFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isTargeted ? theme.accent : theme.cardStroke,
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: selectedFileURL == nil ? [6, 4] : [])
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isProcessing { onTap() }
        }
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }
}

private struct SegmentPreviewBar: View {
    let duration: Double
    let start: Double
    let end: Double

    private let theme = HomeTheme.shared

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x0 = duration > 0 ? CGFloat(start / duration) * w : 0
            let x1 = duration > 0 ? CGFloat(end / duration) * w : w

            Capsule()
                .fill(theme.cardStroke)
            Capsule()
                .fill(theme.accent.opacity(0.75))
                .frame(width: max(4, x1 - x0))
                .offset(x: x0)
        }
    }
}

// MARK: - Segment editor with waveform

struct AudioSegmentEditor: View {
    let duration: Double
    @Binding var useSegment: Bool
    @Binding var start: Double
    @Binding var end: Double
    let waveform: [Float]
    let estimatedMinutes: Int

    private let theme = HomeTheme.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("process portion only", isOn: $useSegment)
                .font(.subheadline)
                .toggleStyle(.switch)
                .tint(theme.accent)

            if useSegment {
                WaveformRangeControl(
                    duration: duration,
                    start: $start,
                    end: $end,
                    samples: waveform
                )
                .frame(height: 56)

                HStack {
                    Label(PianissimoFormatters.formatTime(start), systemImage: "arrow.right.to.line")
                    Spacer()
                    Label(PianissimoFormatters.formatTime(end), systemImage: "arrow.left.to.line")
                }
                .font(theme.mono)
                .foregroundStyle(theme.subtleText)

                Text("\(PianissimoFormatters.formatTime(end - start)) selected of \(PianissimoFormatters.formatTime(duration))")
                    .font(.caption)
                    .foregroundStyle(theme.subtleText)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption)
                Text("estimated time: ~\(estimatedMinutes) min")
                    .font(.caption)
            }
            .foregroundStyle(theme.subtleText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        )
    }
}

struct WaveformRangeControl: View {
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    let samples: [Float]

    private let theme = HomeTheme.shared

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.accent.opacity(0.08))

                WaveformBars(samples: samples, color: theme.accent.opacity(0.35))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                if duration > 0 {
                    let x0 = CGFloat(start / duration) * width
                    let x1 = CGFloat(end / duration) * width

                    Rectangle()
                        .fill(theme.accent.opacity(0.18))
                        .frame(width: max(0, x1 - x0))
                        .offset(x: x0)

                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: 2, height: height)
                        .offset(x: x0)

                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: 2, height: height)
                        .offset(x: max(0, x1 - 2))

                    Color.clear
                        .frame(width: 20, height: height)
                        .contentShape(Rectangle())
                        .offset(x: x0 - 10)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = x0 - 10 + value.location.x
                                    let t = min(max(0, Double(x / width) * duration), end - 1)
                                    start = t
                                }
                        )

                    Color.clear
                        .frame(width: 20, height: height)
                        .contentShape(Rectangle())
                        .offset(x: x1 - 10)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = x1 - 10 + value.location.x
                                    let t = max(min(duration, Double(x / width) * duration), start + 1)
                                    end = t
                                }
                        )
                }
            }
        }
    }
}

struct WaveformBars: View {
    let samples: [Float]
    var color: Color = HomeTheme.shared.accent.opacity(0.4)

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 1) {
                ForEach(samples.indices, id: \.self) { i in
                    let amp = CGFloat(samples[i])
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(
                            width: max(1, geo.size.width / CGFloat(samples.count) - 1),
                            height: max(2, amp * geo.size.height)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Pipeline timeline

struct PipelineTimeline: View {
    let mode: AppMode
    let phase: ProcessingPhase
    let currentMessage: String

    private let theme = HomeTheme.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Progress")
                .font(.headline)
                .foregroundStyle(theme.text)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(mode.pipelineLabels.enumerated()), id: \.offset) { index, label in
                    PipelineStepRow(
                        label: label,
                        state: stepState(for: index),
                        isLast: index == mode.pipelineLabels.count - 1,
                        detail: index == activeStepIndex ? currentMessage : nil
                    )
                }
            }

            Spacer(minLength: 0)

            privacyFooter
        }
    }

    private var activeStepIndex: Int {
        switch phase {
        case .idle: return 0
        case .preparing: return 1
        case .separating: return 1
        case .transcribing: return 2
        case .saving: return mode == .playerOnly ? 0 : 3
        case .done: return mode.pipelineLabels.count
        case .failed: return max(0, mode.pipelineLabels.count - 1)
        }
    }

    private func stepState(for index: Int) -> PipelineStepState {
        let active = activeStepIndex
        if phase == .failed && index == active { return .failed }
        if index < active { return .completed }
        if index == active && phase != .done && phase != .idle { return .active }
        if phase == .done { return .completed }
        return .pending
    }

    private var privacyFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.caption)
                .foregroundStyle(theme.subtleText)
            Text("All your data is processed locally on your Mac. No data is collected. AI models run entirely on your machine.")
                .font(.caption)
                .foregroundStyle(theme.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum PipelineStepState {
    case pending, active, completed, failed
}

struct PipelineStepRow: View {
    let label: String
    let state: PipelineStepState
    let isLast: Bool
    let detail: String?

    private let theme = HomeTheme.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                stepIcon
                    .frame(width: 22, height: 22)
                if !isLast {
                    Rectangle()
                        .fill(state == .completed ? theme.success.opacity(0.5) : theme.cardStroke)
                        .frame(width: 2, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.body.weight(state == .active ? .semibold : .regular))
                    .foregroundStyle(state == .pending ? theme.subtleText : theme.text)
                if let detail, state == .active {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.accent)
                        .transition(.opacity)
                }
            }
            .padding(.bottom, isLast ? 0 : 8)
        }
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch state {
        case .pending:
            Circle().strokeBorder(theme.cardStroke, lineWidth: 2)
        case .active:
            ZStack {
                Circle().fill(theme.accent.opacity(0.15))
                ProgressView().controlSize(.small)
            }
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.success)
                .font(.system(size: 20))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 20))
        }
    }
}

// MARK: - Player mode panel

struct PlayerModePanel: View {
    let onOpenMIDI: () -> Void
    let onOpenEmpty: () -> Void

    private let theme = HomeTheme.shared

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(theme.accent)

            Text("learn and play")
                .font(.subheadline.weight(.semibold))
            Text("open an existing midi score in the visualizer.")
                .font(.caption)
                .foregroundStyle(theme.subtleText)
                .multilineTextAlignment(.center)

            Button("open midi file…", action: onOpenMIDI)
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)

            Button("open empty player", action: onOpenEmpty)
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(theme.subtleText)
        }
        .frame(maxWidth: .infinity, minHeight: 148)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.dropzoneFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Recent files

struct RecentFilesSection: View {
    let audioFiles: [URL]
    let midiFiles: [URL]
    let onSelectAudio: (URL) -> Void
    let onSelectMIDI: (URL) -> Void

    private let theme = HomeTheme.shared

    var body: some View {
        if !audioFiles.isEmpty || !midiFiles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)

                if !audioFiles.isEmpty {
                    recentGroup(title: "Audio", files: audioFiles, icon: "waveform", onSelect: onSelectAudio)
                }
                if !midiFiles.isEmpty {
                    recentGroup(title: "MIDI", files: midiFiles, icon: "pianokeys", onSelect: onSelectMIDI)
                }
            }
        }
    }

    private func recentGroup(
        title: String,
        files: [URL],
        icon: String,
        onSelect: @escaping (URL) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.subtleText)
            ForEach(files, id: \.path) { url in
                Button {
                    onSelect(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(theme.text)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Logs overlay

struct LogsOverlay: View {
    @Binding var text: String
    @Binding var isPresented: Bool

    private let theme = HomeTheme.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Console", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.subtleText)
                Spacer()
                Button("clear") { text = "" }
                    .buttonStyle(.borderless)
                    .font(.caption)
                Button {
                    withAnimation { isPresented = false }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                }
                .buttonStyle(.borderless)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "waiting for a task…\n" : text)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .id("LogText")
                }
                .background(theme.palette.stageBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: text) {
                    proxy.scrollTo("LogText", anchor: .bottom)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardFill)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - Idle right panel (mode description)

struct ModeInfoPanel: View {
    let mode: AppMode

    private let theme = HomeTheme.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                ForEach(Array(mode.infoSteps.enumerated()), id: \.offset) { index, step in
                    SplashStepRow(
                        icon: step.icon,
                        title: step.title,
                        detail: step.detail,
                        isLast: index == mode.infoSteps.count - 1
                    )
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(.caption2))
                    .foregroundStyle(.tertiary)
                Text("All your data is processed locally on your Mac. No data is collected. AI models run entirely on your machine.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SplashStepRow: View {
    let icon: String
    let title: String
    let detail: String
    let isLast: Bool

    private let theme = HomeTheme.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.text)
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(theme.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.accent)
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.cardStroke, lineWidth: 1)
            )

            if !isLast {
                Rectangle()
                    .fill(theme.cardStroke)
                    .frame(width: 1, height: 16)
            }
        }
    }
}
