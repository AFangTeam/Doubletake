import SwiftUI

struct JumpToDateView: View {
    let range: ClosedRange<Date>
    var onJump: (Date) -> Void

    @State private var pickedDate: Date

    init(range: ClosedRange<Date>, initial: Date? = nil, onJump: @escaping (Date) -> Void) {
        self.range = range
        self.onJump = onJump
        let mid = initial ?? Date(timeIntervalSince1970:
            (range.lowerBound.timeIntervalSince1970 + range.upperBound.timeIntervalSince1970) / 2
        )
        self._pickedDate = State(initialValue: mid.clamped(to: range))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("跳转到时间点")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("素材覆盖区间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(format(range.lowerBound))  →  \(format(range.upperBound))")
                    .font(.system(.caption, design: .monospaced))
            }

            DatePicker(
                "目标时间",
                selection: $pickedDate,
                in: range,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)

            Slider(
                value: Binding(
                    get: { pickedDate.timeIntervalSince1970 },
                    set: { pickedDate = Date(timeIntervalSince1970: $0) }
                ),
                in: range.lowerBound.timeIntervalSince1970 ... range.upperBound.timeIntervalSince1970
            )

            HStack {
                Button("跳到起点") { pickedDate = range.lowerBound }
                Button("跳到中点") {
                    pickedDate = Date(timeIntervalSince1970:
                        (range.lowerBound.timeIntervalSince1970 + range.upperBound.timeIntervalSince1970) / 2
                    )
                }
                Button("跳到终点") { pickedDate = range.upperBound }
            }
            .controlSize(.small)

            Divider()

            HStack {
                Spacer()
                Button("跳转", action: { onJump(pickedDate) })
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func format(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .standard)
    }
}

private extension Date {
    func clamped(to range: ClosedRange<Date>) -> Date {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}
