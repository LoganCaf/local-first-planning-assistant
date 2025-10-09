import SwiftUI

struct CalendarDayCell: View {
    let day: CalendarDay
    let isSelected: Bool
    let isToday: Bool
    let eventsCount: Int?
    @AppStorage("calendarIndicatorStyle") private var indicatorStyle: String = "centered" // "centered", "bottom", "centeredShape"

    var body: some View {
        ZStack {
            // background circle for the day number
            Circle()
                .fill(backgroundColor)
                .frame(height: 44)

            // centered larger event indicator behind the number (unless user chose bottom-only)
            if let count = eventsCount, count > 0, indicatorStyle != "bottom" {
                if indicatorStyle == "centeredShape" {
                    // render shapes by count: 1 circle, 2 triangle, 3 square, 4+ pentagon
                    Group {
                        switch count {
                        case 1:
                            Circle()
                                .fill(indicatorColor(for: count).opacity(0.22))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(indicatorColor(for: count), lineWidth: 1.0))
                        case 2:
                            Triangle()
                                .fill(indicatorColor(for: count).opacity(0.22))
                                .frame(width: 24, height: 20)
                                .overlay(Triangle().stroke(indicatorColor(for: count), lineWidth: 1.0))
                        case 3:
                            Rectangle()
                                .fill(indicatorColor(for: count).opacity(0.22))
                                .frame(width: 22, height: 22)
                                .overlay(Rectangle().stroke(indicatorColor(for: count), lineWidth: 1.0))
                        default:
                            Pentagon()
                                .fill(indicatorColor(for: count).opacity(0.22))
                                .frame(width: 24, height: 24)
                                .overlay(Pentagon().stroke(indicatorColor(for: count), lineWidth: 1.0))
                        }
                    }
                } else {
                    Circle()
                        .fill(indicatorColor(for: count).opacity(0.22))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(indicatorColor(for: count), lineWidth: 1.0)
                        )
                }
            }

            Text("\(day.number)")
                .font(.body)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(textColor)
        }
        .frame(height: 44)
        // show small bottom dot only for the explicit "bottom" style
        .overlay(alignment: .bottom) {
            if let count = eventsCount, count > 0, indicatorStyle == "bottom" {
                Circle()
                    .fill(indicatorColor(for: count))
                    .frame(width: 10, height: 10)
                    .padding(.bottom, 4)
            }
        }
        .opacity(day.isWithinDisplayedMonth ? 1.0 : 0.4)
    }
}

private extension CalendarDayCell {
    var textColor: Color {
        if isSelected {
            return .white
        }
        if isToday {
            return .accentColor
        }
        return .primary
    }

    var backgroundColor: Color {
        if isSelected {
            return .accentColor
        }
        if isToday {
            return Color.accentColor.opacity(0.15)
        }
        return .clear
    }
}

private extension CalendarDayCell {
    func indicatorColor(for count: Int) -> Color {
        switch count {
        case 1:
            return .green
        case 2:
            return .yellow
        case 3:
            return Color.orange
        default:
            return .red
        }
    }
}

// MARK: - Custom shapes
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        path.move(to: top)
        path.addLine(to: bottomLeft)
        path.addLine(to: bottomRight)
        path.closeSubpath()
        return path
    }
}

struct Pentagon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        let angle = (2 * Double.pi) / 5
        for i in 0..<5 {
            let theta = Double(i) * angle - Double.pi / 2
            let x = cx + CGFloat(cos(theta)) * r
            let y = cy + CGFloat(sin(theta)) * r
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}
