import Foundation
import Network
final class NetSender {
  private let q = MessageQueue()
  private let throttle: Throttle
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "net")
  init(throttle: Throttle){ self.throttle = throttle }
  func start(){
    monitor.pathUpdateHandler = { [weak self] path in
      guard path.status == .satisfied else { return }
      self?.drain()
    }
    monitor.start(queue: queue)
    drain()
  }
  private func drain(){
    while let url = q.next() {
      guard let data = try? Data(contentsOf: url) else { q.remove(url); continue }
      guard let fr = try? JSONDecoder().decode(Frame.self, from: data) else { q.remove(url); continue }
      guard throttle.allow(size: Int64(data.count)) else { return }
      let secret = Settings.load().secretBytes
      let calc = HmacUtil.hmacSha256Hex(secret: secret, v: fr.v, id: fr.id, ts: fr.ts, dest: fr.dest, body: fr.body)
      guard calc.caseInsensitiveCompare(fr.hmac) == .orderedSame else { q.remove(url); continue }
      var req = URLRequest(url: URL(string: fr.dest)!)
      req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
      req.httpBody = data
      let sem = DispatchSemaphore(value: 0)
      URLSession.shared.dataTask(with: req){ _, resp, _ in
        if let code = (resp as? HTTPURLResponse)?.statusCode, (200...299).contains(code) { self.q.remove(url) }
        sem.signal()
      }.resume()
      sem.wait()
    }
  }
}
