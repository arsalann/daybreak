import BackgroundTasks
import SwiftUI

@main
struct DaybreakApp: App {
    @State private var model = AlarmModel.shared
    var body: some Scene {
        WindowGroup {
            AlarmListView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(.dawn)
        }
        .backgroundTask(.appRefresh(AlarmModel.backgroundID)) {
            await AlarmModel.shared.refresh()
            await AlarmModel.requestBackgroundRefresh()
        }
    }
}
