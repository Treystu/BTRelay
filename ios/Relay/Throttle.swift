import Foundation
final class Throttle {
  private let rate: Int64
  private let burst: Int64
  private let cap: Int64
  private var tokens: Int64
  private var last: TimeInterval
  private var monthUsed: Int64
  init(rateBytesPerSec: Int64, burstBytes: Int64, monthlyCapBytes: Int64){
    self.rate = rateBytesPerSec; self.burst = burstBytes; self.cap = monthlyCapBytes
    self.tokens = burstBytes; self.last = Date().timeIntervalSince1970
    self.monthUsed = UserDefaults.standard.object(forKey:"mon") as? Int64 ?? 0
  }
  func allow(size: Int64) -> Bool {
    let now = Date().timeIntervalSince1970
    let refill = Int64((now - last) * Double(rate))
    tokens = min(burst, tokens + max(0,refill))
    last = now
    if monthUsed + size > cap { return false }
    if tokens < size { return false }
    tokens -= size; monthUsed += size
    UserDefaults.standard.setValue(monthUsed, forKey:"mon")
    return true
  }
}
