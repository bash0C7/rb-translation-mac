import SwiftUI
import Translation
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
        }
    }

    private func runTask(session: TranslationSession) async {
        do {
            switch operation {
            case .translate(_, _, let text):
                let availability = LanguageAvailability()
                let (from, to) = endpoints()
                let status = await availability.status(
                    from: Locale.Language(identifier: from),
                    to:   Locale.Language(identifier: to)
                )
                switch status {
                case .unsupported: onComplete(3, nil, "unsupported language pair"); return
                case .supported:   onComplete(2, nil, "model not installed"); return
                case .installed:   break
                @unknown default:  onComplete(3, nil, "unknown availability"); return
                }
                let response = try await session.translate(text)
                onComplete(0, response.targetText, nil)
            case .prepare:
                try await session.prepareTranslation()
                onComplete(0, "installed", nil)
            }
        } catch {
            onComplete(5, nil, "\(error)")
        }
    }
}
