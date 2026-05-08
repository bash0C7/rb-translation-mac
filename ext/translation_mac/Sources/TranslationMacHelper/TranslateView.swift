import SwiftUI
import Translation
// Apple's SE-0367 cross-import overlay that exposes `.translationTask`. The
// MacOSX26.2 SDK no longer auto-pulls it in via `import Translation` alone, so
// the explicit import is required to compile. It is public API and safe to ship.
import _Translation_SwiftUI

@available(macOS 15.0, *)
struct TranslateView: View {
    let operation: Operation
    let onComplete: (Int32, String?, String?) -> Void

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                let (from, to) = endpoints()
                configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: from),
                    target: Locale.Language(identifier: to)
                )
            }
            .translationTask(configuration) { session in
                await runTask(session: session)
            }
    }

    private func endpoints() -> (String, String) {
        switch operation {
        case .translate(let from, let to, _): return (from, to)
        case .prepare(let from, let to):       return (from, to)
        default: return ("", "")
        }
    }

    private func currentStatus() async -> LanguageAvailability.Status {
        let (from, to) = endpoints()
        return await LanguageAvailability().status(
            from: Locale.Language(identifier: from),
            to:   Locale.Language(identifier: to)
        )
    }

    private func runTask(session: TranslationSession) async {
        do {
            let status = await currentStatus()
            switch operation {
            case .translate(_, _, let text):
                switch status {
                case .unsupported: onComplete(3, nil, "unsupported language pair"); return
                case .supported:   onComplete(2, nil, "model not installed"); return
                case .installed:   break
                @unknown default:  onComplete(3, nil, "unknown availability"); return
                }
                let response = try await session.translate(text)
                onComplete(0, response.targetText, nil)
            case .prepare:
                if status == .unsupported {
                    onComplete(3, nil, "unsupported language pair")
                    return
                }
                try await session.prepareTranslation()
                onComplete(0, "installed", nil)
            default:
                onComplete(5, nil, "unexpected operation in UI task path")
            }
        } catch {
            onComplete(5, nil, "\(error)")
        }
    }
}
