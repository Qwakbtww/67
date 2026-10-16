import SwiftUI
import LucidCore

/// Create or edit an account and the rules it's measured against.
struct AccountEditorView: View {
    let existing: TradingAccount?

    @EnvironmentObject private var store: AccountStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var accountNumber: String
    @State private var phase: AccountPhase
    @State private var startingBalance: Double
    @State private var hasTarget: Bool
    @State private var profitTarget: Double
    @State private var maxDrawdown: Double
    @State private var drawdownType: DrawdownType
    @State private var hasLock: Bool
    @State private var lockOffset: Double
    @State private var hasDailyLimit: Bool
    @State private var dailyLossLimit: Double
    @State private var hasConsistency: Bool
    @State private var consistencyPercent: Double
    @State private var confirmingDelete = false

    init(account: TradingAccount?) {
        existing = account
        let r = account?.rules ?? RulePreset.all[1].rules
        _name = State(initialValue: account?.name ?? "")
        _accountNumber = State(initialValue: account?.accountNumber ?? "")
        _phase = State(initialValue: account?.phase ?? .evaluation)
        _startingBalance = State(initialValue: r.startingBalance)
        _hasTarget = State(initialValue: r.profitTarget != nil)
        _profitTarget = State(initialValue: r.profitTarget ?? 3_000)
        _maxDrawdown = State(initialValue: r.maxDrawdown)
        _drawdownType = State(initialValue: r.drawdownType)
        _hasLock = State(initialValue: r.drawdownLockOffset != nil)
        _lockOffset = State(initialValue: r.drawdownLockOffset ?? 100)
        _hasDailyLimit = State(initialValue: r.dailyLossLimit != nil)
        _dailyLossLimit = State(initialValue: r.dailyLossLimit ?? 1_000)
        _hasConsistency = State(initialValue: r.consistencyLimit != nil)
        _consistencyPercent = State(initialValue: (r.consistencyLimit ?? 0.5) * 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name (e.g. LucidFlex 50K #1)", text: $name)
                    TextField("Account number (optional)", text: $accountNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("Phase", selection: $phase) {
                        ForEach(AccountPhase.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(RulePreset.all) { preset in
                                Button(preset.name) { apply(preset) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                } header: {
                    Text("Start from a preset")
                } footer: {
                    Text("Presets are starting points only. Check your plan's current rules on Lucid's site and adjust the values below to match.")
                }

                Section("Balance & target") {
                    money("Starting balance", $startingBalance)
                    if phase == .evaluation || hasTarget {
                        Toggle("Profit target", isOn: $hasTarget)
                        if hasTarget { money("Target profit", $profitTarget) }
                    }
                }

                Section {
                    money("Max drawdown", $maxDrawdown)
                    Picker("Type", selection: $drawdownType) {
                        ForEach(DrawdownType.allCases) { Text($0.label).tag($0) }
                    }
                    if drawdownType != .fixed {
                        Toggle("Stops trailing", isOn: $hasLock)
                        if hasLock { money("…at start balance +", $lockOffset) }
                    }
                } header: {
                    Text("Drawdown")
                } footer: {
                    Text("The floor trails your peak balance by the max drawdown. With \"Stops trailing\" on, it freezes once it reaches the starting balance plus the amount set.")
                }

                Section("Other rules") {
                    Toggle("Daily loss limit", isOn: $hasDailyLimit)
                    if hasDailyLimit { money("Daily loss limit", $dailyLossLimit) }
                    Toggle("Consistency rule", isOn: $hasConsistency)
                    if hasConsistency {
                        Stepper(value: $consistencyPercent, in: 10...100, step: 5) {
                            LabeledContent("Best day ≤", value: "\(Int(consistencyPercent))% of profit")
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("Delete Account", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || startingBalance <= 0 || maxDrawdown <= 0)
                }
            }
            .confirmationDialog("Delete this account and all its trades?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { store.delete(id: existing.id) }
                    dismiss()
                }
            }
        }
    }

    private func money(_ title: String, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private func apply(_ preset: RulePreset) {
        let r = preset.rules
        if name.isEmpty { name = "\(preset.name) \(phase.label)" }
        startingBalance = r.startingBalance
        hasTarget = r.profitTarget != nil
        profitTarget = r.profitTarget ?? profitTarget
        maxDrawdown = r.maxDrawdown
        drawdownType = r.drawdownType
        hasLock = r.drawdownLockOffset != nil
        lockOffset = r.drawdownLockOffset ?? lockOffset
        hasDailyLimit = r.dailyLossLimit != nil
        dailyLossLimit = r.dailyLossLimit ?? dailyLossLimit
        hasConsistency = r.consistencyLimit != nil
        consistencyPercent = (r.consistencyLimit ?? consistencyPercent / 100) * 100
    }

    private func save() {
        let rules = AccountRules(
            startingBalance: startingBalance,
            profitTarget: hasTarget ? profitTarget : nil,
            maxDrawdown: maxDrawdown,
            drawdownType: drawdownType,
            drawdownLockOffset: hasLock && drawdownType != .fixed ? lockOffset : nil,
            dailyLossLimit: hasDailyLimit ? dailyLossLimit : nil,
            consistencyLimit: hasConsistency ? consistencyPercent / 100 : nil
        )
        var account = existing ?? TradingAccount(name: name, rules: rules)
        account.name = name.trimmingCharacters(in: .whitespaces)
        account.accountNumber = accountNumber.trimmingCharacters(in: .whitespaces)
        account.phase = phase
        account.rules = rules
        store.upsert(account)
        dismiss()
    }
}
