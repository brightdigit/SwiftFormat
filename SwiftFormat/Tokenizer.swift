//
//  Tokenizer.swift
//  SwiftFormat
//
//  Version 0.15
//
//  Created by Nick Lockwood on 11/08/2016.
//  Copyright 2016 Nick Lockwood
//
//  Distributed under the permissive zlib license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/SwiftFormat
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

import Foundation

// https://developer.apple.com/library/ios/documentation/Swift/Conceptual/Swift_Programming_Language/LexicalStructure.html

public enum Token: Equatable {
    case number(String)
    case linebreak(String)
    case startOfScope(String)
    case endOfScope(String)
    case symbol(String)
    case stringBody(String)
    case identifier(String)
    case whitespace(String)
    case commentBody(String)
    case error(String)

    public var string: String {
        switch self {
        case .number(let string),
             .linebreak(let string),
             .startOfScope(let string),
             .endOfScope(let string),
             .symbol(let string),
             .stringBody(let string),
             .identifier(let string),
             .whitespace(let string),
             .commentBody(let string),
             .error(let string):
            return string
        }
    }

    public var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    public var isEndOfScope: Bool {
        if case .endOfScope = self {
            return true
        }
        return false
    }

    public var isIdentifier: Bool {
        if case .identifier = self {
            return true
        }
        return false
    }

    public var isWhitespace: Bool {
        if case .whitespace = self {
            return true
        }
        return false
    }

    public var isLinebreak: Bool {
        if case .linebreak = self {
            return true
        }
        return false
    }

    public var isWhitespaceOrLinebreak: Bool {
        switch self {
        case .linebreak, .whitespace:
            return true
        default:
            return false
        }
    }

    public var isWhitespaceOrComment: Bool {
        switch self {
        case .whitespace,
             .commentBody,
             .startOfScope("//"),
             .startOfScope("/*"),
             .endOfScope("*/"):
            return true
        default:
            return false
        }
    }

    public var isWhitespaceOrCommentOrLinebreak: Bool {
        switch self {
        case .linebreak,
             .whitespace,
             .commentBody,
             .startOfScope("//"),
             .startOfScope("/*"),
             .endOfScope("*/"):
            return true
        default:
            return false
        }
    }

    public func closesScopeForToken(_ token: Token) -> Bool {
        switch token {
        case .startOfScope("("):
            return self == .endOfScope(")")
        case .startOfScope("["):
            return self == .endOfScope("]")
        case .startOfScope("{"), .startOfScope(":"):
            return [.endOfScope("}"), .endOfScope("case"), .endOfScope("default")].contains(self)
        case .startOfScope("/*"):
            return self == .endOfScope("*/")
        case .startOfScope("#if"):
            return self == .endOfScope("#endif")
        case .startOfScope("\""):
            return self == .endOfScope("\"")
        case .startOfScope("<"):
            return string.hasPrefix(">")
        case .startOfScope("//"):
            return isLinebreak
        case .endOfScope("case"), .endOfScope("default"):
            return self == .symbol(":")
        default:
            return false
        }
    }

    public static func ==(lhs: Token, rhs: Token) -> Bool {
        switch lhs {
        case .number(let string):
            if case .number(string) = rhs {
                return true
            }
        case .linebreak(let string):
            if case .linebreak(string) = rhs {
                return true
            }
        case .startOfScope(let string):
            if case .startOfScope(string) = rhs {
                return true
            }
        case .endOfScope(let string):
            if case .endOfScope(string) = rhs {
                return true
            }
        case .symbol(let string):
            if case .symbol(string) = rhs {
                return true
            }
        case .identifier(let string):
            if case .identifier(string) = rhs {
                return true
            }
        case .stringBody(let string):
            if case .stringBody(string) = rhs {
                return true
            }
        case .commentBody(let string):
            if case .commentBody(string) = rhs {
                return true
            }
        case .whitespace(let string):
            if case .whitespace(string) = rhs {
                return true
            }
        case .error(let string):
            if case .error(string) = rhs {
                return true
            }
        }
        return false
    }
}

extension Character {

    var unicodeValue: UInt32 {
        return String(self).unicodeScalars.first?.value ?? 0
    }

    var isDigit: Bool { return isdigit(Int32(unicodeValue)) > 0 }
    var isHexDigit: Bool { return isxdigit(Int32(unicodeValue)) > 0 }
    var isWhitespace: Bool { return self == " " || self == "\t" || unicodeValue == 0x0b }
    var isLinebreak: Bool { return self == "\r" || self == "\n" || self == "\r\n" }
}

private extension String.CharacterView {

    mutating func scanCharacters(_ matching: (Character) -> Bool) -> String? {
        var index = endIndex
        for (i, c) in enumerated() {
            if !matching(c) {
                index = self.index(startIndex, offsetBy: i)
                break
            }
        }
        if index > startIndex {
            let string = String(prefix(upTo: index))
            self = suffix(from: index)
            return string
        }
        return nil
    }

    mutating func scanCharacters(head: (Character) -> Bool, tail: (Character) -> Bool) -> String? {
        if let head = scanCharacter(head) {
            if let tail = scanCharacters(tail) {
                return head + tail
            }
            return head
        }
        return nil
    }

    mutating func scanCharacter(_ matching: (Character) -> Bool = { _ in true }) -> String? {
        if let c = first, matching(c) {
            self = dropFirst()
            return String(c)
        }
        return nil
    }

    mutating func scanCharacter(_ character: Character) -> Bool {
        return scanCharacter({ $0 == character }) != nil
    }
}

private extension String.CharacterView {

    mutating func parseWhitespace() -> Token? {
        return scanCharacters({ $0.isWhitespace }).map { .whitespace($0) }
    }

    mutating func parseLineBreak() -> Token? {
        return scanCharacter({ $0.isLinebreak }).map { .linebreak($0) }
    }

    mutating func parsePunctuation() -> Token? {
        return scanCharacter({ ":;,".characters.contains($0) }).map { .symbol($0) }
    }

    mutating func parseStartOfScope() -> Token? {
        return scanCharacter({ "([{\"".characters.contains($0) }).map { .startOfScope($0) }
    }

    mutating func parseEndOfScope() -> Token? {
        return scanCharacter({ "}])".characters.contains($0) }).map { .endOfScope($0) }
    }

    mutating func parseOperator() -> Token? {

        func isHead(_ c: Character) -> Bool {
            if "./=­-+!*%<>&|^~?".characters.contains(c) {
                return true
            }
            switch c.unicodeValue {
            case 0x00A1 ... 0x00A7,
                 0x00A9, 0x00AB, 0x00AC, 0x00AE,
                 0x00B0 ... 0x00B1,
                 0x00B6, 0x00BB, 0x00BF, 0x00D7, 0x00F7,
                 0x2016 ... 0x2017,
                 0x2020 ... 0x2027,
                 0x2030 ... 0x203E,
                 0x2041 ... 0x2053,
                 0x2055 ... 0x205E,
                 0x2190 ... 0x23FF,
                 0x2500 ... 0x2775,
                 0x2794 ... 0x2BFF,
                 0x2E00 ... 0x2E7F,
                 0x3001 ... 0x3003,
                 0x3008 ... 0x3030:
                return true
            default:
                return false
            }
        }

        func isTail(_ c: Character) -> Bool {
            if isHead(c) {
                return true
            }
            switch c.unicodeValue {
            case 0x0300 ... 0x036F,
                 0x1DC0 ... 0x1DFF,
                 0x20D0 ... 0x20FF,
                 0xFE00 ... 0xFE0F,
                 0xFE20 ... 0xFE2F,
                 0xE0100 ... 0xE01EF:
                return true
            default:
                return false
            }
        }

        if var tail = scanCharacter(isHead) {
            var head = ""
            // Tail may only contain dot if head does
            let headWasDot = (tail == ".")
            while let c = scanCharacter({ isTail($0) && (headWasDot || $0 != ".") }) {
                if tail == "/" {
                    if c == "*" {
                        if head == "" {
                            return .startOfScope("/*")
                        }
                        // Can't return two tokens, so put /* back to be parsed next time
                        self = "/*".characters + self
                        return .symbol(head)
                    } else if c == "/" {
                        if head == "" {
                            return .startOfScope("//")
                        }
                        // Can't return two tokens, so put // back to be parsed next time
                        self = "//".characters + self
                        return .symbol(head)
                    }
                }
                head += tail
                tail = c
            }
            let op = head + tail
            return op == "<" ? .startOfScope(op) : .symbol(op)
        }
        return nil
    }

    mutating func parseIdentifier() -> Token? {

        func isHead(_ c: Character) -> Bool {
            switch c.unicodeValue {
            case 0x41 ... 0x5A, // A-Z
                 0x61 ... 0x7A, // a-z
                 0x5F, 0x24, // _ and $
                 0x00A8, 0x00AA, 0x00AD, 0x00AF,
                 0x00B2 ... 0x00B5,
                 0x00B7 ... 0x00BA,
                 0x00BC ... 0x00BE,
                 0x00C0 ... 0x00D6,
                 0x00D8 ... 0x00F6,
                 0x00F8 ... 0x00FF,
                 0x0100 ... 0x02FF,
                 0x0370 ... 0x167F,
                 0x1681 ... 0x180D,
                 0x180F ... 0x1DBF,
                 0x1E00 ... 0x1FFF,
                 0x200B ... 0x200D,
                 0x202A ... 0x202E,
                 0x203F ... 0x2040,
                 0x2054,
                 0x2060 ... 0x206F,
                 0x2070 ... 0x20CF,
                 0x2100 ... 0x218F,
                 0x2460 ... 0x24FF,
                 0x2776 ... 0x2793,
                 0x2C00 ... 0x2DFF,
                 0x2E80 ... 0x2FFF,
                 0x3004 ... 0x3007,
                 0x3021 ... 0x302F,
                 0x3031 ... 0x303F,
                 0x3040 ... 0xD7FF,
                 0xF900 ... 0xFD3D,
                 0xFD40 ... 0xFDCF,
                 0xFDF0 ... 0xFE1F,
                 0xFE30 ... 0xFE44,
                 0xFE47 ... 0xFFFD,
                 0x10000 ... 0x1FFFD,
                 0x20000 ... 0x2FFFD,
                 0x30000 ... 0x3FFFD,
                 0x40000 ... 0x4FFFD,
                 0x50000 ... 0x5FFFD,
                 0x60000 ... 0x6FFFD,
                 0x70000 ... 0x7FFFD,
                 0x80000 ... 0x8FFFD,
                 0x90000 ... 0x9FFFD,
                 0xA0000 ... 0xAFFFD,
                 0xB0000 ... 0xBFFFD,
                 0xC0000 ... 0xCFFFD,
                 0xD0000 ... 0xDFFFD,
                 0xE0000 ... 0xEFFFD:
                return true
            default:
                return false
            }
        }

        func isTail(_ c: Character) -> Bool {
            switch c.unicodeValue {
            case 0x30 ... 0x39, // 0-9
                 0x0300 ... 0x036F,
                 0x1DC0 ... 0x1DFF,
                 0x20D0 ... 0x20FF,
                 0xFE20 ... 0xFE2F:
                return true
            default:
                return isHead(c)
            }
        }

        func scanIdentifier() -> String? {
            return scanCharacters(head: { isHead($0) || "@#".characters.contains($0) }, tail: isTail)
        }

        let start = self
        if scanCharacter("`") {
            if let identifier = scanIdentifier() {
                if scanCharacter("`") {
                    return .identifier("`" + identifier + "`")
                }
            }
            self = start
        } else if let identifier = scanIdentifier() {
            if identifier == "#if" {
                return .startOfScope(identifier)
            }
            if identifier == "#endif" {
                return .endOfScope(identifier)
            }
            return .identifier(identifier)
        }
        return nil
    }

    mutating func parseNumber() -> Token? {

        func scanNumber(_ head: @escaping (Character) -> Bool) -> String? {
            return scanCharacters(head: head, tail: { head($0) || $0 == "_" })
        }

        func scanInteger() -> String? {
            return scanNumber({ $0.isDigit })
        }

        var number = ""
        if scanCharacter("0") {
            number = "0"
            if scanCharacter("x") {
                number += "x"
                if let hex = scanNumber({ $0.isHexDigit }) {
                    number += hex
                    if scanCharacter("p"), let power = scanInteger() {
                        number += "p" + power
                    }
                    return .number(number)
                }
                return .error(number + String(self))
            } else if scanCharacter("b") {
                number += "b"
                if let bin = scanNumber({ "01".characters.contains($0) }) {
                    return .number(number + bin)
                }
                return .error(number + String(self))
            } else if scanCharacter("o") {
                number += "o"
                if let octal = scanNumber({ ("0" ... "7").contains($0) }) {
                    return .number(number + octal)
                }
                return .error(number + String(self))
            } else if let tail = scanCharacters({ $0.isDigit || $0 == "_" }) {
                number += tail
            }
        } else if let integer = scanInteger() {
            number += integer
        }
        if !number.isEmpty {
            let endOfInt = self
            if scanCharacter(".") {
                if let fraction = scanInteger() {
                    number += "." + fraction
                } else {
                    self = endOfInt
                }
            }
            let endOfFloat = self
            if let e = scanCharacter({ "eE".characters.contains($0) }) {
                let sign = scanCharacter({ "-+".characters.contains($0) }) ?? ""
                if let exponent = scanInteger() {
                    number += e + sign + exponent
                } else {
                    self = endOfFloat
                }
            }
            return .number(number)
        }
        return nil
    }

    mutating func parseToken() -> Token? {
        // Have to split into groups for Swift to be able to process this
        if let token = parseWhitespace() ??
            parseLineBreak() ??
            parseNumber() ??
            parseIdentifier() {
            return token
        }
        if let token = parseOperator() ??
            parsePunctuation() ??
            parseStartOfScope() ??
            parseEndOfScope() {
            return token
        }
        if count > 0 {
            return .error(String(self))
        }
        return nil
    }
}

public func tokenize(_ source: String) -> [Token] {
    var scopeIndexStack: [Int] = []
    var tokens: [Token] = []
    var characters = source.characters
    var lastNonWhitespaceIndex: Int?
    var closedGenericScopeIndexes: [Int] = []
    var nestedSwitches = 0

    func processStringBody() {
        var string = ""
        var escaped = false
        while let c = characters.scanCharacter() {
            switch c {
            case "\\":
                escaped = !escaped
            case "\"":
                if !escaped {
                    if string != "" {
                        tokens.append(.stringBody(string))
                    }
                    tokens.append(.endOfScope("\""))
                    scopeIndexStack.removeLast()
                    return
                }
                escaped = false
            case "(":
                if escaped {
                    if string != "" {
                        tokens.append(.stringBody(string))
                    }
                    scopeIndexStack.append(tokens.count)
                    tokens.append(.startOfScope("("))
                    return
                }
                escaped = false
            default:
                escaped = false
            }
            string += c
        }
        if string != "" {
            tokens.append(.stringBody(string))
        }
    }

    var comment = ""
    var whitespace = ""

    func flushCommentBodyTokens() {
        if comment != "" {
            tokens.append(.commentBody(comment))
            comment = ""
        }
        if whitespace != "" {
            tokens.append(.whitespace(whitespace))
            whitespace = ""
        }
    }

    func processCommentBody() {
        while let c = characters.scanCharacter() {
            switch c {
            case "/":
                if characters.scanCharacter("*") {
                    flushCommentBodyTokens()
                    scopeIndexStack.append(tokens.count)
                    tokens.append(.startOfScope("/*"))
                    continue
                }
            case "*":
                if characters.scanCharacter("/") {
                    flushCommentBodyTokens()
                    tokens.append(.endOfScope("*/"))
                    scopeIndexStack.removeLast()
                    if scopeIndexStack.last == nil || tokens[scopeIndexStack.last!] != .startOfScope("/*") {
                        return
                    }
                    continue
                }
            default:
                if c.characters.first?.isLinebreak == true {
                    flushCommentBodyTokens()
                    tokens.append(.linebreak(c))
                    continue
                }
                if c.characters.first?.isWhitespace == true {
                    whitespace += c
                    continue
                }
            }
            if whitespace != "" {
                if comment == "" {
                    tokens.append(.whitespace(whitespace))
                } else {
                    comment += whitespace
                }
                whitespace = ""
            }
            comment += c
        }
        // We shouldn't actually get here, unless code is malformed
        flushCommentBodyTokens()
    }

    func processSingleLineCommentBody() {
        while let c = characters.scanCharacter({ !$0.isLinebreak }) {
            if c.characters.first?.isWhitespace == true {
                whitespace += c
                continue
            }
            if whitespace != "" {
                if comment == "" {
                    tokens.append(.whitespace(whitespace))
                } else {
                    comment += whitespace
                }
                whitespace = ""
            }
            comment += c
        }
        flushCommentBodyTokens()
    }

    func processToken() {
        let token = tokens.last!
        if !token.isWhitespace {
            switch token {
            case .identifier(let string):
                // Track switch/case statements
                let previousToken = lastNonWhitespaceIndex.map({ tokens[$0] })
                if previousToken == .symbol(".") {
                    break
                }
                switch string {
                case "switch":
                    nestedSwitches += 1
                case "default":
                    if nestedSwitches > 0 {
                        tokens[tokens.count - 1] = .endOfScope(string)
                        processToken()
                        return
                    }
                case "case":
                    if let previousToken = previousToken {
                        if case .identifier(let string) = previousToken,
                            ["if", "guard", "while", "for"].contains(string) {
                            break
                        } else if previousToken == .symbol(",") {
                            break
                        }
                    }
                    if nestedSwitches > 0 {
                        tokens[tokens.count - 1] = .endOfScope(string)
                        processToken()
                        return
                    }
                default:
                    break
                }
            case .symbol(let string):
                // Fix up optional indicator misidentified as operator
                if string.characters.count > 1 &&
                    (string.hasPrefix("?") || string.hasPrefix("!")) &&
                    tokens.count > 1 && !tokens[tokens.count - 2].isWhitespace {
                    tokens[tokens.count - 1] = .symbol(String(string.characters.first!))
                    let string = String(string.characters.dropFirst())
                    tokens.append(string == "<" ? .startOfScope(string) : .symbol(string))
                    processToken()
                    return
                }
            default:
                break
            }
            // Fix up misidentified generic that is actually a pair of operators
            if let lastNonWhitespaceIndex = lastNonWhitespaceIndex {
                let lastToken = tokens[lastNonWhitespaceIndex]
                if case .endOfScope(">") = lastToken {
                    let wasOperator: Bool
                    switch token {
                    case .identifier(let string):
                        wasOperator = !["in", "is", "as", "where", "else"].contains(string)
                    case .symbol(let string):
                        wasOperator = !["=", "->", ">", ",", ":", ";", "?", "!", "."].contains(string)
                    case .number, .startOfScope("\""):
                        wasOperator = true
                    default:
                        wasOperator = false
                    }
                    if wasOperator {
                        tokens[closedGenericScopeIndexes.last!] = .symbol("<")
                        closedGenericScopeIndexes.removeLast()
                        if case .symbol(let string) = token, lastNonWhitespaceIndex == tokens.count - 2 {
                            // Need to stitch the operator back together
                            tokens[lastNonWhitespaceIndex] = .symbol(">" + string)
                            tokens.removeLast()
                        } else {
                            tokens[lastNonWhitespaceIndex] = .symbol(">")
                        }
                        // TODO: this is horrible - need to take a better approach
                        var previousIndex = lastNonWhitespaceIndex - 1
                        var previousToken = tokens[previousIndex]
                        while previousToken == .endOfScope(">") {
                            tokens[closedGenericScopeIndexes.last!] = .symbol("<")
                            closedGenericScopeIndexes.removeLast()
                            if case .symbol(let string) = tokens[previousIndex + 1] {
                                tokens[previousIndex] = .symbol(">" + string)
                                tokens.remove(at: previousIndex + 1)
                                previousIndex -= 1
                                previousToken = tokens[previousIndex]
                            } else {
                                assertionFailure()
                            }
                        }
                        processToken()
                        return
                    }
                }
            }
            lastNonWhitespaceIndex = tokens.count - 1
        }
        if let scopeIndex = scopeIndexStack.last {
            let scope = tokens[scopeIndex]
            if token.closesScopeForToken(scope) {
                scopeIndexStack.removeLast()
                switch token {
                case .symbol(":"):
                    tokens[tokens.count - 1] = .startOfScope(":")
                    processToken()
                case .endOfScope("case"), .endOfScope("default"):
                    scopeIndexStack.append(tokens.count - 1)
                    processToken()
                case .endOfScope("}"):
                    if scope == .startOfScope(":") {
                        nestedSwitches -= 1
                    }
                case .endOfScope(")"):
                    if scopeIndexStack.last.map({ tokens[$0] }) == .startOfScope("\"") {
                        processStringBody()
                    }
                case .symbol(let string) where string.hasPrefix(">"):
                    closedGenericScopeIndexes.append(scopeIndex)
                    tokens[tokens.count - 1] = .endOfScope(">")
                    if string.characters.count > 1 {
                        // Need to split the token
                        let suffix = String(string.characters.dropFirst())
                        tokens.append(.symbol(suffix))
                        processToken()
                    }
                default:
                    break
                }
                return
            } else if scope == .startOfScope("<") {
                // We think it's a generic at this point, but could be wrong
                switch token {
                case .symbol(let string):
                    switch string {
                    case ".", ",", ":", "==", "?", "!":
                        break
                    case _ where string.hasPrefix("?>") || string.hasPrefix("!>"):
                        // Need to split token
                        tokens[tokens.count - 1] = .symbol(String(string.characters.first!))
                        let suffix = String(string.characters.dropFirst())
                        tokens.append(.symbol(suffix))
                        processToken()
                        return
                    default:
                        // Not a generic scope
                        tokens[scopeIndex] = .symbol("<")
                        scopeIndexStack.removeLast()
                        processToken()
                        return
                    }
                case .endOfScope:
                    // If we encountered a scope token that wasn't a < or >
                    // then the opening < must have been an operator after all
                    tokens[scopeIndex] = .symbol("<")
                    scopeIndexStack.removeLast()
                    processToken()
                    return
                default:
                    break
                }
            }
        }
        switch token {
        case .startOfScope(let string):
            scopeIndexStack.append(tokens.count - 1)
            switch string {
            case "\"":
                processStringBody()
            case "/*":
                processCommentBody()
            case "//":
                processSingleLineCommentBody()
            default:
                break
            }
        case .endOfScope("case"), .endOfScope("default"):
            break
        case .endOfScope(let string):
            // Previous scope wasn't closed correctly
            tokens[tokens.count - 1] = .error(string)
            return
        default:
            break
        }
    }

    while let token = characters.parseToken() {
        tokens.append(token)
        if case .error = token {
            return tokens
        }
        processToken()
    }

    if let scopeIndex = scopeIndexStack.last {
        switch tokens[scopeIndex] {
        case .startOfScope("<"):
            // If we encountered an end-of-file while a generic scope was
            // still open, the opening < must have been an operator
            tokens[scopeIndex] = .symbol("<")
            scopeIndexStack.removeLast()
        case .startOfScope("//"):
            break
        default:
            if tokens.last?.isError == false {
                // File ended with scope still open
                tokens.append(.error(""))
            }
        }
    }

    return tokens
}
