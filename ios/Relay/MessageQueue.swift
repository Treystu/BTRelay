import Foundation
final class MessageQueue {
  private let dir: URL
  init(){
    dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("queue", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  func enqueue(_ data: Data){
    let url = dir.appendingPathComponent(UUID().uuidString + ".msg")
    try? data.write(to: url)
  }
  func next() -> URL? {
    (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []))?
      .sorted{ ($0.contentModDate ?? Date()) < ($1.contentModDate ?? Date()) }
      .first
  }
  func remove(_ url: URL){ try? FileManager.default.removeItem(at: url) }
}
private extension URL { var contentModDate: Date? { (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate } }
