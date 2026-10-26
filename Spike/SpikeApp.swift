import AlarmKit
import SwiftUI

@main
struct DaybreakSpikeApp: App {
    @State private var model = SpikeModel()

    var body: some Scene {
        WindowGroup {
            SpikeView(model: model)
                .preferredColorScheme(.dark)
                .task { await model.observe() }
        }
    }
}

struct SpikeView: View {
    @Bindable var model: SpikeModel
    @Environment(\.scenePhase) private var scenePhase

    private let observations = ["On time + audible", "Late", "Silent / not heard", "Did not fire", "Cancelled by I'm up", "Stopped"]

    var body: some View {
        NavigationStack {
            List {
                Section("Setup") {
                    LabeledContent("Authorization", value: "\(model.authorization)")
                    Button("Request AlarmKit authorization") { Task { await model.requestAuthorization() } }
                    Stepper("First alarm in ~\(model.leadMinutes) min", value: $model.leadMinutes, in: 1...15)
                    Text(SpikeModel.deviceSummary).font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    ForEach(SpikeRun.allCases) { run in
                        Button(run.rawValue) { Task { await model.schedule(run) } }
                    }
                    if !model.status.isEmpty { Text(model.status).font(.footnote) }
                } header: { Text("Schedule a run") } footer: {
                    Text("Every alarm is alert-only (no widget extension) with an \"I'm up\" .custom secondary button. Lock the phone and leave it untouched for runs A/B.")
                }
                Section("AlarmKit reports \(model.alarms.count)") {
                    ForEach(model.alarms, id: \.id) { alarm in
                        LabeledContent(model.label(for: alarm.id), value: "\(alarm.state)")
                            .font(.footnote)
                    }
                    Button("Cancel all alarms", role: .destructive) { model.cancelAll() }
                }
                Section("Records — tap to note what happened") {
                    ForEach(model.records) { record in
                        Menu {
                            ForEach(observations, id: \.self) { o in Button(o) { model.setObservation(o, for: record) } }
                        } label: {
                            VStack(alignment: .leading) {
                                Text("\(record.runName) \(record.index)/\(record.total) · \(record.expected?.formatted(date: .omitted, time: .shortened) ?? "-")\(record.isTarget ? " · Target" : "")")
                                Text(record.observation ?? "not recorded").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Log") {
                    ShareLink("Export report", item: model.report)
                    Button("Clear records and log", role: .destructive) { model.clearHistory() }
                    Text(model.log).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                }
            }
            .navigationTitle("Daybreak M0")
            .refreshable { model.refreshLocal() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { SpikeStore.log("APP foreground"); model.refreshLocal() }
        }
    }
}
