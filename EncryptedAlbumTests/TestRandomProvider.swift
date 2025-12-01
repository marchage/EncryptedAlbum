import Foundation
#if canImport(EncryptedAlbum)
@testable import EncryptedAlbum
#else
@testable import EncryptedAlbum_iOS
#endif

/// Test helper that returns deterministic, high-entropy-looking bytes for unit tests.
/// It produces a different byte pattern on each call so tests that expect different salts/values still work.
final class TestRandomProvider: RandomProvider {
    /// Internal 64-bit state (SplitMix64-style) to produce deterministic but high-entropy-looking bytes
    private var state: UInt64 = 0x0123456789ABCDEF

    private func nextUInt64() -> UInt64 {
        // SplitMix64 generator
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    func randomBytes(count: Int) async throws -> Data {
        var result = Data(capacity: count)
        while result.count < count {
            let n = nextUInt64()
            var value = n.littleEndian
            withUnsafeBytes(of: &value) { ptr in
                let bytes = ptr.bindMemory(to: UInt8.self)
                for b in bytes {
                    if result.count < count {
                        result.append(b)
                    } else {
                        break
                    }
                }
            }
        }
        return result
    }
}
