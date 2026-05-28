import SwiftUI

struct GalleryCalendarFilterSheet: View {
    let sessions: [SessionWithPreview]
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var environmentCalendar
    @State private var visibleMonth: Date
    @State private var draftStart: Date
    @State private var draftEnd: Date
    @State private var pendingAnchor: Date?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 7)

    init(
        sessions: [SessionWithPreview],
        startDate: Binding<Date>,
        endDate: Binding<Date>,
        onApply: @escaping () -> Void
    ) {
        self.sessions = sessions
        self._startDate = startDate
        self._endDate = endDate
        self.onApply = onApply

        let month = GalleryCalendarMonth.startOfMonth(for: startDate.wrappedValue)
        self._visibleMonth = State(initialValue: month)
        self._draftStart = State(initialValue: startDate.wrappedValue)
        self._draftEnd = State(initialValue: endDate.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                monthHeader
                weekdayHeader
                dayGrid
                selectedRangeSummary
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .navigationTitle("gallery_filter_custom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("button_cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("button_save") {
                        startDate = draftStart
                        endDate = draftEnd
                        onApply()
                        dismiss()
                    }
                }
            }
        }
    }

    private var calendar: Calendar {
        environmentCalendar
    }

    private var displayedDays: [GalleryCalendarDay] {
        GalleryCalendarMonth.days(for: visibleMonth, calendar: calendar)
    }

    private var recordedDays: Set<Date> {
        GalleryCalendarMonth.recordedDays(in: sessions, calendar: calendar)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("gallery_calendar_previous_month"))

            Spacer()

            Text(visibleMonth.formatted(.dateTime.year().month(.wide)))
                .font(.headline)

            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("gallery_calendar_next_month"))
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: Spacing.xs) {
            ForEach(GalleryCalendarMonth.orderedWeekdaySymbols(calendar: calendar), id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.xs) {
            ForEach(displayedDays) { day in
                dayCell(day)
            }
        }
    }

    private var selectedRangeSummary: some View {
        Text(selectedRangeText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.sm)
    }

    private var selectedRangeText: String {
        let lower = min(draftStart, draftEnd)
        let upper = max(draftStart, draftEnd)
        return String(
            format: String(localized: "gallery_calendar_selected_range_format"),
            lower.formatted(date: .numeric, time: .omitted),
            upper.formatted(date: .numeric, time: .omitted)
        )
    }

    private func dayCell(_ day: GalleryCalendarDay) -> some View {
        let normalized = calendar.startOfDay(for: day.date)
        let isEndpoint = isSameDay(normalized, draftStart) || isSameDay(normalized, draftEnd)
        let isInRange = normalized >= calendar.startOfDay(for: min(draftStart, draftEnd))
            && normalized <= calendar.startOfDay(for: max(draftStart, draftEnd))
        let hasRecord = recordedDays.contains(normalized)

        return Button {
            select(normalized)
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: normalized))")
                    .font(.callout.weight(isEndpoint ? .semibold : .regular))
                    .foregroundStyle(dayTextStyle(isEndpoint: isEndpoint, isInDisplayedMonth: day.isInDisplayedMonth))
                    .frame(width: 34, height: 30)
                    .background {
                        if isEndpoint {
                            Circle().fill(Color.accentColor)
                        }
                    }

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: 4)
                    .opacity(hasRecord ? (day.isInDisplayedMonth ? 1 : 0.35) : 0)
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background {
                if isInRange && !isEndpoint {
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .fill(Color.accentColor.opacity(day.isInDisplayedMonth ? 0.16 : 0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(normalized.formatted(date: .complete, time: .omitted)))
        .accessibilityValue(hasRecord ? Text("gallery_calendar_recorded_day") : Text(""))
    }

    private func dayTextStyle(isEndpoint: Bool, isInDisplayedMonth: Bool) -> AnyShapeStyle {
        if isEndpoint {
            return AnyShapeStyle(Color.white)
        }
        if isInDisplayedMonth {
            return AnyShapeStyle(Color.primary)
        }
        return AnyShapeStyle(Color.secondary.opacity(0.45))
    }

    private func moveMonth(by offset: Int) {
        visibleMonth = GalleryCalendarMonth.startOfMonth(
            for: calendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth,
            calendar: calendar
        )
    }

    private func select(_ date: Date) {
        let normalized = calendar.startOfDay(for: date)
        if let anchor = pendingAnchor {
            draftStart = min(anchor, normalized)
            draftEnd = max(anchor, normalized)
            pendingAnchor = nil
        } else {
            draftStart = normalized
            draftEnd = normalized
            pendingAnchor = normalized
        }

        visibleMonth = GalleryCalendarMonth.startOfMonth(for: normalized, calendar: calendar)
    }

    private func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }
}
