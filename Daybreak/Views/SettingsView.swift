import AlarmKit
import SwiftUI

struct SettingsView: View {
    @Environment(AlarmModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gapWarning") private var gapWarning = 2
    var body: some View {
        NavigationStack {
            Form {
                Section("Alarms") {
                    LabeledContent("Alarm access", value: model.authorization == .authorized ? "Allowed" : "Not allowed")
                    Link("Open system settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    Stepper("Warn below \(gapWarning) min gaps", value: $gapWarning, in: 1...10)
                    NavigationLink("Activity log") { ActivityLogView() }
                }
                Section("How it works") {
                    Text("Regular alarms ring once, or on your selected weekdays. Snooze adds another ring after your chosen delay.")
                    Text("Target alarms bring child alarms together around one wake-up time. Stop silences only the ringing alarm. “I'm up” ends the remaining alarms in that occurrence.")
                    Text("After “I'm up” on a repeating target, reopen Daybreak within a week to ensure every repeat day is restored. Background refresh also attempts this automatically.")
                        .foregroundStyle(.secondary)
                }.font(.subheadline)
                Section("Made for quieter mornings") {
                    LabeledContent("Daybreak", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("No accounts. No ads. No tracking. Your alarms stay on your device.")
                    NavigationLink("Privacy") {
                        ScrollView {
                            Text("Daybreak stores alarm times, labels, repeat days, and preferences locally on this device. It requests alarm permission only to schedule the alarms you create. Daybreak does not collect personal information, use analytics, or send your alarm data to a server. Deleting an alarm removes its saved configuration and cancels its scheduled alerts.")
                                .padding(24)
                        }.navigationTitle("Privacy")
                    }
                    Link("Source code on GitHub", destination: URL(string: "https://github.com/arsalann/daybreak")!)
                    NavigationLink("Open-source license") {
                        ScrollView { Text(licenseText).font(.footnote).padding(24) }.navigationTitle("MIT License")
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Color.canvas)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "MIT License" }
        return text
    }
}

struct WelcomeView: View {
    @Environment(AlarmModel.self) private var model
    let done: () -> Void
    @State private var requesting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 64, weight: .ultraLight)).foregroundStyle(Color.dawn).padding(.top, 30)
                Eyebrow(text: "Welcome to Daybreak")
                Text("Mornings,\nat your pace.")
                    .font(.system(size: 44, weight: .light, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Text("A simple alarm. Or a thoughtful sequence.\nSet your target and ease into the day.")
                    .font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 22) {
                    feature("clock", "Make time yours", "Regular alarms and target sequences, together.")
                    feature("waveform.path", "Find your rhythm", "Fibonacci, fixed intervals, or your own times.")
                    feature("bell.badge", "Ready when you are", "Alarm access lets Daybreak ring through Silent mode and Focus.")
                }.padding(.vertical, 10)
                Button {
                    requesting = true
                    Task { await model.authorize(); requesting = false; done() }
                } label: {
                    HStack { Spacer(); if requesting { ProgressView() } else { Text("Enable alarms").fontWeight(.semibold) }; Spacer() }.padding(.vertical, 10)
                }.buttonStyle(.borderedProminent).tint(.dawn).foregroundStyle(Color.canvas).disabled(requesting)
                Button("Explore first") { done() }.frame(maxWidth: .infinity).font(.subheadline).disabled(requesting)
                Text("Private by design. Everything stays on this device.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(28)
        }.background(Color.canvas).interactiveDismissDisabled()
    }
    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.dawn).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Shows what Daybreak scheduled, cancelled and saw ringing. Useful when an alarm rings unexpectedly.
struct ActivityLogView: View {
    @State private var text = AlarmLog.read()
    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No activity yet." : text)
                .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
        .defaultScrollAnchor(.bottom)
        .background(Color.canvas)
        .navigationTitle("Activity log").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: text.isEmpty ? "No activity yet." : text, subject: Text("Daybreak activity log"))
                    Button("Clear log", role: .destructive) { AlarmLog.clear(); text = "" }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Log options")
            }
        }
    }
}
