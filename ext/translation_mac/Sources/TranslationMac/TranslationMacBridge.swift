import Foundation

@_cdecl("translation_mac_perform")
public func translation_mac_perform(_ input: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar> {
    let s = String(cString: input)
    let result = translation_mac_perform(s)
    return strdup(result)!
}

@_cdecl("translation_mac_free")
public func translation_mac_free(_ ptr: UnsafeMutablePointer<CChar>?) {
    free(ptr)
}
