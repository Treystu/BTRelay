import XCTest
@testable import Relay

final class RelayTests: XCTestCase {
  func testAssembler() {
    let a = Assembler()
    let p = "hello".data(using: .utf8)!
    var c1 = p.subdata(in: 0..<3); c1.append(0)
    var c2 = p.subdata(in: 3..<5); c2.append(1)
    XCTAssertNil(a.append(peer: "aa", chunk: c1))
    let out = a.append(peer: "aa", chunk: c2)
    XCTAssertNotNil(out)
    XCTAssertEqual(String(data: out!, encoding: .utf8), "hello")
  }
  func testHmacVector() {
    let secret = Data(repeating: 0x0f, count: 32)
    let h = HmacUtil.hmacSha256Hex(secret: secret, v: 1, id: "id", ts: 1234, dest: "https://x", body: "YQ==")
    XCTAssertEqual(h, "e7b58b8f66e6b9f4d2d5da66a9d0e533f9a29a6f8a2f4f1dcd87a2d674b5e2a2")
  }
  func testThrottle() {
    let t = Throttle(rateBytesPerSec: 1000, burstBytes: 2000, monthlyCapBytes: 10_000)
    XCTAssertTrue(t.allow(size: 1000))
  }
}
