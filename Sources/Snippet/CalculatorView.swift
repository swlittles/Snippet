import SwiftUI

struct CalculatorView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var calculator: CalculatorStore
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var shortcuts: ShortcutStore
    @State private var confirmClear = false
    private let keys = ["AC", "(", ")", "⌫", "7", "8", "9", "÷", "4", "5", "6", "×", "1", "2", "3", "−", ".", "0", "%", "+"]
    var body: some View {
        VStack(spacing: 0) {
            display
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 7) {
                    HStack(spacing: 6) {
                        ForEach(["sqrt(", "^", "pi", "ans"], id: \.self) { key in keyButton(key) }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(keys, id: \.self) { key in keyButton(key) }
                    }
                    Button { model.calculate() } label: { Text("=   Calculate").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 33).background(theme.accent, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(Color(hex: theme.palette.isDark ? 0x11131A : 0xFFFFFF)) }.buttonStyle(PointerButtonStyle())
                }.frame(width: 238)
                history
            }.padding(.horizontal, 20).padding(.bottom, 12)
        }.frame(height: 388)
            .alert("Clear calculation history?", isPresented: $confirmClear) {
                Button("Clear", role: .destructive) { calculator.clear() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your clipboard history and snippets will be kept.") }
    }
    var display: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.calcError ?? (model.calcResult == nil ? "Type an expression above" : "RESULT")).font(.system(size: 10, weight: .medium)).foregroundStyle(model.calcError == nil ? theme.secondary : .orange).lineLimit(1)
                    Text(model.calcResult.map(Calculator.format) ?? "0").font(.system(size: 27, weight: .medium, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.5).textSelection(.enabled)
                }
                Spacer()
                Picker("Angles", selection: $model.degrees) { Text("RAD").tag(false); Text("DEG").tag(true) }.pickerStyle(.segmented).frame(width: 100).help("Angle unit for sin, cos, tan")
                Button { model.copyCalculation() } label: { Image(systemName: "doc.on.doc") }.buttonStyle(PointerButtonStyle()).disabled(model.calcResult == nil).help("Copy result · " + shortcuts.label(.copyCalculation))
            }
            Text("+ − × ÷  ^ powers  % ÷100  ! factorial · sin, cos, tan, log, ln, sqrt · pi, e, ans").font(.system(size: 9)).foregroundStyle(theme.secondary).lineLimit(1)
        }.padding(.horizontal, 20).padding(.vertical, 13)
    }
    func keyButton(_ key: String) -> some View {
        Button { model.calculatorKey(key) } label: {
            Text(key == "sqrt(" ? "√" : key).font(.system(size: 15, weight: .medium, design: .rounded)).frame(maxWidth: .infinity).frame(height: 31)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(PointerButtonStyle())
    }
    var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HISTORY").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondary)
                Spacer()
                Button("Clear") { confirmClear = true }.font(.system(size: 10)).disabled(calculator.entries.isEmpty).buttonStyle(PointerButtonStyle())
            }
            if let error = calculator.error { Text(error).font(.caption).foregroundStyle(.orange) }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(calculator.entries) { entry in
                        HStack(spacing: 8) {
                            Button {
                                model.degrees = entry.degrees
                                model.expression = entry.expression
                                model.calcResult = entry.result
                                model.calcError = nil
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.expression).font(.system(size: 11)).foregroundStyle(theme.secondary).lineLimit(1)
                                    Text("= " + entry.formatted).font(.system(size: 14, weight: .medium, design: .monospaced)).lineLimit(1)
                                    Text(entry.degrees ? "DEG" : "RAD").font(.system(size: 8)).foregroundStyle(theme.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(PointerButtonStyle()).help("Reuse this calculation")
                            Button { model.copyResult(entry.formatted) } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)) }.buttonStyle(PointerButtonStyle()).help("Copy this result")
                        }.padding(10).background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                    }
                    if calculator.entries.isEmpty { Text("Your calculations will appear here.\nPress " + shortcuts.label(.calculate) + " to save a result.").font(.system(size: 11)).foregroundStyle(theme.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 24) }
                }
            }.frame(height: 230)
        }.frame(maxWidth: .infinity)
    }
}
