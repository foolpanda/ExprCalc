//
//  ContentView.swift
//  ExprCalc
//
//  Created by foolpanda on 2026/10/1.
//
//  主界面：左侧 30% 变量面板，右侧 70% 表达式输入 → 计算 → 结果 → 函数参考
//

import SwiftUI
import Combine

// MARK: - 数据模型

struct Variable: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var value: Double
}

// MARK: - 视图模型

@MainActor
final class CalcViewModel: ObservableObject {

    @Published var variables: [Variable] = [
        Variable(name: "x", value: 3),
        Variable(name: "y", value: 4),
        Variable(name: "r", value: 5),
        Variable(name: "t", value: 1.5)
    ]

    @Published var expression: String = "sqrt(x^2 + y^2)"
    @Published var result: String?
    @Published var error: String?

    private var variableDict: [String: Double] {
        Dictionary(
            variables
                .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ($0.name, $0.value) },
            uniquingKeysWith: { _, b in b }
        )
    }

    func compute() {
        result = nil
        error = nil

        let expr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty else {
            error = "请输入表达式"
            return
        }

        do {
            let evaluator = ExprEvaluator(variables: variableDict)
            let value = try evaluator.evaluate(expr)

            if value.isNaN {
                error = "计算结果为 NaN（例如 0/0、sqrt(-1)）"
                return
            }
            if value.isInfinite {
                error = "计算结果溢出（趋于无穷大）"
                return
            }

            if value.truncatingRemainder(dividingBy: 1) == 0 {
                result = String(format: "= %g", value)
            } else {
                result = String(format: "= %.6g", value)
            }
        } catch let e as ParseError {
            error = e.message
        } catch {
            self.error = "计算失败：\(error.localizedDescription)"
        }
    }

    func addVariable() {
        let base = "v"
        var n = 1
        var name = base
        while variables.contains(where: { $0.name == name }) {
            n += 1
            name = "\(base)\(n)"
        }
        withAnimation { variables.append(Variable(name: name, value: 0)) }
    }

    func removeVariable(at offsets: IndexSet) {
        guard variables.count > offsets.count else { return }
        withAnimation { variables.remove(atOffsets: offsets) }
    }

    func resetVariables() {
        withAnimation {
            variables = [
                Variable(name: "x", value: 3),
                Variable(name: "y", value: 4),
                Variable(name: "r", value: 5),
                Variable(name: "t", value: 1.5)
            ]
        }
    }
}

// MARK: - 主视图

struct ContentView: View {
    @StateObject private var vm = CalcViewModel()

    var body: some View {
        HStack(spacing: 0) {
            variablePanel
                .layoutPriority(0)
            Divider()
            expressionPanel
                .layoutPriority(1)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("计算", systemImage: "equal.circle") { vm.compute() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("重置变量", systemImage: "arrow.counterclockwise") { vm.resetVariables() }
            }
        }
    }

    // MARK: 左面板：变量（30%）
    private var variablePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("变量", systemImage: "v.square")
                    .font(.headline)
                Spacer()
                Text("\(vm.variables.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)

            List {
                ForEach($vm.variables) { $v in
                    HStack(spacing: 8) {
                        TextField("名称", text: $v.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .autocorrectionDisabled()
                        Text("=")
                            .foregroundStyle(.secondary)
                        TextField("值", value: $v.value, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: vm.removeVariable)
            }
            .listStyle(.inset)

            HStack {
                Button { vm.addVariable() } label: {
                    Label("添加变量", systemImage: "plus")
                }
                Spacer()
                Text("提示：左滑可删除")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)

            Divider().padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("当前变量值").font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(vm.variables) { v in
                            if !v.name.isEmpty {
                                Text("\(v.name) = \(format(v.value))")
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 240)
    }

    // MARK: 右面板：输入 + 按钮 + 结果 + 参考（70%）
    private var expressionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ① 输入框
            VStack(alignment: .leading, spacing: 6) {
                Text("数学表达式").font(.headline)
                TextEditor(text: $vm.expression)
                    .font(.title2.monospaced())
                    .padding(8)
                    .frame(minHeight: 60, maxHeight: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .onKeyPress(.return) {
                        vm.compute()
                        return .handled
                    }
                Text("按 Return 或 ⌘Return 立即计算").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // ② 计算按钮
            HStack {
                Button { vm.compute() } label: {
                    Label("计  算", systemImage: "play.fill")
                        .font(.headline)
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)

                Button("清空") {
                    vm.expression = ""
                    vm.result = nil
                    vm.error = nil
                }
                .controlSize(.large)
                Spacer()
            }
            .padding(.horizontal, 16)

            // ③ 结果 / 错误
            VStack(alignment: .leading, spacing: 6) {
                if let r = vm.result {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(r).font(.title.monospaced())
                    }
                    .transition(.slide.combined(with: .opacity))
                }
                if let e = vm.error {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        Text(e).font(.body.monospaced()).foregroundStyle(.red)
                    }
                    .transition(.slide.combined(with: .opacity))
                }
            }
            .frame(minHeight: 44, alignment: .leading)
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 0.2), value: vm.result)
            .animation(.easeInOut(duration: 0.2), value: vm.error)

            Divider()

            // ④ 支持的运算与函数参考（双列展示，常规窗口下无需滚动）
            VStack(alignment: .leading, spacing: 8) {
                Text("支持的运算与函数").font(.headline)
                ScrollView {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 10) {
                            referenceSection("运算符", items: operators)
                            referenceSection("内置常量", items: constants)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            referenceSection("三角函数", items: trig)
                            referenceSection("对数与指数", items: logarithm)
                            referenceSection("数值处理", items: numeric)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func referenceSection(_ title: String,
                                  items: [(proto: String, desc: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            ForEach(items, id: \.proto) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.proto)
                        .font(.callout.monospaced())
                        .foregroundStyle(.blue)
                        .frame(width: 110, alignment: .leading)
                    Text("—")
                        .foregroundStyle(.quaternary)
                    Text(item.desc)
                        .font(.callout)
                }
            }
        }
    }

    private let operators: [(String, String)] = [
        ("a + b",        "加法"),
        ("a - b",        "减法"),
        ("a * b",        "乘法"),
        ("a / b",        "除法（除零报错）"),
        ("a ^ b",        "幂运算，右结合：2^3^2 = 2^(3²) = 512"),
        ("( ... )",      "括号，提升优先级"),
        ("-a",           "一元负号，优先级低于 ^：-3^2 = -9")
    ]

    private let constants: [(String, String)] = [
        ("pi",  "圆周率 π ≈ 3.14159"),
        ("e",   "自然常数 e ≈ 2.71828")
    ]

    private let trig: [(String, String)] = [
        ("sin(x)",   "正弦（参数单位：弧度）"),
        ("cos(x)",   "余弦（参数单位：弧度）"),
        ("tan(x)",   "正切（参数单位：弧度）"),
        ("deg(r)",   "弧度 → 角度，r × 180 / π"),
        ("rad(d)",   "角度 → 弧度，d × π / 180")
    ]

    private let logarithm: [(String, String)] = [
        ("ln(x)",      "自然对数（以 e 为底）"),
        ("log(x)",     "常用对数（以 10 为底），log(100) = 2"),
        ("log(b, x)",  "以 b 为底的对数，log(2, 8) = 3"),
        ("exp(x)",     "e 的 x 次幂"),
        ("pow(a, b)",  "a 的 b 次幂"),
        ("sqrt(x)",    "平方根（x ≥ 0）")
    ]

    private let numeric: [(String, String)] = [
        ("abs(x)",   "绝对值"),
        ("ceil(x)",  "向上取整"),
        ("floor(x)", "向下取整"),
        ("round(x)", "四舍五入（.5 向偶数）")
    ]

    private func format(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%g", value)
        }
        return String(format: "%.4g", value)
    }
}

#Preview {
    ContentView()
}
