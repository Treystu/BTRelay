import Foundation

struct Settings {
  var secretHex: String
  var rate: Int64
  var burst: Int64
  var cap: Int64
  static func load() -> Settings {
    let d = UserDefaults.standard
    return Settings(
      secretHex: d.string(forKey: "secret") ?? String(repeating: "0", count: 64),
      rate: d.object(forKey: "rate") as? Int64 ?? 10_000,
      burst: d.object(forKey: "burst") as? Int64 ?? 200_000,
      cap: d.object(forKey: "cap") as? Int64 ?? 500*1024*1024
    )
  }
  func save() {
    let d = UserDefaults.standard
    d.set(secretHex, forKey: "secret"); d.set(rate, forKey: "rate"); d.set(burst, forKey: "burst"); d.set(cap, forKey: "cap")
  }
  var secretBytes: Data { Settings.hexToData(secretHex) }
  static func hexToData(_ s: String) -> Data {
    precondition(s.count % 2 == 0)
    var bytes = Data(capacity: s.count/2)
    var idx = s.startIndex
    while idx < s.endIndex {
      let b = s[idx...s.index(idx, offsetBy: 1)]
      idx = s.index(idx, offsetBy: 2)
      bytes.append(UInt8(b, radix: 16)!)
    }
    return bytes
  }
}
