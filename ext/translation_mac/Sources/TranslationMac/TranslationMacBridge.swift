import Foundation

@c
public func translation_mac_supported_languages() -> UnsafeMutablePointer<CChar> {
    if #available(macOS 15.0, *) {
        return strdup(translationMacSupportedLanguages())!
    } else {
        return strdup("")!
    }
}

@c
public func translation_mac_status(
    _ from: UnsafePointer<CChar>,
    _ to: UnsafePointer<CChar>
) -> UnsafeMutablePointer<CChar> {
    if #available(macOS 15.0, *) {
        let f = String(cString: from)
        let t = String(cString: to)
        return strdup(translationMacStatus(from: f, to: t))!
    } else {
        return strdup("unsupported")!
    }
}

@c
public func translation_mac_free(_ ptr: UnsafeMutablePointer<CChar>?) {
    free(ptr)
}
