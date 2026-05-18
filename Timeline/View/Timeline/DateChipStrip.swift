import SwiftUI

/// 时间线上方的"按日期切片" chip 条。
/// 跨日素材时显示，点 chip → 跳到那天开头。
/// 单日素材时整条不渲染、不占布局。
struct DateChipStrip: View {
    let days: [Date]
    let currentVisibleDay: Date?
    let onSelect: (Date) -> Void

    var body: some View {
        if days.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(days, id: \.timeIntervalSince1970) { day in
                        DateChip(
                            day: day,
                            isCurrent: currentVisibleDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false,
                            onTap: { onSelect(day) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .frame(height: 32)
            .background(.background.secondary.opacity(0.4))
            .overlay(alignment: .bottom) {
                Rectangle().fill(.separator).frame(height: 0.5)
            }
        }
    }
}

private struct DateChip: View {
    let day: Date
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(day.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular, design: .rounded))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(isCurrent ? Color.accentColor.opacity(0.18) : .clear)
                )
                .overlay(
                    Capsule().strokeBorder(
                        isCurrent ? Color.accentColor.opacity(0.5) : Color(NSColor.separatorColor).opacity(0.5),
                        lineWidth: 0.5
                    )
                )
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
