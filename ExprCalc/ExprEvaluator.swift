//
//  ExprEvaluator.swift
//  ExprCalc
//
//  表达式求值引擎：词法分析 + 递归下降语法分析
//  运算符：+ - * / ^ ( ) ，幂右结合，一元负号低于幂
//  函数：sin cos tan deg rad ln log exp pow sqrt abs ceil floor round
//  常量：pi, e
//

import Foundation

// MARK: - 词法单元

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

// MARK: - 求值器

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
