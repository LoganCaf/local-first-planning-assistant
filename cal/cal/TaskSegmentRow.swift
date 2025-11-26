import SwiftUI

struct TaskSegmentRow: View {
    let segment: TaskSegment
    var parentTitle: String?
    let onToggleCompletion: () -> Void
    let onStart: () -> Void
    let onPause: () -> Void
    let onFinish: () -> Void
    let onEdit: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var showFinishConfirmation = false

    private var isLate: Bool {
        segment.hasDeadline && !segment.isCompleted && segment.dueDate < Date()
    }

    private var hasTrackingStarted: Bool {
        segment.actualStartTime != nil
    }

    private var hasTrackingCompleted: Bool {
        segment.actualEndTime != nil
    }

    private var isTimerRunning: Bool {
        segment.activeTimerStart != nil
    }

    private var elapsedSeconds: TimeInterval? {
        if let active = segment.activeTimerStart {
            let accumulated = segment.actualDurationSeconds ?? 0
            return max(0, accumulated + Date().timeIntervalSince(active))
        }
        if let stored = segment.actualDurationSeconds {
            return max(0, stored)
        }
        if let start = segment.actualStartTime {
            let end = segment.actualEndTime ?? Date()
            return max(0, end.timeIntervalSince(start))
        }
        return nil
    }

    private var stopwatchText: String? {
        guard let seconds = elapsedSeconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggleCompletion) {
                    Image(systemName: segment.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(segment.isCompleted ? Color.green : Color.secondary)
                        .accessibilityLabel(segment.isCompleted ? "Mark segment incomplete" : "Mark segment complete")
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(segment.title)
                        .font(.headline)
                        .strikethrough(segment.isCompleted, color: .primary)
                        .opacity(segment.isCompleted ? 0.6 : 1)

                    if let parentTitle, !parentTitle.isEmpty {
                        Text("From: \(parentTitle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Label("Due: \(formattedDateTime(segment.dueDate))", systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(isLate ? Color.red : .secondary)

                    Label("Priority: \(segment.priority.displayName)", systemImage: segment.priority.systemImageName)
                        .font(.caption)
                        .foregroundStyle(segment.priority.tintColor)

                    if let start = segment.startDate {
                        Label("Start: \(formattedDateTime(start))", systemImage: "play.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let duration = segment.estimatedDurationMinutes, duration > 0 {
                        Label("Duration: \(durationLabel(for: duration))", systemImage: "hourglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isLate {
                        Text("Late")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if segment.isCompleted {
                        Text("Completed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
            }

            if let stopwatchText {
                let metricLabel = hasTrackingCompleted ? "Total time" : "Elapsed"
                Label("\(metricLabel): \(stopwatchText)", systemImage: "stopwatch")
                    .font(.caption)
                    .foregroundStyle(isTimerRunning ? Color.accentColor : .secondary)
            }

            HStack(spacing: 12) {
                if !hasTrackingStarted && !hasTrackingCompleted {
                    Button("Start", action: onStart)
                        .buttonStyle(.bordered)
                } else if hasTrackingStarted && !hasTrackingCompleted {
                    if isTimerRunning {
                        Button("Pause", action: onPause)
                            .buttonStyle(.bordered)
                    } else {
                        Button("Resume", action: onStart)
                            .buttonStyle(.bordered)
                    }

                    Button("Done") {
                        showFinishConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog("Mark this segment as done?", isPresented: $showFinishConfirmation, titleVisibility: .visible) {
            Button("Mark as done", role: .destructive, action: onFinish)
            Button("Cancel", role: .cancel, action: {})
        }
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func durationLabel(for minutes: Int) -> String {
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours > 0 && remaining > 0 {
            return "\(hours)h \(remaining)m"
        } else if hours > 0 {
            return "\(hours)h"
        }
        return "\(remaining)m"
    }
}
