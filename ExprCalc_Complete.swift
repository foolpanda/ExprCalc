//
//  ExprCalc_Complete.swift
//  ═══════════════════════════════════════════════════════════════════════════
//  单文件完整版 —— macOS SwiftUI 表达式计算器
//
//  使用方法（二选一）：
//    A) Xcode：新建 macOS App → 用本文件替换 ContentView.swift → ⌘R
//    B) 命令行：swift verify_engine.swift   （仅验证引擎，无需 Xcode）
//
//  功能：
//    ✅ 左侧 30% 变量面板（增/删/改）
//    ✅ 右侧 70% 表达式输入 → 计算按钮 → 结果 → 函数参考
//    ✅ Return / ⌘Return / 按钮 三种方式触发计算
//    ✅ 鼠标可完成全部输入：数字/括号/退格按键行 + 运算符/函数/变量点击插入光标处
//    ✅ 运算符：+ - * / ^ ( )  ，幂右结合，一元负号低于幂
//    ✅ 函数：sin cos tan deg rad ln log exp pow sqrt abs ceil floor round
//    ✅ 常量：pi, e
//    ✅ 完整中文错误处理
//  ═══════════════════════════════════════════════════════════════════════════
//

import SwiftUI
import Combine

// MARK: - ════════════════════════════════════════════════════════════════════
//  第一部分：表达式求值引擎
//  ═══════════════════════════════════════════════════════════════════════════

enum Token: Equatable {
    case number(Double)
    case identifier(String)
    case plus, minus, mul, div, pow, lparen, rparen, comma
}

struct ParseError: Error, CustomStringConvertible, Identifiable {
    let id = UUID()
    let message: String
    init(_ m: String) { message = m }
    var description: String { message }
}

final class ExprEvaluator {

    private let variables: [String: Double]
    private var tokens: [Token] = []
    private var pos: Int = 0

    private let builtins: Set<String> = [
        "sin", "cos", "tan", "deg", "rad",
        "ln", "log", "exp", "pow", "sqrt",
        "abs", "ceil", "floor", "round"
    ]

    private let constants: [String: Double] = [
        "pi": Double.pi,
        "e":  M_E
    ]

    init(variables: [String: Double] = [:]) {
        self.variables = variables
    }

    // MARK: 公开 API
    func evaluate(_ expression: String) throws -> Double {
        tokens = try tokenize(expression)
        pos = 0
        let value = try parseExpression()
        if !isAtEnd {
            throw ParseError("表达式末尾存在多余字符")
        }
        return value
    }

    // MARK: 词法分析
    private func tokenize(_ input: String) throws -> [Token] {
        var result: [Token] = []
        var iter = input.unicodeScalars.makeIterator()
        var peekBuffer: UnicodeScalar?

        func peek() -> UnicodeScalar? {
            if peekBuffer == nil { peekBuffer = iter.next() }
            return peekBuffer
        }
        func advance() -> UnicodeScalar? {
            if let p = peekBuffer { peekBuffer = nil; return p }
            return iter.next()
        }

        while let ch = peek() {
            if ch == " " || ch == "\t" { _ = advance(); continue }

            if ("0"..."9").contains(ch) || ch == "." {
                var buffer = ""
                var seenDot = false
                while let c = peek(), ("0"..."9").contains(c) || c == "." {
                    _ = advance()
                    if c == "." {
                        if seenDot { throw ParseError("数字中包含多个小数点") }
                        seenDot = true
                    }
                    buffer.append(String(c))
                }
                if buffer == "." { throw ParseError("无效的数字字面量 '.'") }
                guard let d = Double(buffer) else {
                    throw ParseError("无法解析数字：\(buffer)")
                }
                result.append(.number(d))
                continue
            }

            if ("a"..."z").contains(ch) || ("A"..."Z").contains(ch) || ch == "_" {
                var buffer = ""
                while let c = peek(),
                      ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "_" {
                    _ = advance()
                    buffer.append(String(c))
                }
                result.append(.identifier(buffer))
                continue
            }

            _ = advance()
            switch ch {
            case "+": result.append(.plus)
            case "-": result.append(.minus)
            case "*": result.append(.mul)
            case "/": result.append(.div)
            case "^": result.append(.pow)
            case "(": result.append(.lparen)
            case ")": result.append(.rparen)
            case ",": result.append(.comma)
            default:  throw ParseError("未识别的字符：\(String(ch))")
            }
        }
        return result
    }

    // MARK: 语法分析（递归下降）
    //
    // 优先级（由低到高）：
    //   expression  : term
    //   term        : factor (('+'|'-') factor)*
    //   factor      : unary (('*'|'/') unary)*
    //   unary       : ('-') unary | power        ← 负号低于 ^
    //   power       : primary ('^' power)*       ← 右结合
    //   primary     : number | identifier | funcCall | '(' expr ')'

    private var isAtEnd: Bool { pos >= tokens.count }

    private func match(_ kinds: Token...) -> Bool {
        for k in kinds {
            if !isAtEnd && tokens[pos] == k {
                pos += 1
                return true
            }
        }
        return false
    }

    private func consume(_ kind: Token, _ message: String) throws {
        if !isAtEnd && tokens[pos] == kind {
            pos += 1
            return
        }
        throw ParseError(message)
    }

    private func parseExpression() throws -> Double { try parseTerm() }

    private func parseTerm() throws -> Double {
        var left = try parseFactor()
        while true {
            if match(.plus) {
                left = left + (try parseFactor())
            } else if match(.minus) {
                left = left - (try parseFactor())
            } else {
                break
            }
        }
        return left
    }

    private func parseFactor() throws -> Double {
        var left = try parseUnary()
        while true {
            if match(.mul) {
                left = left * (try parseUnary())
            } else if match(.div) {
                let right = try parseUnary()
                if right == 0 { throw ParseError("除以零") }
                left = left / right
            } else {
                break
            }
        }
        return left
    }

    /// 一元负号（优先级低于 ^，故 `-3^2 = -9`）
    private func parseUnary() throws -> Double {
        if match(.minus) {
            return -(try parseUnary())
        }
        return try parsePower()
    }

    /// 幂运算（右结合：`2^3^2` = `2^(3^2)` = 512）
    private func parsePower() throws -> Double {
        let base = try parsePrimary()
        if match(.pow) {
            let exponent = try parsePower()
            return Darwin.pow(base, exponent)
        }
        return base
    }

    private func parsePrimary() throws -> Double {
        // 数字 / 标识符按「类型」匹配（match 是按值比较，只能用于无关联值的符号）
        if !isAtEnd, case let .number(v) = tokens[pos] {
            pos += 1
            return v
        }

        if !isAtEnd, case let .identifier(name) = tokens[pos] {
            pos += 1
            if match(.lparen) {
                return try evaluateFunction(name)
            }
            if let c = constants[name] { return c }
            if let v = variables[name] { return v }
            throw ParseError("未定义的变量或函数：\(name)")
        }

        if match(.lparen) {
            let value = try parseExpression()
            try consume(.rparen, "缺少右括号")
            return value
        }

        throw ParseError("期望数字、变量、函数或左括号")
    }

    private func evaluateFunction(_ name: String) throws -> Double {
        guard builtins.contains(name) else {
            throw ParseError("未知函数：\(name)")
        }

        var args: [Double] = []
        if !(isAtEnd || tokens[pos] == .rparen) {
            args.append(try parseExpression())
            while match(.comma) {
                args.append(try parseExpression())
            }
        }
        try consume(.rparen, "函数参数列表缺少右括号")

        switch name {
        case "sin":   try require(args, 1, name); return Darwin.sin(args[0])
        case "cos":   try require(args, 1, name); return Darwin.cos(args[0])
        case "tan":   try require(args, 1, name); return Darwin.tan(args[0])
        case "deg":   try require(args, 1, name); return args[0] * 180.0 / Double.pi
        case "rad":   try require(args, 1, name); return args[0] * Double.pi / 180.0
        case "ln":    try require(args, 1, name); return Darwin.log(args[0])
        case "log":
            if args.count == 1 { return Darwin.log10(args[0]) }
            if args.count == 2 { return Darwin.log(args[1]) / Darwin.log(args[0]) }
            throw ParseError("log 接受 1 或 2 个参数：log(x) 或 log(base, x)")
        case "exp":   try require(args, 1, name); return Darwin.exp(args[0])
        case "sqrt":  try require(args, 1, name); return Darwin.sqrt(args[0])
        case "abs":   try require(args, 1, name); return Darwin.fabs(args[0])
        case "ceil":  try require(args, 1, name); return Darwin.ceil(args[0])
        case "floor": try require(args, 1, name); return Darwin.floor(args[0])
        case "round": try require(args, 1, name); return args[0].rounded(.toNearestOrEven) // .5 向偶数
        case "pow":   try require(args, 2, name); return Darwin.pow(args[0], args[1])
        default:
            throw ParseError("未实现的函数：\(name)")
        }
    }

    private func require(_ args: [Double], _ count: Int, _ name: String) throws {
        if args.count != count {
            throw ParseError("\(name) 需要 \(count) 个参数，实际传入 \(args.count) 个")
        }
    }
}

// MARK: - ══════════════════════════════════════════════════════════════════════
//  第二部分：SwiftUI 界面
//  ═══════════════════════════════════════════════════════════════════════════

import AppKit

// MARK: - 表达式编辑控制器（供按键插入，光标感知）

final class ExpressionEditorController {
    fileprivate weak var textView: NSTextView?
    fileprivate var selectedRange = NSRange(location: 0, length: 0)

    /// 在当前光标/选区处插入文本
    /// - caretOffset: 插入后光标相对插入起点的偏移（nil 表示落在插入文本末尾）
    /// - selectLength: 大于 0 时在光标处选中占位符（如 sin(x) 中的 x，可直接输入覆盖）
    func insert(_ snippet: String, caretOffset: Int? = nil, selectLength: Int = 0) {
        guard let tv = textView else { return }
        let sel = normalizedSelection(of: tv)
        let offset = min(caretOffset ?? (snippet as NSString).length, (snippet as NSString).length)
        let newSelection = NSRange(location: sel.location + offset, length: selectLength)
        performEdit(on: tv, range: sel, replacement: snippet, newSelection: newSelection)
    }

    /// 退格：有选区先删选区，否则删除光标前一个字符
    func backspace() {
        guard let tv = textView else { return }
        let sel = normalizedSelection(of: tv)
        if sel.length > 0 {
            performEdit(on: tv, range: sel, replacement: "",
                        newSelection: NSRange(location: sel.location, length: 0))
        } else if sel.location > 0 {
            let previous = NSRange(location: sel.location - 1, length: 1)
            performEdit(on: tv, range: previous, replacement: "",
                        newSelection: NSRange(location: previous.location, length: 0))
        }
    }

    private func normalizedSelection(of tv: NSTextView) -> NSRange {
        let length = (tv.string as NSString).length
        let sel = tv.selectedRange()
        if sel.location == NSNotFound || sel.location > length {
            return NSRange(location: length, length: 0)
        }
        return sel
    }

    /// 支持 undo 的程序化编辑；编辑后把键盘焦点交还给文本框
    private func performEdit(on tv: NSTextView, range: NSRange, replacement: String, newSelection: NSRange) {
        tv.shouldChangeText(in: range, replacementString: replacement)
        tv.textStorage?.replaceCharacters(in: range, with: replacement)
        tv.didChangeText()
        tv.setSelectedRange(newSelection)
        tv.scrollRangeToVisible(newSelection)
        if tv.window?.firstResponder !== tv {
            tv.window?.makeFirstResponder(tv)
        }
    }
}

// MARK: - 表达式编辑器（NSTextView 封装，向控制器同步光标）

struct ExpressionEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: ExpressionEditorController
    var onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.focusRingType = .none

        let tv = NSTextView()
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFontPanel = false
        tv.smartInsertDeleteEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 21, weight: .regular)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 2, height: 8)
        tv.string = text
        tv.delegate = context.coordinator

        scrollView.documentView = tv

        controller.textView = tv
        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            // 初始光标落在表达式末尾，点击按键即追加油
            let end = NSRange(location: (tv.string as NSString).length, length: 0)
            tv.setSelectedRange(end)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        controller.textView = tv
        if tv.string != text {
            tv.string = text
            let length = (text as NSString).length
            let location = min(controller.selectedRange.location, length)
            tv.setSelectedRange(NSRange(location: location, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ExpressionEditor
        init(_ parent: ExpressionEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.controller.selectedRange = tv.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.controller.selectedRange = tv.selectedRange()
        }

        // Return 触发计算，不插入换行
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onReturn()
                return true
            }
            return false
        }
    }
}

// MARK: - 视图模型

@MainActor
final class CalcViewModel: ObservableObject {

    let editor = ExpressionEditorController()

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

    /// 按键/参考项/变量插入到光标处
    func insert(_ snippet: String, caretOffset: Int? = nil, selectLength: Int = 0) {
        editor.insert(snippet, caretOffset: caretOffset, selectLength: selectLength)
    }

    func backspace() {
        editor.backspace()
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
                Text("当前变量值（点击插入）").font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(vm.variables) { v in
                            if !v.name.isEmpty {
                                VariableChip(name: v.name, value: format(v.value)) {
                                    vm.insert(v.name)
                                }
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

    // MARK: 右面板：输入 + 按键行 + 按钮 + 结果 + 参考（70%）
    private var expressionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ① 输入框 + 按键行
            VStack(alignment: .leading, spacing: 6) {
                Text("数学表达式").font(.headline)
                ExpressionEditor(text: $vm.expression, controller: vm.editor, onReturn: { vm.compute() })
                    .frame(minHeight: 60, maxHeight: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )

                // 输入框下方第一行：数字 / 小数点 / 括号 / 退格
                keypadRow

                Text("按 Return 或 ⌘Return 立即计算；按键与参考项插入到光标处")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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

            // ④ 支持的运算与函数参考（双列展示，点击插入）
            VStack(alignment: .leading, spacing: 8) {
                Text("支持的运算与函数（点击插入）").font(.headline)
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

    // MARK: 数字/括号/退格按键行

    private var keypadRow: some View {
        HStack(spacing: 5) {
            ForEach(0..<10, id: \.self) { digit in
                keyButton("\(digit)", tip: "插入 \(digit)") { vm.insert("\(digit)") }
            }
            keyButton(".", tip: "插入小数点") { vm.insert(".") }
            keyButton("(", tip: "插入左括号") { vm.insert("(", caretOffset: 1) }
            keyButton(")", tip: "插入右括号") { vm.insert(")") }
            Button {
                vm.backspace()
            } label: {
                Image(systemName: "delete.left")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(KeyCapStyle())
            .help("退格：删除光标前一个字符")
            .pointerStyle(.link)
        }
    }

    private func keyButton(_ label: String, tip: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.body.monospaced().weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(KeyCapStyle())
        .help(tip)
        .pointerStyle(.link)
    }

    // MARK: 参考列表

    private func referenceSection(_ title: String,
                                  items: [ReferenceItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            ForEach(items, id: \.proto) { item in
                ReferenceRow(item: item) {
                    vm.insert(item.insert, caretOffset: item.caretOffset,
                              selectLength: item.selectLength)
                }
            }
        }
    }

    // MARK: 参考数据（insert 为点击后插入的文本；caretOffset/selectLength 定位占位符）

    private let operators: [ReferenceItem] = [
        ReferenceItem("a + b",   "加法", insert: "+"),
        ReferenceItem("a - b",   "减法", insert: "-"),
        ReferenceItem("a * b",   "乘法", insert: "*"),
        ReferenceItem("a / b",   "除法（除零报错）", insert: "/"),
        ReferenceItem("a ^ b",   "幂运算，右结合：2^3^2 = 2^(3²) = 512", insert: "^"),
        ReferenceItem("( ... )", "括号，提升优先级", insert: "()", caretOffset: 1),
        ReferenceItem("-a",      "一元负号，优先级低于 ^：-3^2 = -9", insert: "-")
    ]

    private let constants: [ReferenceItem] = [
        ReferenceItem("pi", "圆周率 π ≈ 3.14159"),
        ReferenceItem("e",  "自然常数 e ≈ 2.71828")
    ]

    private let trig: [ReferenceItem] = [
        ReferenceItem("sin(x)", "正弦（参数单位：弧度）", caretOffset: 4, selectLength: 1),
        ReferenceItem("cos(x)", "余弦（参数单位：弧度）", caretOffset: 4, selectLength: 1),
        ReferenceItem("tan(x)", "正切（参数单位：弧度）", caretOffset: 4, selectLength: 1),
        ReferenceItem("deg(r)", "弧度 → 角度，r × 180 / π", caretOffset: 4, selectLength: 1),
        ReferenceItem("rad(d)", "角度 → 弧度，d × π / 180", caretOffset: 4, selectLength: 1)
    ]

    private let logarithm: [ReferenceItem] = [
        ReferenceItem("ln(x)",     "自然对数（以 e 为底）", caretOffset: 3, selectLength: 1),
        ReferenceItem("log(x)",    "常用对数（以 10 为底），log(100) = 2", caretOffset: 4, selectLength: 1),
        ReferenceItem("log(b, x)", "以 b 为底的对数，log(2, 8) = 3", caretOffset: 4, selectLength: 1),
        ReferenceItem("exp(x)",    "e 的 x 次幂", caretOffset: 4, selectLength: 1),
        ReferenceItem("pow(a, b)", "a 的 b 次幂", caretOffset: 4, selectLength: 1),
        ReferenceItem("sqrt(x)",   "平方根（x ≥ 0）", caretOffset: 5, selectLength: 1)
    ]

    private let numeric: [ReferenceItem] = [
        ReferenceItem("abs(x)",   "绝对值", caretOffset: 4, selectLength: 1),
        ReferenceItem("ceil(x)",  "向上取整", caretOffset: 5, selectLength: 1),
        ReferenceItem("floor(x)", "向下取整", caretOffset: 6, selectLength: 1),
        ReferenceItem("round(x)", "四舍五入（.5 向偶数）", caretOffset: 6, selectLength: 1)
    ]

    private func format(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%g", value)
        }
        return String(format: "%.4g", value)
    }
}

// MARK: - 参考项模型与可点击行

private struct ReferenceItem {
    let proto: String       // 界面展示
    let insert: String      // 点击插入的文本
    let caretOffset: Int?   // 插入后光标相对插入起点的偏移（nil = 插入文本末尾）
    let selectLength: Int   // 光标处选中的占位符长度（0 = 纯光标）
    let desc: String

    init(_ proto: String, _ desc: String,
         insert: String? = nil, caretOffset: Int? = nil, selectLength: Int = 0) {
        self.proto = proto
        self.desc = desc
        self.insert = insert ?? proto
        self.caretOffset = caretOffset
        self.selectLength = selectLength
    }
}

private struct ReferenceRow: View {
    let item: ReferenceItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.proto)
                    .font(.callout.monospaced())
                    .foregroundStyle(.blue)
                    .frame(width: 110, alignment: .leading)
                Text("—")
                    .foregroundStyle(.quaternary)
                Text(item.desc)
                    .font(.callout)
                    .foregroundStyle(hovering ? .primary : .secondary)
                Image(systemName: "plus.circle")
                    .foregroundStyle(.blue)
                    .imageScale(.small)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.blue.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .help("点击插入 \(item.insert)")
    }
}

// MARK: - 变量值标签（点击插入变量名）

private struct VariableChip: View {
    let name: String
    let value: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(name) = \(value)")
                .font(.caption.monospaced())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(hovering ? Color.accentColor.opacity(0.15)
                                            : Color.primary.opacity(0.04))
                )
                .overlay(
                    Capsule().strokeBorder(hovering ? Color.accentColor.opacity(0.4) : Color.clear,
                                           lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .help("插入变量 \(name)")
    }
}

// MARK: - 按键风格

struct KeyCapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed
                          ? Color.accentColor.opacity(0.30)
                          : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.15 : 0.08),
                                  lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - ════════════════════════════════════════════════════════════════════
//  第三部分：App 入口
//  ═══════════════════════════════════════════════════════════════════════════

@main
struct ExprCalcApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1080, height: 760)
    }
}


// MARK: - ════════════════════════════════════════════════════════════════════
//  第四部分：单元测试
//  ═══════════════════════════════════════════════════════════════════════════

#if canImport(XCTest)
import XCTest

final class ExprEvaluatorTests: XCTestCase {

    private func eval(_ expr: String, vars: [String: Double] = [:]) throws -> Double {
        try ExprEvaluator(variables: vars).evaluate(expr)
    }

    func testAddition()       throws { XCTAssertEqual(try eval("1 + 2"), 3) }
    func testSubtraction()    throws { XCTAssertEqual(try eval("5 - 3"), 2) }
    func testMultiplication() throws { XCTAssertEqual(try eval("6 * 7"), 42) }
    func testDivision()       throws { XCTAssertEqual(try eval("10 / 4"), 2.5) }

    func testOperatorPrecedence() throws {
        XCTAssertEqual(try eval("2 + 3 * 4"), 14)
        XCTAssertEqual(try eval("3 * 4 + 2"), 14)
        XCTAssertEqual(try eval("(2 + 3) * 4"), 20)
    }

    func testPowerRightAssociative() throws {
        XCTAssertEqual(try eval("2 ^ 3 ^ 2"), 512)
    }

    func testUnaryMinusVsPower() throws {
        XCTAssertEqual(try eval("-3 ^ 2"), -9)
        XCTAssertEqual(try eval("(-3) ^ 2"), 9)
    }

    func testSquareRootOfSum() throws {
        XCTAssertEqual(try eval("sqrt(3 ^ 2 + 4 ^ 2)"), 5)
    }

    func testVariable() throws {
        XCTAssertEqual(try eval("x + y", vars: ["x": 3, "y": 4]), 7)
        XCTAssertEqual(try eval("r * 2", vars: ["r": 5]), 10)
    }

    func testConstants() throws {
        XCTAssertEqual(try eval("pi"), Double.pi, accuracy: 1e-12)
        XCTAssertEqual(try eval("e"), M_E, accuracy: 1e-12)
        XCTAssertEqual(try eval("sin(pi / 2)"), 1, accuracy: 1e-12)
    }

    func testTrig() throws {
        XCTAssertEqual(try eval("sin(0)"), 0, accuracy: 1e-12)
        XCTAssertEqual(try eval("cos(0)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try eval("tan(0)"), 0, accuracy: 1e-12)
    }

    func testLog() throws {
        XCTAssertEqual(try eval("ln(e)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try eval("log(100)"), 2, accuracy: 1e-12)
        XCTAssertEqual(try eval("log(2, 8)"), 3, accuracy: 1e-12)
    }

    func testPowAndSqrt() throws {
        XCTAssertEqual(try eval("pow(2, 10)"), 1024)
        XCTAssertEqual(try eval("sqrt(16)"), 4)
        XCTAssertEqual(try eval("exp(0)"), 1, accuracy: 1e-12)
    }

    func testNumeric() throws {
        XCTAssertEqual(try eval("abs(-7)"), 7)
        XCTAssertEqual(try eval("ceil(3.2)"), 4)
        XCTAssertEqual(try eval("floor(3.8)"), 3)
        XCTAssertEqual(try eval("round(3.5)"), 4)
        XCTAssertEqual(try eval("round(2.5)"), 2)
    }

    func testDegRad() throws {
        XCTAssertEqual(try eval("deg(pi)"), 180, accuracy: 1e-12)
        XCTAssertEqual(try eval("rad(180)"), Double.pi, accuracy: 1e-12)
    }

    func testWhitespaceIgnored() throws {
        XCTAssertEqual(try eval(" 2 + 3 "), 5)
        XCTAssertEqual(try eval("sqrt( 16 )"), 4)
    }

    func testDecimal() throws {
        XCTAssertEqual(try eval("0.5 * 4"), 2)
        XCTAssertEqual(try eval("1.5 + 2.5"), 4)
    }

    func testCompound() throws {
        XCTAssertEqual(try eval("2 * (3 + 4) ^ 2"), 98)
        XCTAssertEqual(try eval("exp(ln(5))"), 5, accuracy: 1e-12)
        XCTAssertEqual(try eval("log(10, 1000)"), 3, accuracy: 1e-12)
    }

    func testDivisionByZero()  { XCTAssertThrowsError(try eval("1 / 0")) }
    func testUndefinedVariable(){ XCTAssertThrowsError(try eval("z + 1")) }
    func testMismatchedParen() { XCTAssertThrowsError(try eval("(1 + 2")); XCTAssertThrowsError(try eval("1 + 2)")) }
    func testUnknownFunction() { XCTAssertThrowsError(try eval("unknown(1)")) }
    func testWrongArgCount()   { XCTAssertThrowsError(try eval("sin(1, 2)")); XCTAssertThrowsError(try eval("pow(2)")) }
    func testTrailingGarbage() { XCTAssertThrowsError(try eval("1 + 2 x")) }
    func testEmpty()           { XCTAssertThrowsError(try eval("")) }
    func testInvalidNumber()   { XCTAssertThrowsError(try eval("3..14")) }
    func testNaNNoCrash()      { XCTAssertNoThrow(try eval("sqrt(-1)")) }
}
#endif


// MARK: - Preview
#Preview {
    ContentView()
}
