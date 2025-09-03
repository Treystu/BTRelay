import Foundation
import CryptoKit
enum HmacUtil {
  static func hex(_ d: Data) -> String { d.map{ String(format:"%02x",$0) }.joined() }
  static func hmacSha256Hex(secret: Data, v: Int, id: String, ts: Int64, dest: String, body: String) -> String {
    let msg = "\(v)|\(id)|\(ts)|\(dest)|\(body)"
    let mac = HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: SymmetricKey(data: secret))
    return mac.map{ String(format:"%02x",$0) }.joined()
  }
}
