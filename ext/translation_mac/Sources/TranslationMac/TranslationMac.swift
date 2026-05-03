import Foundation
@preconcurrency import Translation

@available(macOS 15.0, *)
private let availability = LanguageAvailability()

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@available(macOS 15.0, *)
func translationMacSupportedLanguages() -> String {
    let semaphore = DispatchSemaphore(value: 0)
    let box = Box<[String]>([])
    Task {
        let supported = await availability.supportedLanguages
        box.value = supported.map { $0.maximalIdentifier }
        semaphore.signal()
    }
    semaphore.wait()
    return box.value.joined(separator: "\n")
}

@available(macOS 15.0, *)
func translationMacStatus(from: String, to: String) -> String {
    let semaphore = DispatchSemaphore(value: 0)
    let box = Box<String>("unsupported")
    Task {
        let src = Locale.Language(identifier: from)
        let dst = Locale.Language(identifier: to)
        let s = await availability.status(from: src, to: dst)
        switch s {
        case .installed:   box.value = "installed"
        case .supported:   box.value = "supported"
        case .unsupported: box.value = "unsupported"
        @unknown default:  box.value = "unsupported"
        }
        semaphore.signal()
    }
    semaphore.wait()
    return box.value
}
