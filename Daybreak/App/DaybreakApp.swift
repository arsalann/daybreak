import SwiftUI

@main
struct DaybreakApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
                .preferredColorScheme(.dark)
        }
    }
}

/// M1 placeholder. The real list/editor UI is M3, gated on the M0 device spike.
struct PlaceholderView: View {
    private let preview = SequenceGenerator.offsets(for: .fibonacci(windowMinutes: 60, firstGap: 2))

    var body: some View {
        NavigationStack {
            List {
                Section("Default Fibonacci preview (09:00 target)") {
                    ForEach(ScheduleMapper.wallClockAlarms(targetHour: 9, targetMinute: 0, offsets: preview, repeatDays: []), id: \.offsetMinutes) { alarm in
                        HStack {
                            Text(String(format: "%02d:%02d", alarm.hour, alarm.minute))
                                .font(alarm.offsetMinutes == 0 ? .headline : .body)
                                .monospacedDigit()
                            Spacer()
                            if alarm.offsetMinutes == 0 { Text("Target").foregroundStyle(.tint) }
                        }
                    }
                }
                Section {
                    Text("Daybreak is in its device feasibility stage. Alarm scheduling is not built yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Daybreak")
        }
    }
}
