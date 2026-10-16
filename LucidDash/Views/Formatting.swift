import SwiftUI
import LucidCore

extension Double {
    var currency: String {
        formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    var signedCurrency: String {
        (self > 0 ? "+" : "") + currency
    }

    var percent: String {
        formatted(.percent.precision(.fractionLength(0)))
    }

    var pnlColor: Color {
        self > 0 ? .green : (self < 0 ? .red : .secondary)
    }
}

extension AccountStatus {
    var color: Color {
        switch self {
        case .active: .blue
        case .warning: .orange
        case .passed: .green
        case .breached: .red
        }
    }

    var symbol: String {
        switch self {
        case .active: "circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .passed: "checkmark.seal.fill"
        case .breached: "xmark.octagon.fill"
        }
    }
}

struct StatusBadge: View {
    let status: AccountStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.15), in: Capsule())
    }
}

extension Binding where Value == Bool {
    /// True while `optional` holds a value; setting false clears it.
    init<T>(isPresenting optional: Binding<T?>) {
        self.init(
            get: { optional.wrappedValue != nil },
            set: { if !$0 { optional.wrappedValue = nil } }
        )
    }
}
