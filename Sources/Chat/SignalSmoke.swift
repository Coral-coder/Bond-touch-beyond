import LibSignalClient

/// Link check for LibSignalClient: generating an identity key pair exercises the Swift
/// wrapper and the Rust core (libsignal_ffi). Replaced by the real chat crypto.
enum SignalSmoke {
    static func identityKeyLength() -> Int {
        IdentityKeyPair.generate().identityKey.serialize().count
    }
}
