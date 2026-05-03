import AppKit
import SwiftUI

enum Operation {
    case translate(from: String, to: String, text: String)
    case prepare(from: String, to: String)
}

@available(macOS 15.0, *)
final class HelperApp {
    func run(operation: Operation) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Off-screen 1x1 borderless window. PoC verified (2026-05-02):
        // - SwiftUI .translationTask fires under NSHostingView in this configuration.
        // - Language model download sheets attach to this window AND macOS promotes
        //   the sheet to the foreground so the user sees it. No visible window required.
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

        // Timeout: 30 s
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            FileHandle.standardError.write(Data("timeout".utf8))
            exit(4)
        }

        app.run()
    }
}
