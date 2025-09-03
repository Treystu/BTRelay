import Foundation
import CoreBluetooth

final class PeripheralManager: NSObject, CBPeripheralManagerDelegate {
  private var pm: CBPeripheralManager!
  private let serviceUUID = CBUUID(string:"5f1dd9f0-5c4a-4a0f-9b6d-27f1a5f6a9b1")
  private let msgInUUID   = CBUUID(string:"8b21f1b8-9b7f-4b17-9f3e-7a0e9b6e2a10")
  private let ackUUID     = CBUUID(string:"3e9c2d6a-1b1e-4f1c-8a62-0c4f7a9b12aa")
  private let assembler = Assembler()
  private let sender = NetSender(throttle: Throttle(rateBytesPerSec: Settings.load().rate, burstBytes: Settings.load().burst, monthlyCapBytes: Settings.load().cap))

  func start(){ pm = CBPeripheralManager(delegate: self, queue: nil) ; sender.start() }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    guard peripheral.state == .poweredOn else { return }
    let svc = CBMutableService(type: serviceUUID, primary: true)
    let msgIn = CBMutableCharacteristic(type: msgInUUID, properties: [.writeWithoutResponse], value: nil, permissions: [.writeable])
    let ack = CBMutableCharacteristic(type: ackUUID, properties: [.notify], value: nil, permissions: [.readable])
    svc.characteristics = [msgIn, ack]
    pm.add(svc)
    pm.startAdvertising([CBAdvertisementDataServiceUUIDsKey:[serviceUUID],
                         CBAdvertisementDataLocalNameKey: "Relay"])
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for r in requests where r.characteristic.uuid == msgInUUID {
      if let v = r.value, let frame = assembler.append(peer: r.central.identifier.uuidString, chunk: v) {
        if let fr = try? JSONDecoder().decode(Frame.self, from: frame) {
          let s = Settings.load().secretBytes
          let calc = HmacUtil.hmacSha256Hex(secret: s, v: fr.v, id: fr.id, ts: fr.ts, dest: fr.dest, body: fr.body)
          if calc.caseInsensitiveCompare(fr.hmac) == .orderedSame { MessageQueue().enqueue(frame) ; notify("ok") } else { notify("bad_hmac") }
        } else { notify("bad_json") }
      }
      pm.respond(to: r, withResult: .success)
    }
  }

  private func notify(_ text: String){
    if let ch = (pm.services?.first { $0.uuid == serviceUUID } as? CBMutableService)?
      .characteristics?.first(where: { $0.uuid == ackUUID }) as? CBMutableCharacteristic {
      ch.value = Data(text.utf8)
      pm.updateValue(ch.value!, for: ch, onSubscribedCentrals: nil)
    }
  }
}

final class Assembler {
  private var buffers = [String: Data]()
  func append(peer: String, chunk: Data) -> Data? {
    guard let last = chunk.last else { return nil }
    let data = chunk.dropLast()
    buffers[peer, default: Data()].append(data)
    if last == 0x01 {
      let out = buffers[peer]; buffers.removeValue(forKey: peer); return out
    }
    return nil
  }
}
