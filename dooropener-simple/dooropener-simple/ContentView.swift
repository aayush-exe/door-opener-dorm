import SwiftUI
import CoreBluetooth

// MARK: - Nordic UART UUIDs (match your ESP32 sketch)
let nusServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
let nusRXUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Write
let nusTXUUID      = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Notify
// Name-based targeting
let targetDeviceNameDefault = ""


// Model for scanner table
struct ScannedPeripheral: Identifiable, Hashable {
  let id: UUID
  var peripheral: CBPeripheral
  var name: String
  var rssi: Int
  var lastSeen: Date
}

final class BLEManager: NSObject, ObservableObject {
  // Connected flow (unchanged)
  @Published var connected: CBPeripheral?
    @Published var lastRX: String = ""
  @Published var rxChar: CBCharacteristic?
  @Published var txChar: CBCharacteristic?
  @Published var logLines: [String] = []
    @Published var targetDeviceName: String = targetDeviceNameDefault
    @Published var autoConnectToNamed = true


  // Scanner / list of all devices currently seen
  @Published var scans: [ScannedPeripheral] = []
  @Published var isScanning = false

  private var central: CBCentralManager!
  private var indexByID: [UUID: Int] = [:]
  private var pruneTimer: Timer?

    init(targetDeviceName: String) {
        self.targetDeviceName = targetDeviceName
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        // (optionally hold off startScan until poweredOn; you already do that)
      }
    
  override init() {
    super.init()
    central = CBCentralManager(delegate: self, queue: .main)
    // Periodically prune entries not seen recently (15s)
    pruneTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      guard let self else { return }
      let cutoff = Date().addingTimeInterval(-15)
      var newIndex: [UUID:Int] = [:]
      self.scans.removeAll { $0.lastSeen < cutoff }
      for (i, s) in self.scans.enumerated() { newIndex[s.id] = i }
      self.indexByID = newIndex
    }
  }

  // MARK: Scanning
    func startScan() {
      guard central.state == .poweredOn else { return }
      log("Scanning (no filter)… target name = \"\(targetDeviceName)\"")
      scans.removeAll()
      indexByID.removeAll()
      isScanning = true
      central.scanForPeripherals(withServices: nil,   // <— broad scan
                                 options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }


  func stopScan() {
    isScanning = false
    central.stopScan()
  }

  func printCurrentDevices() {
    print("=== CURRENT BLE DEVICES (\(scans.count)) ===")
    for s in scans.sorted(by: { $0.rssi > $1.rssi }) {
      let age = Int(Date().timeIntervalSince(s.lastSeen))
      print("- \(s.name) [\(s.rssi) dBm], last seen \(age)s ago, id=\(s.id)")
    }
  }

  // MARK: Connection / GATT
  func connect(_ p: CBPeripheral) {
    stopScan()
    log("Connecting to \(p.name ?? "device")…")
    p.delegate = self
    central.connect(p, options: nil)
  }

  func disconnect() {
    guard let p = connected else { return }
    log("Disconnecting…")
    central.cancelPeripheralConnection(p)
  }

  func sendASCII(_ text: String) {
    guard let p = connected, let rx = rxChar else { return }
    guard let data = text.data(using: .utf8) else { return }
    // RX is WRITE (no writeWithoutResponse) → use withResponse
    p.writeValue(data, for: rx, type: .withResponse)
    log("→ \(text)")
  }

  private func log(_ s: String) {
    print(s)
    logLines.append(s)
  }
}

// MARK: - CoreBluetooth delegates
extension BLEManager: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn: startScan()
    case .poweredOff: log("Bluetooth is OFF")
    case .unauthorized: log("Bluetooth unauthorized")
    case .unsupported: log("Bluetooth unsupported on this device")
    case .resetting: log("Bluetooth resetting…")
    case .unknown: fallthrough @unknown default: log("Bluetooth state unknown")
    }
  }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
      let now = Date()
      let rssi = RSSI.intValue
      // Prefer ADV local name; fallback to CoreBluetooth's cached name; finally "Unknown"
      let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
      let name = localName ?? peripheral.name ?? "Unknown"

      // Upsert into scans table (so you still see everything)
      if let idx = indexByID[peripheral.identifier] {
        scans[idx].rssi = rssi
        scans[idx].lastSeen = now
        if scans[idx].name != name { scans[idx].name = name }
        objectWillChange.send()
      } else {
        let entry = ScannedPeripheral(id: peripheral.identifier,
                                      peripheral: peripheral,
                                      name: name,
                                      rssi: rssi,
                                      lastSeen: now)
        scans.append(entry)
        indexByID[peripheral.identifier] = scans.count - 1
      }

      // If name matches, optionally auto-connect
        if autoConnectToNamed && name.lowercased() == targetDeviceName.lowercased() && connected == nil {
        log("Match \(name). Auto-connecting…")
        stopScan()
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
      }
    }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    connected = peripheral
    log("Connected. Discovering services…")
    peripheral.discoverServices([nusServiceUUID])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    log("Connect failed: \(error?.localizedDescription ?? "unknown")")
    startScan()
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    log("Disconnected.")
    connected = nil
    rxChar = nil
    txChar = nil
    lastRX = ""
    startScan()
  }
}

extension BLEManager: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let e = error { log("Service discovery error: \(e.localizedDescription)"); return }
    guard let services = peripheral.services else { return }
    for s in services where s.uuid == nusServiceUUID {
      log("NUS found. Discovering characteristics…")
      peripheral.discoverCharacteristics([nusRXUUID, nusTXUUID], for: s)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let e = error { log("Char discovery error: \(e.localizedDescription)"); return }
    guard let chars = service.characteristics else { return }
    for c in chars {
      if c.uuid == nusRXUUID {
        rxChar = c
        log("RX characteristic ready (Write).")
      } else if c.uuid == nusTXUUID {
        txChar = c
        if c.properties.contains(.notify) {
          peripheral.setNotifyValue(true, for: c)
          log("Subscribed to TX notifications.")
        }
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let e = error { log("Notify state error: \(e.localizedDescription)") }
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    if let e = error { log("Write error: \(e.localizedDescription)") } else { log("✓ Write ACK") }
  }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
      if let e = error { log("Notify error: \(e.localizedDescription)"); return }
      guard let data = characteristic.value else { return }

      if let s = String(data: data, encoding: .utf8), !s.isEmpty {
        // Split on newlines, log each, and keep the last one as the latest message
        let lines = s.split(whereSeparator: \.isNewline).map(String.init)
        lines.forEach { line in log("← \(line)") }
        if let last = lines.last { lastRX = last }
      } else {
        // Fallback: non-UTF8 payload, show as bytes
        lastRX = (data as NSData).description
        log("← \(data as NSData)")
      }
    }

}

// MARK: - UI: reusable device list
struct DeviceListView: View {
  @ObservedObject var ble: BLEManager
  var connectAction: (CBPeripheral) -> Void

  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text(ble.isScanning ? "Scanning…" : "Scan stopped")
        Spacer()
        Button(ble.isScanning ? "Stop Scanning" : "Start Scanning") {
          ble.isScanning ? ble.stopScan() : ble.startScan()
        }
//        Button("Print to Console") { ble.printCurrentDevices() }
      }
      .font(.subheadline)

        List(
          ble.scans
            .filter { $0.name.lowercased() == ble.targetDeviceName.lowercased() } // ⬅️ only show matches
            .sorted(by: { $0.rssi > $1.rssi })
        ) { s in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(s.name).font(.body)
            Text(s.id.uuidString).font(.caption).foregroundColor(.secondary).lineLimit(1)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 2) {
            Text("\(s.rssi) dBm").font(.caption).monospaced()
            Text("\(Int(Date().timeIntervalSince(s.lastSeen)))s ago")
              .font(.caption2).foregroundColor(.secondary)
          }
          Button("Connect") { connectAction(s.peripheral) }
            .buttonStyle(.bordered)
        }
      }
    }
    .padding(.horizontal)
  }
}
private struct ConnectedPanel: View {
  @ObservedObject var ble: BLEManager
  let peripheralName: String
  @Binding var pin: String
  @Binding var autoAuthOnConnect: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
        
      Text("Connected: \(peripheralName)")
        .font(.headline)
    Text("Device Options")
      .font(.caption)
      .foregroundColor(.secondary)
      HStack {
        TextField("Enter PIN", text: $pin)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 140)
        Toggle("Auto AUTH on connect", isOn: $autoAuthOnConnect)
      }
        Text("Device Actions")
          .font(.caption)
          .foregroundColor(.secondary)
        Button {
          ble.sendASCII("OPEN")
        } label: {
          Text("OPEN")
            .frame(maxWidth: .infinity)     // fill the label
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)                 // (optional) bigger height/text
        .frame(maxWidth: .infinity)          // fill the container
        .padding(.vertical, 4)               // (optional) breathing room
        
      HStack {
        Button("AUTH")   { ble.sendASCII("AUTH \(pin)") }
        Button("STATUS") { ble.sendASCII("STATUS") }
        Button("PING")   { ble.sendASCII("PING") }
        Button("DISCONNECT")   { ble.disconnect() }
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity)
        
    // Last message box
//    if !ble.lastRX.isEmpty {
    if true {
      VStack(alignment: .leading, spacing: 4) {
        Text("Last message from device")
          .font(.caption)
          .foregroundColor(.secondary)

        TextEditor(text: .constant(ble.lastRX))
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 10, maxHeight: 40)
          .disabled(true) // read-only
          .scrollContentBackground(.hidden)
          .background(Color(.secondarySystemBackground))
          .cornerRadius(8)
      }
    }




    }
    // keep it tight so it feels like part of the list
    .padding(.vertical, 6)
    .onChange(of: (ble.rxChar != nil && ble.txChar != nil)) { oldReady, newReady in
      guard autoAuthOnConnect, newReady, !oldReady else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        ble.sendASCII("AUTH \(pin)")
      }
    }
  }
}
// MARK: - Main Screen
struct ContentView: View {
  @State private var custom = ""
    @AppStorage("pin") private var pin: String = ""
  @State private var autoAuthOnConnect = true
    @AppStorage("targetDeviceName") private var targetDeviceName: String = ""
    @StateObject private var ble: BLEManager

    init() {
      // Read the saved value immediately and inject it
      let saved = UserDefaults.standard.string(forKey: "targetDeviceName") ?? ""
      _ble = StateObject(wrappedValue: BLEManager(targetDeviceName: saved))
    }

    var body: some View {
      NavigationView {
        VStack(spacing: 12) {
          // Top controls
          HStack {
              TextField("Enter Target Device Name", text: $targetDeviceName)
              .textFieldStyle(.roundedBorder)
              .onChange(of: targetDeviceName) { _, newValue in
                  ble.targetDeviceName = newValue
                }
            Toggle("Auto-connect", isOn: $ble.autoConnectToNamed)
          }
          .padding(.horizontal)

          // Device list
          Text("Nearby Devices")
            .font(.headline)
          DeviceListView(ble: ble) { periph in ble.connect(periph) }

          // Connected view appears *after* the list, as its own section
          if let p = ble.connected {
            Divider()
            ConnectedPanel(
              ble: ble,
              peripheralName: p.name ?? "Unnamed",
              pin: $pin,
              autoAuthOnConnect: $autoAuthOnConnect
            )
            .padding()
          }
        }
        .navigationTitle("Auto Door Opener")
      }
    }

}
