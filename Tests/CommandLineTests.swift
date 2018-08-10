//
//  CommandLineTests.swift
//  SwiftFormat
//
//  Created by Nick Lockwood on 10/01/2017.
//  Copyright 2017 Nick Lockwood
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/SwiftFormat
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

@testable import SwiftFormat
import XCTest

private let sourceDirectory = URL(fileURLWithPath: #file)
    .deletingLastPathComponent().deletingLastPathComponent()

private let readme: String = {
    let readmeURL = sourceDirectory.appendingPathComponent("README.md")
    return try! String(contentsOf: readmeURL, encoding: .utf8)
}()

class CommandLineTests: XCTestCase {
    // MARK: pipe

    func testPipe() {
        CLI.print = { message, _ in
            XCTAssertEqual(message, "func foo() {\n    bar()\n}\n")
        }
        var readCount = 0
        CLI.readLine = {
            readCount += 1
            switch readCount {
            case 1:
                return "func foo()\n"
            case 2:
                return "{\n"
            case 3:
                return "bar()\n"
            case 4:
                return "}"
            default:
                return nil
            }
        }
        _ = processArguments([""], in: "")
    }

    // MARK: help

    func testHelpLineLength() {
        CLI.print = { message, _ in
            message.components(separatedBy: "\n").forEach { line in
                XCTAssertLessThanOrEqual(line.count, 80, line)
            }
        }
        printHelp()
    }

    func testHelpOptionsImplemented() {
        CLI.print = { message, _ in
            if message.hasPrefix("--") {
                let name = String(message["--".endIndex ..< message.endIndex]).components(separatedBy: " ")[0]
                XCTAssertTrue(commandLineArguments.contains(name), name)
            }
        }
        printHelp()
    }

    func testHelpOptionsDocumented() {
        var arguments = Set(commandLineArguments)
        deprecatedArguments.forEach { arguments.remove($0) }
        CLI.print = { allHelpMessage, _ in
            allHelpMessage
                .components(separatedBy: "\n")
                .forEach { message in
                    if message.hasPrefix("--") {
                        let name = String(message["--".endIndex ..< message.endIndex]).components(separatedBy: " ")[0]
                        arguments.remove(name)
                    }
                }
        }
        printHelp()
        XCTAssert(arguments.isEmpty, "\(arguments.joined(separator: ","))")
    }

    // MARK: documentation

    func testAllRulesInReadme() {
        for ruleName in FormatRules.byName.keys {
            XCTAssertTrue(readme.contains("***\(ruleName)*** - "), ruleName)
        }
    }

    func testNoInvalidRulesInReadme() {
        let ruleNames = Set(FormatRules.byName.keys)
        var range = readme.startIndex ..< readme.endIndex
        while let match = readme.range(of: "\\*[a-zA-Z]+\\* - ", options: .regularExpression, range: range, locale: nil) {
            let lower = readme.index(after: match.lowerBound)
            let upper = readme.index(match.upperBound, offsetBy: -4)
            let ruleName: String = String(readme[lower ..< upper])
            XCTAssertTrue(ruleNames.contains(ruleName), ruleName)
            range = match.upperBound ..< range.upperBound
        }
    }

    func testAllOptionsInReadme() {
        var arguments = Set(formattingArguments)
        deprecatedArguments.forEach { arguments.remove($0) }
        for argument in arguments {
            XCTAssertTrue(readme.contains("`--\(argument)`"), argument)
        }
    }

    func testNoInvalidOptionsInReadme() {
        let arguments = Set(commandLineArguments)
        var range = readme.startIndex ..< readme.endIndex
        while let match = readme.range(of: "`--[a-zA-Z]+`", options: .regularExpression, range: range, locale: nil) {
            let lower = readme.index(match.lowerBound, offsetBy: 3)
            let upper = readme.index(before: match.upperBound)
            let argument: String = String(readme[lower ..< upper])
            XCTAssertTrue(arguments.contains(argument), argument)
            range = match.upperBound ..< range.upperBound
        }
    }

    // MARK: cache

    func testHashIsFasterThanFormatting() throws {
        let sourceFile = URL(fileURLWithPath: #file)
        let source = try String(contentsOf: sourceFile, encoding: .utf8)
        let hash = computeHash(source + ";")

        let hashTime = timeEvent { _ = computeHash(source) == hash }
        let formatTime = try timeEvent { _ = try format(source) }
        XCTAssertLessThan(hashTime, formatTime)
    }

    func testCacheHit() throws {
        let input = "let foo = bar"
        XCTAssertEqual(computeHash(input), computeHash(input))
    }

    func testCacheMiss() throws {
        let input = "let foo = bar"
        let output = "let foo = bar\n"
        XCTAssertNotEqual(computeHash(input), computeHash(output))
    }

    func testCachePotentialFalsePositive() throws {
        let input = "let foo = bar;"
        let output = "let foo = bar\n"
        XCTAssertNotEqual(computeHash(input), computeHash(output))
    }

    func testCachePotentialFalsePositive2() throws {
        let input = """
        import Foo
        import Bar

        """
        let output = """
        import Bar
        import Foo

        """
        XCTAssertNotEqual(computeHash(input), computeHash(output))
    }

    // MARK: end-to-end tests

    func testFormatting() {
        CLI.print = { _, _ in }
        #if swift(>=4.1.5)
            let args = "."
        #else
            let args = ". --disable redundantSelf" // redundantSelf crashes Xcode 9.4 in debug mode
        #endif

        XCTAssertEqual(CLI.run(in: sourceDirectory.path, with: args), .ok)
    }

    func testRulesNotMarkedAsDisabled() {
        CLI.print = { message, _ in
            XCTAssert(message.contains("trailingClosures") || !message.contains("(disabled)"))
        }
        XCTAssertEqual(CLI.run(in: sourceDirectory.path, with: "--rules"), .ok)
    }
}
