import Foundation
import CommonCrypto

extension Data {
    func md5Hex() -> String {
        guard !isEmpty else { return "d41d8cd98f00b204e9800998ecf8427e" }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(self.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
