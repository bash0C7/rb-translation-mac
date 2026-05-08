import AppKit
import SwiftUI
import Translation

enum Operation {
    case translate(from: String, to: String, text: String)
    case prepare(from: String, to: String)
    case status(from: String, to: String)
    case supportedLanguages
}

@available(macOS 15.0, *)
final class HelperApp {
    func run(operation: Operation) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        switch operation {
        case .translate, .prepare:
            runUITask(operation: operation)
        case .status(let from, let to):
            runAvailabilityStatus(from: from, to: to)
        case .supportedLanguages:
            runSupportedLanguages()
        }

        // Global timeout: 30 s — applies to all four operations.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            FileHandle.standardError.write(Data("timeout".utf8))
            exit(4)
        }

        app.run()
    }

    // translate / prepare path: hosts SwiftUI .translationTask via TranslateView
    // because TranslationSession requires a SwiftUI environment.
    private func runUITask(operation: Operation) {
        let window = NSWindow(
            contentRect: NSRect(x: -200, y: -200, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        let view = TranslateView(operation: operation, onComplete: { exitCode, output, errorMessage in
            DispatchQueue.main.async {
                if let output = output { print(output) }
                if let msg = errorMessage {
                    FileHandle.standardError.write(Data(msg.utf8))
                }
                exit(exitCode)
            }
        })
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
    }

    // status path: LanguageAvailability is callable directly without a
    // TranslationSession; NSApp's main run loop services the async continuation.
    private func runAvailabilityStatus(from: String, to: String) {
        Task {
            let s = await LanguageAvailability().status(
                from: Locale.Language(identifier: from),
                to:   Locale.Language(identifier: to)
            )
            let str: String
            switch s {
            case .installed:   str = "installed"
            case .supported:   str = "supported"
            case .unsupported: str = "unsupported"
            @unknown default:  str = "unsupported"
            }
            DispatchQueue.main.async {
                print(str)
                exit(0)
            }
        }
    }

    // languages path: same direct-Task pattern.
    private func runSupportedLanguages() {
        Task {
            let langs = await LanguageAvailability().supportedLanguages
            let lines = langs.map { $0.maximalIdentifier }.joined(separator: "\n")
            DispatchQueue.main.async {
                print(lines)
                exit(0)
            }
        }
    }
}
