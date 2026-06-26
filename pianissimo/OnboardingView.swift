//
//  OnboardingView.swift
//  Pianissimo
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let theme = HomeTheme.shared

    private let pages: [(icon: String, title: String, body: String)] = [
        (
            "pianokeys",
            "From audio to piano",
            "Pianissimo isolates the piano in your songs, transcribes them to MIDI, and helps you learn — entirely on your Mac."
        ),
        (
            "waveform.path",
            "Three modes",
            "Full pipeline, transcription only, or MIDI player: pick what you need before you start."
        ),
        (
            "lock.shield",
            "100% local",
            "Your files never leave your machine. AI models run locally with no data collection."
        )
    ]

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: pages[page].icon)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(theme.accent)
                    .symbolEffect(.pulse, options: .repeating, value: page)

                VStack(spacing: 10) {
                    Text(pages[page].title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(pages[page].body)
                        .font(.body)
                        .foregroundStyle(theme.subtleText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? theme.accent : theme.cardStroke)
                            .frame(width: i == page ? 20 : 8, height: 8)
                    }
                }

                Spacer()

                HStack {
                    if page > 0 {
                        Button("Back") { page -= 1 }
                            .buttonStyle(.borderless)
                    }
                    Spacer()
                    Button(page == pages.count - 1 ? "Get started" : "Next") {
                        if page == pages.count - 1 {
                            isPresented = false
                        } else {
                            page += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .padding(32)
        }
        .frame(width: 480, height: 420)
    }
}
