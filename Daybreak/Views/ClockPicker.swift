import SwiftUI

struct ClockPicker: View {
    @Binding var date: Date
    @Binding var style: ClockStyle
    @State private var selectingMinutes = false
    private var hour: Int { Calendar.current.component(.hour, from: date) }
    private var minute: Int { Calendar.current.component(.minute, from: date) }

    var body: some View {
        VStack(spacing: 18) {
            Picker("Clock style", selection: $style) {
                ForEach(ClockStyle.allCases) { style in
                    Label(style.title, systemImage: style == .wheel ? "line.3.horizontal" : "clock").tag(style)
                }
            }.pickerStyle(.segmented).accessibilityIdentifier("clockStyle")
            if style == .wheel {
                DatePicker("Alarm time", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                    .accessibilityIdentifier("alarmTime")
            } else {
                HStack(spacing: 6) {
                    Button { selectingMinutes = false } label: {
                        Text(String(format: "%02d", hour % 12 == 0 ? 12 : hour % 12))
                            .foregroundStyle(selectingMinutes ? .secondary : Color.dawn)
                    }.accessibilityLabel("Select hour").accessibilityValue("\(hour)")
                        .accessibilityAdjustableAction { direction in
                            let step = direction == .increment ? 1 : -1
                            setTime(hour: (hour + step + 24) % 24, minute: minute)
                        }
                    Text(":").foregroundStyle(.secondary)
                    Button { selectingMinutes = true } label: {
                        Text(String(format: "%02d", minute)).foregroundStyle(selectingMinutes ? Color.dawn : .secondary)
                    }.accessibilityLabel("Select minute").accessibilityValue("\(minute)")
                        .accessibilityAdjustableAction { direction in adjustMinute(direction == .increment ? 1 : -1) }
                    Picker("Period", selection: Binding(get: { hour >= 12 }, set: { setTime(hour: hour % 12 + ($0 ? 12 : 0), minute: minute) })) {
                        Text("AM").tag(false)
                        Text("PM").tag(true)
                    }.pickerStyle(.segmented).frame(width: 110).padding(.leading, 14)
                }.font(.system(size: 36, weight: .light, design: .rounded)).monospacedDigit().buttonStyle(.plain)
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    let center = size / 2
                    let value = selectingMinutes ? Double(minute) / 60 : Double(hour % 12) / 12
                    ZStack {
                        Circle().fill(Color.canvas)
                        ForEach(0..<60) { tick in
                            Capsule().fill(.white.opacity(tick % 5 == 0 ? 0.25 : 0.08))
                                .frame(width: tick % 5 == 0 ? 2 : 1, height: tick % 5 == 0 ? 7 : 3)
                                .offset(y: -center + 9).rotationEffect(.degrees(Double(tick) * 6))
                        }
                        Capsule().fill(Color.dawn.opacity(0.7)).frame(width: 2, height: center - 38)
                            .offset(y: -(center - 38) / 2).rotationEffect(.degrees(value * 360))
                        Circle().fill(Color.dawn).frame(width: 8, height: 8)
                        ForEach(0..<12) { index in
                            let angle = Double(index) * .pi / 6
                            let selected = selectingMinutes ? minute / 5 == index : hour % 12 == index
                            Button {
                                if selectingMinutes { setTime(hour: hour, minute: index * 5) }
                                else { setTime(hour: index + (hour >= 12 ? 12 : 0), minute: minute); selectingMinutes = true }
                            } label: {
                                Text(selectingMinutes ? String(format: "%02d", index * 5) : "\(index == 0 ? 12 : index)")
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(selected ? Color.canvas : .white)
                                    .background(selected ? Color.dawn : .clear, in: Circle())
                            }.buttonStyle(.plain)
                                .position(x: center + sin(angle) * (center - 31), y: center - cos(angle) * (center - 31))
                        }
                    }.frame(width: size, height: size)
                    .gesture(DragGesture(minimumDistance: 5).onChanged { value in
                        let angle = atan2(value.location.x - center, center - value.location.y)
                        let fraction = (angle / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
                        if selectingMinutes {
                            setTime(hour: hour, minute: Int((fraction * 60).rounded()) % 60)
                        } else {
                            setTime(hour: Int((fraction * 12).rounded()) % 12 + (hour >= 12 ? 12 : 0), minute: minute)
                        }
                    }.onEnded { _ in selectingMinutes = true })
                    .frame(maxWidth: .infinity)
                }.frame(height: 250)
                HStack {
                    Text(selectingMinutes ? "Choose a minute" : "Choose an hour").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { adjustMinute(-1) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("One minute earlier")
                    Button { adjustMinute(1) } label: { Image(systemName: "plus.circle") }.accessibilityLabel("One minute later")
                }.buttonStyle(.borderless)
            }
        }.padding(.vertical, 6)
    }
    private func setTime(hour: Int, minute: Int) {
        date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }
    private func adjustMinute(_ amount: Int) {
        date = Calendar.current.date(byAdding: .minute, value: amount, to: date) ?? date
    }
}
