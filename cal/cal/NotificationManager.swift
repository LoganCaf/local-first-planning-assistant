import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }
    }

    func scheduleRoutineReminders(routines: [RoutineItem]) {
        requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        let identifiers = routines.flatMap { routine in
            routine.weekdays.map { "\(routine.id.uuidString)-\($0)" }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        routines
            .filter { $0.isEnabled }
            .forEach { routine in
                guard let hour = routine.startTime.hour, let minute = routine.startTime.minute else { return }
                // Repeat on selected weekdays; if empty, treat as every day
                let days = routine.weekdays.isEmpty ? Set(1...7) : routine.weekdays
                let targetWeekdays = Array(days)
                for weekday in targetWeekdays {
                    var comps = DateComponents()
                    comps.weekday = weekday
                    comps.hour = hour
                    comps.minute = minute
                    comps.second = 0
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

                    let content = UNMutableNotificationContent()
                    content.title = "Routine starting"
                    content.body = "\"\(routine.title)\" starts now."
                    content.sound = .default

                    let identifier = "\(routine.id.uuidString)-\(weekday)"
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    center.add(request, withCompletionHandler: nil)
                }
            }
    }

    func scheduleTaskReminders(tasks: [TaskItem], leadMinutes: Int) {
        requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        let identifiers = tasks.map { $0.id.uuidString }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let leadSeconds = max(0, leadMinutes) * 60
        let now = Date()
        let leadDescription = Self.leadDescription(leadMinutes: leadMinutes)

        tasks
            .filter { $0.hasDeadline && !$0.isCompleted }
            .forEach { task in
                let triggerDate = task.dueDate.addingTimeInterval(TimeInterval(-leadSeconds))
                guard triggerDate > now else { return }

                var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
                comps.second = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

                let content = UNMutableNotificationContent()
                content.title = "Task reminder"
                content.body = "\"\(task.title)\" is due in \(leadDescription)."
                content.sound = .default

                let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
                center.add(request, withCompletionHandler: nil)
            }
    }

    func scheduleAssignmentReminders(assignments: [SchoolAssignment], leadMinutes: Int) {
        requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        let identifiers = assignments.map { $0.id }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let leadSeconds = max(0, leadMinutes) * 60
        let now = Date()
        let leadDescription = Self.leadDescription(leadMinutes: leadMinutes)

        assignments
            .filter { !$0.isCompleted }
            .forEach { assignment in
                let fireDate = assignment.displayEndDate(using: Calendar.current) ?? assignment.dueDate
                let triggerDate = fireDate.addingTimeInterval(TimeInterval(-leadSeconds))
                guard triggerDate > now else { return }

                var comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
                comps.second = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

                let content = UNMutableNotificationContent()
                content.title = "Assignment reminder"
                content.body = "\"\(assignment.title)\" is due in \(leadDescription)."
                content.sound = .default

                let request = UNNotificationRequest(identifier: assignment.id, content: content, trigger: trigger)
                center.add(request, withCompletionHandler: nil)
            }
    }

    private static func leadDescription(leadMinutes: Int) -> String {
        if leadMinutes >= 60 && leadMinutes % 60 == 0 {
            let hours = leadMinutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "\(leadMinutes) minutes"
    }
}
