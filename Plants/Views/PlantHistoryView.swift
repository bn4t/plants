import SwiftUI

struct PlantHistoryView: View {
    let plant: Plant

    @State private var monthAnchor: Date = .now

    private var calendar: Calendar { .current }

    private var monthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: monthAnchor) ?? DateInterval(start: monthAnchor, duration: 0)
    }

    private var monthTitle: String {
        monthAnchor.formatted(.dateTime.month(.wide).year())
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var gridDays: [Date?] {
        let firstOfMonth = monthInterval.start
        let rangeOfDays = calendar.range(of: .day, in: .month, for: firstOfMonth) ?? 1..<1
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in rangeOfDays {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func events(on date: Date) -> (water: Bool, fertilize: Bool) {
        let day = calendar.startOfDay(for: date)
        let events = plant.events.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let water = events.contains { $0.kind == CareEventKind.water.rawValue }
        let fertilize = events.contains { $0.kind == CareEventKind.fertilize.rawValue }
        return (water, fertilize)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }

                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, maybeDate in
                    dayCell(for: maybeDate)
                }
            }

            legend
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(monthTitle)
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()

            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.borderless)

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(canGoForward ? .primary : Color.secondary.opacity(0.4))
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.borderless)
            .disabled(!canGoForward)
        }
    }

    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: monthAnchor) else { return false }
        let nextInterval = calendar.dateInterval(of: .month, for: next) ?? DateInterval(start: next, duration: 0)
        return nextInterval.start <= .now
    }

    private func shiftMonth(by delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        monthAnchor = next
    }

    @ViewBuilder
    private func dayCell(for maybeDate: Date?) -> some View {
        if let date = maybeDate {
            let (water, fertilize) = events(on: date)
            let isToday = calendar.isDateInToday(date)
            let isFuture = date > .now && !isToday
            let dayNumber = calendar.component(.day, from: date)

            VStack(spacing: 4) {
                Text("\(dayNumber)")
                    .font(.callout)
                    .fontWeight(isToday ? .semibold : .regular)
                    .foregroundStyle(dayNumberColor(isToday: isToday, isFuture: isFuture))
                    .frame(width: 32, height: 32)
                    .background {
                        if isToday {
                            Circle().fill(Color.accentColor)
                        }
                    }

                HStack(spacing: 3) {
                    if water {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    }
                    if fertilize {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.green)
                    }
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(height: 48)
        }
    }

    private func dayNumberColor(isToday: Bool, isFuture: Bool) -> Color {
        if isToday { return .white }
        if isFuture { return Color.secondary.opacity(0.5) }
        return .primary
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(systemName: "drop.fill", color: .blue, label: "Watered")
            legendItem(systemName: "leaf.fill", color: .green, label: "Fertilized")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(systemName: String, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
        }
    }
}
