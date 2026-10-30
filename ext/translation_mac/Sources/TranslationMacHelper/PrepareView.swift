import SwiftUI
import Translation

/// An invisible view whose `translationTask` asks the system to download the models for a language pair.
///
/// `prepareTranslation()` presents the system download prompt when the pair is not installed, which needs a SwiftUI host.
struct PrepareView: View {
    let source: Locale.Language
    let target: Locale.Language

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(source: source, target: target) { @concurrent session in
                do {
                    try await session.prepareTranslation()
                    finish(.success, output: "installed")
                } catch {
                    finish(.crash, error: "\(error)")
                }
            }
    }
}
