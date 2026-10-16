import SwiftUI
import LucidCore

struct AddTradeView: View {
    let accountID: UUID

    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss

    @State private var symbol = ""
    @State private var quantity = 1
    @State private var exitTime = Date()
    @State private var pnl: Double?
    @State private var fees: Double = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Symbol (e.g. MNQZ6)", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Stepper("Contracts: \(quantity)", value: $quantity, in: 1...100)
                    DatePicker("Closed", selection: $exitTime)
                }
                Section {
                    LabeledContent("Gross P&L") {
                        TextField("-125.00", value: $pnl, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fees") {
                        TextField("0.00", value: $fees, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Use a minus sign for losing trades.")
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Add Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let pnl else { return }
                        store.addTrade(Trade(
                            symbol: symbol.isEmpty ? "—" : symbol.uppercased(),
                            quantity: quantity,
                            exitTime: exitTime,
                            grossPnL: pnl,
                            fees: abs(fees),
                            note: note.isEmpty ? nil : note
                        ), to: accountID)
                        dismiss()
                    }
                    .disabled(pnl == nil)
                }
            }
        }
    }
}
