import AlarmKit
import SwiftUI

struct AlarmListView: View {
    @Environment(AlarmModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: AlarmGroup?
    @State private var showingSettings = false
    @State private var deleting: AlarmGroup?
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingWelcome = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                alarmList(now: timeline.date)
            }
            .background(Color.canvas)
            .navigationTitle("Daybreak")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = AlarmGroup() } label: { Image(systemName: "plus").fontWeight(.semibold) }
                        .accessibilityLabel("Add alarm").accessibilityIdentifier("addAlarm")
                        .disabled(model.storageFailed)
                }
            }
            .sheet(item: $editing) { group in AlarmEditorView(group: group, isNew: !model.groups.contains { $0.id == group.id }) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingWelcome) {
                WelcomeView {
                    hasSeenWelcome = true
                    showingWelcome = false
                }
            }
            .confirmationDialog("Delete \(deleting?.displayName ?? "alarm")?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete alarm", role: .destructive) {
                    if let group = deleting { Task { _ = await model.delete(group) } }
                    deleting = nil
                }
            }
            .task {
                showingWelcome = !hasSeenWelcome
                await model.refresh()
                await model.observe()
            }
            .task {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    if scenePhase == .active { await model.refresh() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
        }
    }

    private func alarmList(now: Date) -> some View {
        let ordered = model.groups.sorted {
            let a = $0.nextFire(now: now), b = $1.nextFire(now: now)
            if a == b { return $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }
            return (a ?? .distantFuture) < (b ?? .distantFuture)
        }
        return List {
            Section {
                NextAlarmHero(groups: model.groups, snoozes: model.document.snoozes, now: now, authorized: model.authorization == .authorized && model.errorMessage == nil)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 16, trailing: 0))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if model.authorization != .authorized {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Allow alarms to ring", systemImage: "bell.badge")
                            .font(.headline)
                        Text("Daybreak needs alarm access to ring on your Lock Screen, even in Silent mode or Focus.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if model.authorization == .denied {
                            Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                        } else {
                            Button("Enable alarms") { Task { await model.authorize() } }
                        }
                    }.padding(.vertical, 6)
                }.listRowBackground(Color.surface)
            }
            if let error = model.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Needs attention", systemImage: "exclamationmark.triangle").foregroundStyle(Color.dawn)
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                        if !model.storageFailed {
                            Button("Retry") { Task { await model.refresh() } }.disabled(model.isBusy)
                        }
                    }.padding(.vertical, 5)
                }.listRowBackground(Color.surface)
            }
            Section {
                if ordered.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: "alarm").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Color.dawn)
                        Text("A better start to your day").font(.title3.weight(.medium))
                        Text("One alarm, or a gentle sequence leading\nup to the moment you want to wake.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Create your first alarm") { editing = AlarmGroup() }
                            .buttonStyle(.borderedProminent).tint(.dawn).foregroundStyle(Color.canvas)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 32)
                    .listRowBackground(Color.surface)
                } else {
                    ForEach(ordered) { group in
                        AlarmRow(group: group, now: now, showCountdown: model.authorization == .authorized && model.errorMessage == nil,
                            edit: { editing = group }, toggle: { Task { await model.toggle(group) } })
                            .disabled(model.isBusy)
                            .listRowBackground(Color.surface)
                            .listRowSeparatorTint(.white.opacity(0.07))
                            .swipeActions {
                                Button("Delete", role: .destructive) { deleting = group }
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = group }
                                Button("Duplicate", systemImage: "plus.square.on.square") {
                                    var copy = group
                                    copy.id = UUID()
                                    copy.children = copy.children.map { var child = $0; child.id = UUID(); return child }
                                    copy.oneOffTarget = nil
                                    copy.suppressedTarget = nil
                                    copy.label = group.displayName + " copy"
                                    editing = copy
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = group }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Your alarms").font(.caption.weight(.semibold)).tracking(1)
                    Spacer()
                    Text("\(model.groups.count)").monospacedDigit()
                }.padding(.bottom, 5)
            } footer: {
                if !ordered.isEmpty {
                    Text("A little rhythm. A brighter morning.")
                        .frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(16)
    }
}

private struct AlarmRow: View {
    let group: AlarmGroup
    let now: Date
    let showCountdown: Bool
    let edit: () -> Void
    let toggle: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: group.kind == .target ? "sun.horizon" : "alarm")
                        Text(group.kind == .target ? "TARGET · \(group.activeChildren.count) CHILDREN" : "REGULAR ALARM")
                            .tracking(1.2)
                    }.font(.system(size: 10, weight: .bold)).foregroundStyle(group.kind == .target ? Color.dawn : .secondary)
                    AlarmTimeText(date: group.timeDate)
                        .foregroundStyle(group.isEnabled ? .white : .gray)
                    Text(group.displayName + " · " + group.repeatDescription)
                        .font(.subheadline).foregroundStyle(.secondary)
                    if group.kind == .target, !group.activeChildren.isEmpty {
                        Text(group.activeChildren.sorted { $0.offsetMinutes < $1.offsetMinutes }.prefix(4)
                            .map { group.clockDate(offset: $0.offsetMinutes).formatted(date: .omitted, time: .shortened) }
                            .joined(separator: " · ") + (group.activeChildren.count > 4 ? " · …" : ""))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if showCountdown, let next = group.nextFire(now: now) {
                        Text((group.suppressedTarget != nil ? "Done for today · next in " : "Rings in ") + CountdownFormatter.string(from: now, to: next))
                            .font(.caption).foregroundStyle(Color.dawn)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Edit \(group.displayName), \(group.timeDate.formatted(date: .omitted, time: .shortened))")
            Toggle("Enable \(group.displayName)", isOn: Binding(get: { group.isEnabled }, set: { _ in toggle() }))
                .labelsHidden().tint(.dawn)
        }.padding(.vertical, 12)
    }
}

private struct NextAlarmHero: View {
    let groups: [AlarmGroup]
    let snoozes: [PlannedAlarm]
    let now: Date
    let authorized: Bool
    var next: (String, Date)? {
        guard authorized else { return nil }
        let ordinary = groups.compactMap { group in group.nextFire(now: now).map { (group.displayName, $0) } }
        let snoozed = snoozes.compactMap { alarm in alarm.nextFire(after: now, calendar: .current).map { (alarm.title + " · Snoozed", $0) } }
        return (ordinary + snoozed).min { $0.1 < $1.1 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Eyebrow(text: "The next day starts here")
                Spacer()
                Image(systemName: "sun.horizon.fill").font(.title2).foregroundStyle(Color.dawn)
            }
            if let (name, date) = next {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next alarm in").font(.subheadline).foregroundStyle(.secondary)
                    if date.timeIntervalSince(now) < 3600 {
                        Text(timerInterval: now...date, countsDown: true)
                            .font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                    } else {
                        Text(CountdownFormatter.string(from: now, to: date))
                            .font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                    }
                }
                Text("\(date.formatted(date: .omitted, time: .shortened)) · \(name)")
                    .font(.subheadline).foregroundStyle(Color.dawn)
            } else {
                Text("Rest easy.")
                    .font(.system(size: 42, weight: .light, design: .rounded))
                Text(authorized ? "No upcoming alarms. Make room for a fresh start." : "Your morning, at your own pace.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(
                LinearGradient(colors: [Color(red: 0.23, green: 0.18, blue: 0.15), .surface], startPoint: .topTrailing, endPoint: .bottomLeading))
        }
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.dawn.opacity(0.16)))
    }
}
