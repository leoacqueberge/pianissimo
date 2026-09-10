//
//  HomeComponents.swift
//  Pianissimo
//

import SwiftUI

// MARK: - Mode cards

struct ModeCardPicker: View {
    @Binding var selection: AppMode
    var disabled: Bool
    var onOpenPlayer: () -> Void

    @Environment(\.homeTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start from")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.text)

            VStack(spacing: 8) {
                ForEach(AppMode.allCases) { mode in
                    ModeCard(
                        mode: mode,
                        isSelected: mode != .playerOnly && selection == mode,
                        disabled: disabled
                    ) {
                        if mode == .playerOnly {
                            onOpenPlayer()
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selection = mode
                            }
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

    @Environment(\.homeTheme) private var theme

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

                if mode == .playerOnly {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.subtleText)
                } else if isSelected {
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

    @Environment(\.homeTheme) private var theme

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

                Text("Click to change file")
                    .font(.caption2)
                    .foregroundStyle(theme.subtleText)
            } else {
                Text("Drop your song here")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.text)
                Text("mp3 · wav · m4a · webm · mp4")
                    .font(.caption)
                    .foregroundStyle(theme.subtleText)
                Text("or drop a .mid to open the player")
                    .font(.caption2)
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

    @Environment(\.homeTheme) private var theme

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

    @Environment(\.homeTheme) private var theme

    private var segmentLength: Double { max(0, end - start) }
    private var isSegmentValid: Bool { segmentLength >= SegmentLimits.minDuration }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Process portion only", isOn: $useSegment)
                .font(.subheadline)
                .toggleStyle(.switch)
                .tint(theme.accent)

            if useSegment {
                HStack(spacing: 8) {
                    segmentPreset("First min") {
                        start = 0
                        end = min(60, duration)
                    }
                    if duration > 120 {
                        segmentPreset("Middle") {
                            let len = min(60, duration / 3)
                            start = max(0, (duration - len) / 2)
                            end = min(duration, start + len)
                        }
                    }
                    segmentPreset("Full track") {
                        start = 0
                        end = duration
                    }
                }

                WaveformRangeControl(
                    duration: duration,
                    start: $start,
                    end: $end,
                    samples: waveform
                )
                .frame(height: 64)

                HStack(spacing: 12) {
                    SegmentTimeField(label: "Start", value: $start, maxValue: end - SegmentLimits.minDuration)
                    SegmentTimeField(label: "End", value: $end, minValue: start + SegmentLimits.minDuration, maxValue: duration)
                }

                HStack {
                    Text("\(PianissimoFormatters.formatTime(segmentLength)) selected")
                    Spacer()
                    Text("of \(PianissimoFormatters.formatTime(duration))")
                }
                .font(theme.mono)
                .foregroundStyle(theme.subtleText)

                if !isSegmentValid {
                    Label("Select at least \(Int(SegmentLimits.minDuration)) seconds", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
        .onChange(of: start) { _, _ in normalizeSegment() }
        .onChange(of: end) { _, _ in normalizeSegment() }
    }

    private func segmentPreset(_ title: String, apply: @escaping () -> Void) -> some View {
        Button(title) { apply() }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(theme.accent)
    }

    private func normalizeSegment() {
        let minLen = SegmentLimits.minDuration
        start = min(max(0, start), max(0, duration - minLen))
        end = min(max(start + minLen, end), duration)
    }
}

private struct SegmentTimeField: View {
    let label: String
    @Binding var value: Double
    var minValue: Double = 0
    var maxValue: Double = .infinity

    @Environment(\.homeTheme) private var theme
    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.subtleText)
            TextField("0:00", text: $text)
                .font(theme.mono)
                .foregroundStyle(theme.text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { text = PianissimoFormatters.formatTime(value) }
                .onChange(of: value) { _, newValue in
                    if !isFocused { text = PianissimoFormatters.formatTime(newValue) }
                }
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func commit() {
        if let seconds = parseTime(text) {
            value = min(max(minValue, seconds), maxValue)
        }
        text = PianissimoFormatters.formatTime(value)
    }

    private func parseTime(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":")
        if parts.count == 2,
           let m = Int(parts[0]), let s = Int(parts[1]), s >= 0, s < 60 {
            return Double(m * 60 + s)
        }
        if parts.count == 1, let s = Double(trimmed) { return s }
        return nil
    }
}

struct WaveformRangeControl: View {
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    let samples: [Float]

    @Environment(\.homeTheme) private var theme

    @State private var dragKind: DragKind?
    @State private var dragOriginStart: Double = 0
    @State private var dragOriginEnd: Double = 0

    private enum DragKind { case start, end, region }

    private let handleHitWidth: CGFloat = 18
    private let minDuration = SegmentLimits.minDuration

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.accent.opacity(theme.isDark ? 0.12 : 0.08))

                WaveformBars(samples: samples, color: theme.accent.opacity(0.35))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)

                if duration > 0 {
                    let x0 = xForTime(start, width: width)
                    let x1 = xForTime(end, width: width)
                    let selectionWidth = max(0, x1 - x0)

                    // Dimmed outside regions
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.black.opacity(theme.isDark ? 0.45 : 0.25))
                            .frame(width: x0)
                        Spacer(minLength: 0)
                        Rectangle().fill(Color.black.opacity(theme.isDark ? 0.45 : 0.25))
                            .frame(width: max(0, width - x1))
                    }
                    .allowsHitTesting(false)

                    // Selected region (draggable)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(theme.accent, lineWidth: 2)
                        .background(theme.accent.opacity(0.12))
                        .frame(width: selectionWidth, height: height - 4)
                        .offset(x: x0, y: 2)
                        .gesture(regionDrag(width: width))

                    // Start handle
                    handleKnob
                        .offset(x: x0 - handleHitWidth / 2, y: 0)
                        .gesture(handleDrag(.start, width: width))

                    // End handle
                    handleKnob
                        .offset(x: x1 - handleHitWidth / 2, y: 0)
                        .gesture(handleDrag(.end, width: width))
                }
            }
        }
    }

    private func xForTime(_ time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func timeForX(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, duration > 0 else { return 0 }
        return min(max(0, Double(x / width) * duration), duration)
    }

    private var handleKnob: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(theme.accent)
            .frame(width: 4, height: 48)
            .shadow(color: theme.accent.opacity(0.4), radius: 2, y: 1)
            .frame(width: handleHitWidth, height: 64)
            .contentShape(Rectangle())
    }

    private func timeDelta(_ translation: CGFloat, width: CGFloat) -> Double {
        guard width > 0, duration > 0 else { return 0 }
        return Double(translation / width) * duration
    }

    private func handleDrag(_ kind: DragKind, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragKind == nil {
                    dragKind = kind
                    dragOriginStart = start
                    dragOriginEnd = end
                }
                let delta = timeDelta(value.translation.width, width: width)
                switch kind {
                case .start:
                    start = min(max(0, dragOriginStart + delta), end - minDuration)
                case .end:
                    end = max(min(duration, dragOriginEnd + delta), start + minDuration)
                case .region:
                    break
                }
            }
            .onEnded { _ in dragKind = nil }
    }

    private func regionDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragKind == nil {
                    dragKind = .region
                    dragOriginStart = start
                    dragOriginEnd = end
                }
                let delta = timeDelta(value.translation.width, width: width)
                let length = dragOriginEnd - dragOriginStart
                var newStart = dragOriginStart + delta
                var newEnd = dragOriginEnd + delta
                if newStart < 0 {
                    newStart = 0
                    newEnd = length
                }
                if newEnd > duration {
                    newEnd = duration
                    newStart = duration - length
                }
                start = newStart
                end = newEnd
            }
            .onEnded { _ in dragKind = nil }
    }
}

struct WaveformBars: View {
    let samples: [Float]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 1) {
                ForEach(samples.indices, id: \.self) { i in
                    let amp = CGFloat(samples[i])
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(
                            width: max(1, geo.size.width / CGFloat(max(samples.count, 1)) - 1),
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
    var failedAt: ProcessingPhase = .preparing
    let currentMessage: String

    @Environment(\.homeTheme) private var theme

    private var steps: [String] { mode.pipelineLabels }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Progress")
                    .font(.headline)
                    .foregroundStyle(theme.text)
                Text(mode.title)
                    .font(.caption)
                    .foregroundStyle(theme.subtleText)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, label in
                    PipelineStepRow(
                        label: label,
                        state: stepState(for: index),
                        isLast: index == steps.count - 1,
                        detail: index == activeStepIndex ? currentMessage : nil
                    )
                }
            }
        }
    }

    private var activeStepIndex: Int {
        switch phase {
        case .idle: return 0
        case .done: return steps.count
        case .failed: return mode.stepIndex(for: failedAt)
        default: return mode.stepIndex(for: phase)
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

}

enum PipelineStepState {
    case pending, active, completed, failed
}

struct PipelineStepRow: View {
    let label: String
    let state: PipelineStepState
    let isLast: Bool
    let detail: String?

    @Environment(\.homeTheme) private var theme

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
                if let detail, state == .active || state == .failed {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(state == .failed ? Color.red : theme.accent)
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

// MARK: - Privacy chip

struct PrivacyChip: View {
    @Environment(\.homeTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.caption)
            Text("Processed locally on your Mac")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(theme.subtleText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(theme.cardFill)
        )
        .overlay(
            Capsule()
                .strokeBorder(theme.cardStroke, lineWidth: 1)
        )
        .help("All your data is processed locally. No data is collected. AI models run entirely on your machine.")
    }
}

// MARK: - Logs overlay

struct LogsOverlay: View {
    @Binding var text: String
    @Binding var isPresented: Bool

    @Environment(\.homeTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Console", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.subtleText)
                Spacer()
                Button("Clear") { text = "" }
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
                    Text(text.isEmpty ? "Waiting for a task…\n" : text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.text)
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
