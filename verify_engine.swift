//
//  verify_engine.swift
//  ExprCalc
//
//  命令行引擎验证（无需完整 Xcode 工程）：
//    ./build.sh verify
//  或手动编译运行：
//    swiftc -O ExprCalc/ExprEvaluator.swift verify_engine.swift -o .build/verify && .build/verify
//
//  与 ExprCalcTests/ExprEvaluatorTests.swift 覆盖同一套核心断言，
//  针对 App 内使用的同一份引擎源码编译执行。
//

import Foundation

@main
struct VerifyEngine {

    static func main() {
        var passed = 0
        var failed = 0

        func check(_ expr: String, _ expected: Double, vars: [String: Double] = [:], accuracy: Double = 1e-9) {
            do {
                let value = try ExprEvaluator(variables: vars).evaluate(expr)
                if abs(value - expected) <= accuracy {
                    passed += 1
                } else {
                    failed += 1
                    print("❌ \(expr)  =  \(value)  （期望 \(expected)）")
                }
            } catch {
                failed += 1
                print("❌ \(expr)  抛出错误：\(error)")
            }
        }

        func checkThrows(_ expr: String) {
            do {
                _ = try ExprEvaluator().evaluate(expr)
                failed += 1
                print("❌ \(expr)  应当报错，但返回了结果")
            } catch {
                passed += 1
            }
        }

        // 四则运算与优先级
        check("1 + 2", 3)
        check("5 - 3", 2)
        check("6 * 7", 42)
        check("10 / 4", 2.5)
        check("2 + 3 * 4", 14)
        check("(2 + 3) * 4", 20)
        check("2 * (3 + 4) ^ 2", 98)

        // 幂与一元负号
        check("2 ^ 3 ^ 2", 512)          // 右结合
        check("-3 ^ 2", -9)              // 负号低于 ^
        check("(-3) ^ 2", 9)
        check("pow(2, 10)", 1024)

        // 变量与常量
        check("x + y", 7, vars: ["x": 3, "y": 4])
        check("r * 2", 10, vars: ["r": 5])
        check("pi", Double.pi, accuracy: 1e-12)
        check("e", M_E, accuracy: 1e-12)

        // 函数
        check("sin(pi / 2)", 1, accuracy: 1e-12)
        check("cos(0)", 1, accuracy: 1e-12)
        check("sqrt(3 ^ 2 + 4 ^ 2)", 5)
        check("sqrt(16)", 4)
        check("ln(e)", 1, accuracy: 1e-12)
        check("log(100)", 2, accuracy: 1e-12)
        check("log(2, 8)", 3, accuracy: 1e-12)
        check("exp(0)", 1, accuracy: 1e-12)
        check("abs(-7)", 7)
        check("ceil(3.2)", 4)
        check("floor(3.8)", 3)
        check("round(3.5)", 4)
        check("round(2.5)", 2)
        check("deg(pi)", 180, accuracy: 1e-12)
        check("rad(180)", Double.pi, accuracy: 1e-12)
        check("sqrt(x^2 + y^2)", 5, vars: ["x": 3, "y": 4])

        // 空白与小数
        check(" 2 + 3 ", 5)
        check("sqrt( 16 )", 4)
        check("0.5 * 4", 2)
        check("1.5 + 2.5", 4)

        // 错误处理
        checkThrows("1 / 0")
        checkThrows("z + 1")
        checkThrows("(1 + 2")
        checkThrows("1 + 2)")
        checkThrows("unknown(1)")
        checkThrows("sin(1, 2)")
        checkThrows("pow(2)")
        checkThrows("1 + 2 x")
        checkThrows("")
        checkThrows("3..14")

        print(failed == 0
              ? "✅ 引擎验证通过：\(passed) 项全部正确"
              : "⚠️  验证完成：\(passed) 通过 / \(failed) 失败")
        if failed > 0 { exit(1) }
    }
}
