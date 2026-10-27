import SwiftUI

struct AlarmEditorView: View {
    @Environment(AlarmModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var group: AlarmGroup
    let isNew: Bool
    @State private var childEditing: ChildAlarm?
    @State private var showReplace = false
    @State private var showDelete = false
    @State private var saveError: String?
    @AppStorage("gapWarning") private var gapWarning = 2

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Alarm type", selection: $group.kind) {
                        ForEach(AlarmKind.allCases) { kind in Text(kind.title).tag(kind) }
                    }.pickerStyle(.segmented)
                    ClockPicker(date: $group.timeDate, style: $group.clockStyle)
                } footer: {
                    Text(group.kind == .target ? "Your target is when you want to be up. Child alarms build a rhythm around it." : "A single alarm, right when you need it.")
                }
                Section("The essentials") {
                    TextField("Label", text: $group.label).accessibilityIdentifier("alarmLabel")
                    Toggle("Enabled", isOn: $group.isEnabled)
                    SoundPicker(sound: $group.sound)
                    if group.kind == .regular {
                        Toggle("Snooze", isOn: $group.snoozeEnabled)
                        if group.snoozeEnabled {
                            Picker("Snooze duration", selection: $group.snoozeMinutes) {
                                ForEach([1, 3, 5, 9, 10, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                            }
                        }
                    }
                }
                Section {
                    WeekdayPicker(days: $group.repeatDays)
                } header: { Text("Repeat · \(group.repeatDescription)") }
                  footer: { Text("No days selected means this alarm rings once. Days belong to the target, even when a child rings the night before.") }
                if group.kind == .target {
                    presetSection
                    childrenSection
                }
                previewSection
                if let issue = group.validationError {
                    Section { Label(issue, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Color.dawn) }
                }
                if let saveError {
                    Section { Text(saveError).font(.subheadline).foregroundStyle(Color.dawn) }
                }
                if !isNew {
                    Section {
                        Button("Delete alarm", role: .destructive) { showDelete = true }.frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Color.canvas)
            .tint(.dawn)
            .navigationTitle(isNew ? "New alarm" : "Edit alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isBusy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await model.save(group) { dismiss() }
                            else { saveError = model.errorMessage }
                        }
                    } label: {
                        if model.isBusy { ProgressView() } else { Text("Save").fontWeight(.semibold) }
                    }.disabled(model.isBusy || group.validationError != nil).accessibilityIdentifier("saveAlarm")
                }
            }
            .interactiveDismissDisabled(model.isBusy)
            .onChange(of: group.kind) { _, kind in
                if kind == .target, group.children.isEmpty, group.preset != .manual { group.applyPreset() }
            }
            .sheet(item: $childEditing) { child in
                ChildEditorView(child: child, group: group) { updated in
                    if let index = group.children.firstIndex(where: { $0.id == updated.id }) { group.children[index] = updated }
                    else { group.children.append(updated) }
                    group.preset = .manual
                }
            }
            .confirmationDialog("Replace child alarms with this preset?", isPresented: $showReplace, titleVisibility: .visible) {
                Button("Apply preset") { group.applyPreset() }
            } message: { Text("Children at matching offsets keep their settings. Other children will be replaced.") }
            .confirmationDialog("Delete this alarm and its children?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete alarm", role: .destructive) { Task { if await model.delete(group) { dismiss() } else { saveError = model.errorMessage } } }
            }
        }
    }

    private var presetSection: some View {
        Section {
            Picker("Sequence", selection: $group.preset) {
                ForEach(SequencePreset.allCases) { Text($0.title).tag($0) }
            }
            if [.fibonacci, .fiveMinutes, .tenMinutes].contains(group.preset) {
                Picker("Lead-in window", selection: $group.windowMinutes) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            }
            if group.preset == .fibonacci {
                DisclosureGroup("Fine-tune Fibonacci") {
                    Picker("Gap before target", selection: $group.firstGap) {
                        ForEach([1, 2, 3], id: \.self) { Text("\($0) min").tag($0) }
                    }
                }
            }
            if group.preset == .interval {
                Stepper("\(group.intervalCount) children per side", value: $group.intervalCount, in: 1...19)
                Stepper("Every \(group.intervalMinutes) minutes", value: $group.intervalMinutes, in: 1...120)
                Picker("Direction", selection: $group.direction) {
                    ForEach(IntervalDirection.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
            if group.preset != .manual {
                Button {
                    if group.children.isEmpty { group.applyPreset() } else { showReplace = true }
                } label: { Label("Apply preset", systemImage: "wand.and.stars") }
            }
        } header: { Text("Build your sequence") }
          footer: {
              Text(group.preset == .manual ? "Add your own children below, at any time before or after your target." : "The lead-in window sets how far before your target the sequence begins. Apply a preset, then customize each child below.")
          }
    }

    private var childrenSection: some View {
        Section {
            ForEach(group.children.sorted { $0.offsetMinutes < $1.offsetMinutes }) { child in
                HStack {
                    Button { childEditing = child } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Color.dawn)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.clockDate(offset: child.offsetMinutes), format: .dateTime.hour().minute())
                                    .font(.system(.title3, design: .rounded)).monospacedDigit()
                                Text(child.label.isEmpty ? group.relativeLabel(child.offsetMinutes) : "\(child.label) · \(group.relativeLabel(child.offsetMinutes))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).opacity(child.isEnabled ? 1 : 0.45)
                    Toggle("Enable child at \(group.relativeLabel(child.offsetMinutes))", isOn: Binding(
                        get: { child.isEnabled },
                        set: { value in
                            if let i = group.children.firstIndex(where: { $0.id == child.id }) { group.children[i].isEnabled = value }
                        })).labelsHidden()
                }.padding(.vertical, 4)
                .swipeActions { Button("Delete", role: .destructive) {
                    group.children.removeAll { $0.id == child.id }
                    group.preset = .manual
                } }
            }
            HStack {
                Image(systemName: "sun.max.fill").foregroundStyle(Color.dawn)
                Text(group.timeDate, format: .dateTime.hour().minute()).font(.system(.title3, design: .rounded, weight: .semibold))
                Spacer()
                Text("TARGET").font(.caption2.bold()).tracking(1.5).foregroundStyle(Color.dawn)
            }.padding(.vertical, 8)
            Button {
                let used = Set(group.children.map(\.offsetMinutes))
                let offset = (1...720).map { -$0 }.first { !used.contains($0) } ?? -1
                childEditing = ChildAlarm(offsetMinutes: offset, sound: group.sound)
            } label: { Label("Add child alarm", systemImage: "plus") }
                .disabled(group.children.count >= 19)
        } header: { Text("Child alarms · \(group.children.count)") }
          footer: { Text("Tap a child to change its time, label, or sound. Swipe to remove. When ringing, “I'm up” ends the rest of that occurrence; Stop silences just one.") }
    }

    private var previewSection: some View {
        Section("Your next wake-up") {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let now = timeline.date
                let preview = previewGroup(now: now)
                if let next = preview.nextFire(now: now) {
                    Label("First ring in \(CountdownFormatter.string(from: now, to: next))", systemImage: "bell")
                        .foregroundStyle(Color.dawn).font(.subheadline)
                } else { Text(group.isEnabled ? "This occurrence has finished. Enable it again to schedule a new one." : "This alarm is turned off.").foregroundStyle(.secondary) }
                if preview.repeatDays.isEmpty {
                    let skipped = ScheduleMapper.oneOffDates(target: preview.resolvedTarget(now: now, calendar: .current), offsets: preview.offsets, now: now, calendar: .current).skippedPast
                    if skipped > 0 { Text("\(skipped) earlier alarms have passed and will be skipped.").font(.caption).foregroundStyle(.secondary) }
                }
                if group.kind == .target {
                    ForEach(AlarmPlanner.desired(for: preview, now: now, calendar: .current).sorted { ($0.nextFire(after: now, calendar: .current) ?? .distantFuture) < ($1.nextFire(after: now, calendar: .current) ?? .distantFuture) }) { plan in
                        if let date = plan.nextFire(after: now, calendar: .current) {
                            HStack {
                                Text(date, format: .dateTime.weekday(.abbreviated).hour().minute()).monospacedDigit()
                                Spacer()
                                Text(plan.offset == 0 ? "Target" : "in \(CountdownFormatter.string(from: now, to: date))")
                                    .foregroundStyle(plan.offset == 0 ? Color.dawn : .secondary)
                            }.font(.caption).padding(.vertical, 2)
                        }
                    }
                }
            }
            if SequenceValidator.issues(for: group.offsets, gapWarningThreshold: gapWarning).contains(where: { !$0.blocksSaving }) {
                Label("Gaps under \(gapWarning) minutes may be quiet if you sleep through an earlier alarm.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Color.dawn)
            }
        }
    }
    private func previewGroup(now: Date) -> AlarmGroup {
        var preview = group
        let existing = model.groups.first { $0.id == group.id }
        if isNew || existing?.hour != group.hour || existing?.minute != group.minute || existing?.isEnabled == false || existing?.repeatDays != group.repeatDays {
            preview.oneOffTarget = ScheduleMapper.resolveOneOffTarget(hour: group.hour, minute: group.minute, now: now, calendar: .current)
            preview.suppressedTarget = nil
        }
        return preview
    }
}

struct WeekdayPicker: View {
    @Binding var days: Set<Int>
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                    Button {
                        if days.contains(day) { days.remove(day) } else { days.insert(day) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(minHeight: 44)
                            .background(days.contains(day) ? Color.dawn : Color.surface, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(days.contains(day) ? Color.canvas : .secondary)
                    }.buttonStyle(.plain)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        .accessibilityAddTraits(days.contains(day) ? .isSelected : [])
                }
            }
            HStack(spacing: 18) {
                Button("Weekdays") { days = Set(2...6) }
                Button("Every day") { days = Set(1...7) }
                Button("Once") { days = [] }
            }.font(.caption).buttonStyle(.borderless)
        }.padding(.vertical, 6)
    }
}
