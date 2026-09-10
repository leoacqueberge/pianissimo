//
//  SettingsView.swift
//  Pianissimo
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage("showRhythmGrid") private var showRhythmGrid = false
    @AppStorage("showKeyNoteLabels") private var showKeyNoteLabels = false
    @AppStorage("midiInputEnabled") private var midiInputEnabled = true

    var body: some View {
        TabView {
            generalPane
                .tabItem { Label("General", systemImage: "gearshape") }
            playerPane
                .tabItem { Label("Player", systemImage: "pianokeys") }
        }
        .frame(width: 400, height: 260)
        .appAppearance()
    }

    private var generalPane: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Applies to the home window and the MIDI player.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var playerPane: some View {
        Form {
            Section {
                Toggle("Rhythm grid", isOn: $showRhythmGrid)
                Toggle("Note names on keys", isOn: $showKeyNoteLabels)
            } footer: {
                Text("The grid marks beats on the roll. Note names stay off unless you want them while learning.")
            }

            Section {
                Toggle("MIDI keyboard", isOn: $midiInputEnabled)
            } footer: {
                Text("Play along on a connected keyboard. Held keys light up in orange.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    SettingsView()
}
