//
//  ExprEvaluatorTests.swift
//  ExprCalc
//
//  Created by foolpanda on 2026/10/1.
//

import Foundation
import XCTest
@testable import ExprCalc

@MainActor
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
