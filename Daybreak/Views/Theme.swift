import AVFoundation
import SwiftUI

extension Color {
    static let dawn = Color(red: 1, green: 0.72, blue: 0.43)
    static let canvas = Color(red: 0.055, green: 0.064, blue: 0.08)
    static let surface = Color(red: 0.10, green: 0.115, blue: 0.135)
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(.caption2, design: .rounded, weight: .bold))
            .tracking(2).foregroundStyle(Color.dawn)
    }
}

struct SoundPicker: View {
    @Binding var sound: AlarmSound
    @State private var player: AVAudioPlayer?
    var body: some View {
        HStack {
            Picker("Sound", selection: $sound) {
                Section("Classic") { ForEach(AlarmSound.classics) { Text($0.title).tag($0) } }
                Section("Apple") { Text(AlarmSound.system.title).tag(AlarmSound.system) }
                Section("Daybreak") { ForEach(AlarmSound.originals) { Text($0.title).tag($0) } }
                Text(AlarmSound.random.title).tag(AlarmSound.random)
            }
            if sound.filename != nil {
                Button {
                    guard let name = sound.filename, let url = Bundle.main.url(forResource: name, withExtension: nil) else { return }
                    // The default ambient session is muted by the Silent switch; previews should be audible.
                    try? AVAudioSession.sharedInstance().setCategory(.playback)
                    try? AVAudioSession.sharedInstance().setActive(true)
                    player = try? AVAudioPlayer(contentsOf: url)
                    player?.play()
                } label: { Image(systemName: "play.circle.fill").font(.title3) }
                .buttonStyle(.borderless).accessibilityLabel("Preview \(sound.title)")
            }
        }
        .onChange(of: sound) { player?.stop() }
        .onDisappear { player?.stop() }
    }
}

struct AlarmTimeText: View {
    let date: Date
    var size: CGFloat = 48
    var body: some View {
        Text(date, format: .dateTime.hour().minute())
            .font(.system(size: size, weight: .light, design: .rounded))
            .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
    }
}
