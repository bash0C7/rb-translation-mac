import AppKit
import SwiftUI
import Translation

/// A request parsed from the helper's command-line arguments.
enum Operation {
    case translate(source: Locale.Language, target: Locale.Language, text: String)
    case prepare(source: Locale.Language, target: Locale.Language)
    case status(source: Locale.Language, target: Locale.Language)
    case languages

    /// The usage text written to standard error for unrecognized arguments.
    static let usage = """
        usage:
          TranslationMacHelper translate <from> <to> <text>
          TranslationMacHelper prepare <from> <to>
          TranslationMacHelper status <from> <to>
          TranslationMacHelper languages

        """

    /// Parses the arguments that follow the executable path.
    ///
    /// - Parameter arguments: The subcommand followed by its operands.
    /// - Returns: The operation, or `nil` when the subcommand is unknown or operands are missing.
    init?(arguments: [String]) {
        switch arguments.first {
        case "translate" where arguments.count >= 4:
            self = .translate(source: Locale.Language(identifier: arguments[1]), target: Locale.Language(identifier: arguments[2]), text: arguments[3])
        case "prepare" where arguments.count >= 3:
            self = .prepare(source: Locale.Language(identifier: arguments[1]), target: Locale.Language(identifier: arguments[2]))
        case "status" where arguments.count >= 3:
            self = .status(source: Locale.Language(identifier: arguments[1]), target: Locale.Language(identifier: arguments[2]))
        case "languages":
            self = .languages
        default:
            return nil
        }
    }
}

/// The helper's exit codes, which the Ruby side maps to result errors.
enum ExitCode: Int32 {
    case success = 0
    case modelNotInstalled = 2
    case unsupportedLanguagePair = 3
    case timeout = 4
    case crash = 5
}

/// Writes the result streams and terminates the helper.
///
/// - Parameters:
///   - code: The process exit code.
///   - output: Text written to standard output as is.
///   - error: Text written to standard error.
func finish(_ code: ExitCode, output: String? = nil, error: String? = nil) -> Never {
    if let output { FileHandle.standardOutput.write(Data(output.utf8)) }
    if let error { FileHandle.standardError.write(Data(error.utf8)) }
    exit(code.rawValue)
}

/// Runs one ``Operation`` inside an accessory `NSApplication`, whose main run loop services the Translation framework's async work.
@MainActor
enum HelperApp {
    /// The time limit for every operation before the helper exits with ``ExitCode/timeout``.
    static let timeout: DispatchTimeInterval = .seconds(30)

    /// Starts the operation and the timeout, then runs the application loop until ``finish(_:output:error:)`` exits.
    ///
    /// - Parameter operation: The request to run.
    static func run(_ operation: Operation) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { await perform(operation) }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            finish(.timeout, error: "timeout")
        }
        app.run()
    }

    nonisolated private static func perform(_ operation: Operation) async {
        let availability = LanguageAvailability()
        switch operation {
        case .languages:
            let languages = await availability.supportedLanguages
            finish(.success, output: languages.map(\.maximalIdentifier).joined(separator: "\n"))
        case .status(let source, let target):
            finish(.success, output: name(of: await availability.status(from: source, to: target)))
        case .translate(let source, let target, let text):
            switch await availability.status(from: source, to: target) {
            case .installed:
                do {
                    let response = try await TranslationSession(installedSource: source, target: target).translate(text)
                    finish(.success, output: response.targetText)
                } catch {
                    finish(.crash, error: "\(error)")
                }
            case .supported:
                finish(.modelNotInstalled, error: "model not installed")
            default:
                finish(.unsupportedLanguagePair, error: "unsupported language pair")
            }
        case .prepare(let source, let target):
            if await availability.status(from: source, to: target) == .unsupported {
                finish(.unsupportedLanguagePair, error: "unsupported language pair")
            }
            await present(source: source, target: target)
        }
    }

    nonisolated private static func name(of status: LanguageAvailability.Status) -> String {
        switch status {
        case .installed: "installed"
        case .supported: "supported"
        default: "unsupported"
        }
    }

    private static func present(source: Locale.Language, target: Locale.Language) {
        let window = NSWindow(
            contentRect: NSRect(x: -200, y: -200, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: PrepareView(source: source, target: target))
        window.makeKeyAndOrderFront(nil)
    }
}
