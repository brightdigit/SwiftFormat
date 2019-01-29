//
//  SwiftFormat.swift
//  SwiftFormat
//
//  Created by Nick Lockwood on 12/08/2016.
//  Copyright 2016 Nick Lockwood
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

import Foundation

/// The current SwiftFormat version
public let version = "0.38.0"

/// The standard SwiftFormat config file name
public let swiftFormatConfigurationFile = ".swiftformat"

/// The standard Swift version file name
public let swiftVersionFile = ".swift-version"

/// An enumeration of the types of error that may be thrown by SwiftFormat
public enum FormatError: Error, CustomStringConvertible, LocalizedError, CustomNSError {
    case reading(String)
    case writing(String)
    case parsing(String)
    case options(String)

    public var description: String {
        switch self {
        case let .reading(string),
             let .writing(string),
             let .parsing(string),
             let .options(string):
            return string
        }
    }

    public var localizedDescription: String {
        return "Error: \(description)."
    }

    public var errorUserInfo: [String: Any] {
        return [NSLocalizedDescriptionKey: localizedDescription]
    }
}

/// Legacy file enumeration function
@available(*, deprecated, message: "Use other enumerateFiles() method instead")
public func enumerateFiles(withInputURL inputURL: URL,
                           excluding excludedURLs: [URL] = [],
                           outputURL: URL? = nil,
                           options fileOptions: FileOptions = .default,
                           concurrent: Bool = true,
                           block: @escaping (URL, URL) throws -> () throws -> Void) -> [Error] {
    var fileOptions = fileOptions
    fileOptions.excludedGlobs += excludedURLs.map { Glob.path($0.path) }
    let options = Options(fileOptions: fileOptions)
    return enumerateFiles(
        withInputURL: inputURL,
        outputURL: outputURL,
        options: options,
        concurrent: concurrent
    ) { inputURL, outputURL, _ in
        try block(inputURL, outputURL)
    }
}

/// Callback for enumerateFiles() function
public typealias FileEnumerationHandler = (
    _ inputURL: URL,
    _ ouputURL: URL,
    _ options: Options
) throws -> () throws -> Void

/// Enumerate all swift files at the specified location and (optionally) calculate an output file URL for each.
/// Ignores the file if any of the excluded file URLs is a prefix of the input file URL.
///
/// Files are enumerated concurrently. For convenience, the enumeration block returns a completion block, which
/// will be executed synchronously on the calling thread once enumeration is complete.
///
/// Errors may be thrown by either the enumeration block or the completion block, and are gathered into an
/// array and returned after enumeration is complete, along with any errors generated by the function itself.
/// Throwing an error from inside either block does *not* terminate the enumeration.
public func enumerateFiles(withInputURL inputURL: URL,
                           outputURL: URL? = nil,
                           options baseOptions: Options = .default,
                           concurrent: Bool = true,
                           skipped: FileEnumerationHandler? = nil,
                           handler: @escaping FileEnumerationHandler) -> [Error] {
    let manager = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey]

    struct ResourceValues {
        let isRegularFile: Bool?
        let isDirectory: Bool?
        let isAliasFile: Bool?
        let isSymbolicLink: Bool?
    }

    func getResourceValues(for url: URL) throws -> ResourceValues {
        #if os(macOS)
            if let resourceValues = try? url.resourceValues(forKeys: Set(keys)) {
                return ResourceValues(
                    isRegularFile: resourceValues.isRegularFile,
                    isDirectory: resourceValues.isDirectory,
                    isAliasFile: resourceValues.isAliasFile,
                    isSymbolicLink: resourceValues.isSymbolicLink
                )
            }
            if manager.fileExists(atPath: url.path) {
                throw FormatError.reading("failed to read attributes for \(url.path)")
            }
            throw FormatError.options("file not found at \(url.path)")
        #else
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                return ResourceValues(
                    isRegularFile: !isDirectory.boolValue,
                    isDirectory: isDirectory.boolValue,
                    isAliasFile: false,
                    isSymbolicLink: false
                )
            }
            throw FormatError.options("file not found at \(url.path)")
        #endif
    }

    let resourceValues: ResourceValues
    do {
        resourceValues = try getResourceValues(for: inputURL)
    } catch {
        return [error]
    }
    let fileOptions = baseOptions.fileOptions ?? .default
    if !fileOptions.followSymlinks,
        (resourceValues.isAliasFile == true || resourceValues.isSymbolicLink == true) {
        return [FormatError.options("symbolic link or alias was skipped: \(inputURL.path)")]
    }
    if resourceValues.isDirectory == false,
        !fileOptions.supportedFileExtensions.contains(inputURL.pathExtension) {
        return [FormatError.options("unsupported file type: \(inputURL.path)")]
    }

    let group = DispatchGroup()
    var completionBlocks = [() throws -> Void]()
    let completionQueue = DispatchQueue(label: "swiftformat.enumeration")
    func onComplete(_ block: @escaping () throws -> Void) {
        completionQueue.async(group: group) {
            completionBlocks.append(block)
        }
    }

    let queue = concurrent ? DispatchQueue.global(qos: .userInitiated) : completionQueue

    func enumerate(inputURL: URL,
                   outputURL: URL?,
                   options: Options) {
        let inputURL = inputURL.standardizedFileURL
        let fileOptions = options.fileOptions ?? .default
        let resourceValues: ResourceValues
        do {
            resourceValues = try getResourceValues(for: inputURL)
        } catch {
            onComplete { throw error }
            return
        }
        let inputPath = inputURL.path
        func wasSkipped() -> Bool {
            for excluded in fileOptions.excludedGlobs {
                guard excluded.matches(inputPath) else {
                    continue
                }
                if let handler = skipped {
                    do {
                        onComplete(try handler(inputURL, outputURL ?? inputURL, options))
                    } catch {
                        onComplete { throw error }
                    }
                }
                return true
            }
            return false
        }
        if resourceValues.isRegularFile == true {
            if fileOptions.supportedFileExtensions.contains(inputURL.pathExtension) {
                if wasSkipped() {
                    return
                }
                do {
                    onComplete(try handler(inputURL, outputURL ?? inputURL, options))
                } catch {
                    onComplete { throw error }
                }
            }
        } else if resourceValues.isDirectory == true {
            if wasSkipped() {
                return
            }
            var options = options
            let configFile = inputURL.appendingPathComponent(swiftFormatConfigurationFile)
            if manager.fileExists(atPath: configFile.path) {
                do {
                    let data = try Data(contentsOf: configFile)
                    let args = try parseConfigFile(data)
                    try options.addArguments(args, in: inputURL.path)
                } catch {
                    onComplete { throw error }
                    return
                }
            }
            let versionFile = inputURL.appendingPathComponent(swiftVersionFile)
            if manager.fileExists(atPath: versionFile.path) {
                do {
                    let versionString = try String(contentsOf: versionFile, encoding: .utf8)
                    guard let version = Version(rawValue: versionString) else {
                        throw FormatError.options("malformed .swift-format file as \(versionFile.path)")
                    }
                    options.formatOptions?.swiftVersion = version
                } catch {
                    onComplete { throw error }
                    return
                }
            }
            let enumerationOptions: FileManager.DirectoryEnumerationOptions
            #if os(macOS)
                enumerationOptions = .skipsHiddenFiles
            #else
                enumerationOptions = []
            #endif
            guard let files = try? manager.contentsOfDirectory(
                at: inputURL, includingPropertiesForKeys: keys, options: enumerationOptions
            ) else {
                onComplete { throw FormatError.reading("failed to read contents of directory at \(inputURL.path)") }
                return
            }
            for url in files where !url.path.hasPrefix(".") {
                queue.async(group: group) {
                    let outputURL = outputURL.map {
                        URL(fileURLWithPath: $0.path + url.path[inputURL.path.endIndex ..< url.path.endIndex])
                    }
                    enumerate(inputURL: url, outputURL: outputURL, options: options)
                }
            }
        } else if fileOptions.followSymlinks,
            (resourceValues.isSymbolicLink == true || resourceValues.isAliasFile == true) {
            let resolvedURL = inputURL.resolvingSymlinksInPath()
            enumerate(inputURL: resolvedURL, outputURL: outputURL, options: options)
        }
    }

    queue.async(group: group) {
        if !manager.fileExists(atPath: inputURL.path) {
            onComplete { throw FormatError.options("file not found at \(inputURL.path)") }
            return
        }
        enumerate(inputURL: inputURL, outputURL: outputURL, options: baseOptions)
    }
    group.wait()

    var errors = [Error]()
    for block in completionBlocks {
        do {
            try block()
        } catch {
            errors.append(error)
        }
    }
    return errors
}

/// Get line/column offset for token
/// Note: line indexes start at 1, columns start at zero
public func offsetForToken(at index: Int, in tokens: [Token]) -> (line: Int, column: Int) {
    var line = 1, column = 0
    for token in tokens[0 ..< index] {
        if token.isLinebreak {
            line += 1
            column = 0
        } else {
            column += token.string.count
        }
    }
    return (line, column)
}

/// Process parsing errors
public func parsingError(for tokens: [Token], options: FormatOptions) -> FormatError? {
    if let index = tokens.index(where: {
        guard options.fragment || !$0.isError else { return true }
        guard !options.ignoreConflictMarkers, case let .operator(string, _) = $0 else { return false }
        return string.hasPrefix("<<<<<") || string.hasPrefix("=====") || string.hasPrefix(">>>>>")
    }) {
        let message: String
        switch tokens[index] {
        case .error(""):
            message = "unexpected end of file"
        case let .error(string):
            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message = "inconsistent whitespace in multi-line string literal"
            } else {
                message = "unexpected token \(string)"
            }
        case let .operator(string, _):
            message = "found conflict marker \(string)"
        default:
            preconditionFailure()
        }
        let (line, column) = offsetForToken(at: index, in: tokens)
        return .parsing("\(message) at \(line):\(column)")
    }
    return nil
}

/// Convert a token array back into a string
public func sourceCode(for tokens: [Token]) -> String {
    var output = ""
    for token in tokens { output += token.string }
    return output
}

/// Apply specified rules to a token array with optional callback
/// Useful for perfoming additional logic after each rule is applied
public func applyRules(_ rules: [FormatRule],
                       to originalTokens: [Token],
                       with options: FormatOptions,
                       callback: ((Int, [Token]) -> Void)? = nil) throws -> [Token] {
    var tokens = originalTokens

    // Parse
    if let error = parsingError(for: tokens, options: options) {
        throw error
    }

    // Recursively apply rules until no changes are detected
    var options = options
    for _ in 0 ..< 10 {
        let formatter = Formatter(tokens, options: options)
        for (i, rule) in rules.enumerated() {
            rule.apply(with: formatter)
            callback?(i, formatter.tokens)
        }
        if tokens == formatter.tokens {
            return tokens
        }
        tokens = formatter.tokens
        options.fileHeader = .ignore // Prevents infinite recursion
    }
    throw FormatError.writing("failed to terminate")
}

/// Format a pre-parsed token array
/// Returns the formatted token array, and the number of edits made
public func format(_ tokens: [Token],
                   rules: [FormatRule] = FormatRules.default,
                   options: FormatOptions = .default) throws -> [Token] {
    return try applyRules(rules, to: tokens, with: options)
}

/// Format code with specified rules and options
public func format(_ source: String,
                   rules: [FormatRule] = FormatRules.default,
                   options: FormatOptions = .default) throws -> String {
    return sourceCode(for: try format(tokenize(source), rules: rules, options: options))
}

// MARK: Path utilities

public func expandPath(_ path: String, in directory: String) -> URL {
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path)
    }
    if path.hasPrefix("~") {
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
    return URL(fileURLWithPath: directory).appendingPathComponent(path)
}

// MARK: Xcode 9.2 compatibility

#if !swift(>=4.1)

    extension Sequence {
        func compactMap<T>(_ transform: (Element) throws -> T?) rethrows -> [T] {
            return try flatMap { try transform($0).map { [$0] } ?? [] }
        }
    }

#endif
