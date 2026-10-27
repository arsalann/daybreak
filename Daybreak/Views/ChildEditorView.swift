import SwiftUI

struct ChildEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var child: ChildAlarm
    let group: AlarmGroup
    let onSave: (ChildAlarm) -> Void
    @State private var useClock = false
    @State private var clockStyle: ClockStyle = .wheel
    private var isBefore: Binding<Bool> {
        Binding(get: { child.offsetMinutes < 0 }, set: { child.offsetMinutes = abs(child.offsetMinutes) * ($0 ? -1 : 1) })
    }
    private var distance: Binding<Int> {
        Binding(get: { abs(child.offsetMinutes) }, set: { child.offsetMinutes = $0 * (child.offsetMinutes < 0 ? -1 : 1) })
    }
    private var clockTime: Binding<Date> {
        Binding(get: { group.clockDate(offset: child.offsetMinutes) }, set: { date in
            let cal = Calendar.current
            let total = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
            var offset = total - (group.hour * 60 + group.minute)
            if offset > 720 { offset -= 1440 }
            if offset < -720 { offset += 1440 }
            child.offsetMinutes = offset
        })
    }
    private var error: String? {
        if child.offsetMinutes == 0 { return "Choose a time different from the target." }
        if group.children.contains(where: { $0.id != child.id && $0.offsetMinutes == child.offsetMinutes }) { return "Another child already rings at this time." }
        return nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Eyebrow(text: "A step toward your target")
                        AlarmTimeText(date: group.clockDate(offset: child.offsetMinutes), size: 52)
                        Text(group.relativeLabel(child.offsetMinutes)).foregroundStyle(Color.dawn).font(.subheadline)
                    }.frame(maxWidth: .infinity).padding(.vertical, 18)
                }.listRowBackground(Color.clear)
                Section("Timing") {
                    Picker("Set time with", selection: $useClock) {
                        Text("Offset").tag(false)
                        Text("Clock").tag(true)
                    }.pickerStyle(.segmented)
                    if useClock {
                        ClockPicker(date: clockTime, style: $clockStyle)
                        Text("Uses the nearest time within 12 hours of the target.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Relative to target", selection: isBefore) {
                            Text("Before target").tag(true)
                            Text("After target").tag(false)
                        }.pickerStyle(.segmented)
                        Stepper("\(abs(child.offsetMinutes)) minutes", value: distance, in: 1...720)
                        HStack {
                            ForEach([5, 10, 15, 30, 60], id: \.self) { amount in
                                Button("\(amount)m") { distance.wrappedValue = amount }
                                    .frame(maxWidth: .infinity)
                            }
                        }.font(.caption).buttonStyle(.borderless)
                    }
                }
                Section("Personalize") {
                    TextField("Label (optional)", text: $child.label)
                    Toggle("Enabled", isOn: $child.isEnabled)
                    SoundPicker(sound: $child.sound)
                }
                if let error { Section { Text(error).font(.subheadline).foregroundStyle(Color.dawn) } }
            }
            .scrollContentBackground(.hidden).background(Color.canvas)
            .navigationTitle("Child alarm").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(child); dismiss() }.fontWeight(.semibold).disabled(error != nil)
                }
            }
        }.tint(.dawn)
    }
}
