import CoreBluetooth
import Flutter
import Foundation

/// THE MESH RADIO — the iOS half of `lib/core/mesh/method_channel_ble_radio.dart`.
///
/// The Android half is `MeshBleRadio.kt`, and the two are deliberately the same
/// shape so that a phone of either kind relays for a phone of the other. Read the
/// header there for the design; what follows is only what differs on iOS.
///
/// ## Shape
///
/// Both roles at once. A `CBPeripheralManager` publishes one service holding one
/// writable, notifiable characteristic and advertises the service UUID; a
/// `CBCentralManager` scans for that UUID, connects, subscribes, and only then
/// reports the peer. Chunks go central→peripheral as writes and
/// peripheral→central as notifications.
///
/// ## The four requirements
///
///  1. **peerId is not an identity.** A random UUID per link. CoreBluetooth's own
///     `identifier` values are used only inside this file to find the link a
///     callback belongs to; they never cross the channel.
///  2. **The MTU actually negotiated.** iOS negotiates by itself and exposes the
///     result as `maximumWriteValueLength(for: .withoutResponse)` (central) and
///     `maximumUpdateValueLength` (peripheral), both ATT MTU − 3. A write larger
///     than that is refused here.
///  3. **No identity in the advertisement.** Only `CBAdvertisementDataServiceUUIDsKey`.
///     No local name, which iOS would otherwise fill with the device name.
///  4. **Disconnects reported promptly**, including when Bluetooth is switched
///     off, where iOS does not call the per-peripheral disconnect callbacks.
///
/// ## Background, honestly
///
/// With the `bluetooth-central` and `bluetooth-peripheral` background modes this
/// keeps relaying while the app is in the background, with iOS's limits: the
/// advertisement moves to the "overflow" area, which other iPhones can see and
/// Android generally cannot, and scanning slows. State restoration after the
/// system terminates the app is not implemented. Neither has been measured on a
/// handset; this file has not been run on one.
final class MeshBleRadio: NSObject, FlutterStreamHandler {
  static let methodChannelName = "com.operationrainbow.app/mesh_ble"
  static let eventChannelName = "com.operationrainbow.app/mesh_ble/events"

  /// Must equal `MESH_CHARACTERISTIC_UUID` in MeshBleRadio.kt.
  static let characteristicUuid = CBUUID(string: "6f726e62-6f77-4d65-7368-000000000002")

  private static let minMtu = 23
  private static let maxMtu = 517
  private static let maxOutboundLinks = 4
  private static let setupTimeout: TimeInterval = 15
  private static let writeTimeout: TimeInterval = 10
  private static let reconnectCooldown: TimeInterval = 30
  private static let scanRestartInterval: TimeInterval = 60

  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?

  private var central: CBCentralManager?
  private var peripheralManager: CBPeripheralManager?
  private var serviceUuid: CBUUID?
  private var characteristic: CBMutableCharacteristic?
  private var serviceAdded = false
  private var started = false
  private var pendingStart: FlutterResult?
  private var scanTimer: Timer?

  private final class OutboundLink {
    let peerId = UUID().uuidString
    let peripheral: CBPeripheral
    var characteristic: CBCharacteristic?
    var mtu = MeshBleRadio.minMtu
    var reported = false
    var pendingWrite: FlutterResult?
    var writeToken = 0

    init(peripheral: CBPeripheral) {
      self.peripheral = peripheral
    }
  }

  private final class InboundLink {
    let peerId = UUID().uuidString
    let central: CBCentral
    var mtu: Int

    init(central: CBCentral) {
      self.central = central
      mtu = MeshBleRadio.clampMtu(central.maximumUpdateValueLength + 3)
    }
  }

  private final class PendingNotify {
    let link: InboundLink
    let data: Data
    let result: FlutterResult

    init(link: InboundLink, data: Data, result: @escaping FlutterResult) {
      self.link = link
      self.data = data
      self.result = result
    }
  }

  /// Links this phone opened, keyed by CoreBluetooth's identifier (internal only).
  private var outbound: [UUID: OutboundLink] = [:]
  /// Links other phones opened to this one, keyed the same way.
  private var inbound: [UUID: InboundLink] = [:]
  private var cooldownUntil: [UUID: Date] = [:]
  private var notifyQueue: [PendingNotify] = []

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: MeshBleRadio.methodChannelName, binaryMessenger: messenger)
    events = FlutterEventChannel(name: MeshBleRadio.eventChannelName, binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    events.setStreamHandler(self)
  }

  private static func clampMtu(_ value: Int) -> Int {
    min(max(value, minMtu), maxMtu)
  }

  // MARK: Channel plumbing

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    sink = eventSink
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "start":
      start(serviceUuid: args?["serviceUuid"] as? String, result: result)
    case "stop":
      stopAll()
      result(nil)
    case "write":
      let bytes = (args?["bytes"] as? FlutterStandardTypedData)?.data
      write(peerId: args?["peerId"] as? String, data: bytes, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func emit(_ event: [String: Any]) {
    sink?(event)
  }

  private func emitPeer(_ peerId: String, connected: Bool, mtu: Int?) {
    var event: [String: Any] = ["event": "peer", "peerId": peerId, "connected": connected]
    if let mtu = mtu { event["mtu"] = mtu }
    emit(event)
  }

  // MARK: Start / stop

  private func start(serviceUuid text: String?, result: @escaping FlutterResult) {
    guard let text = text, UUID(uuidString: text) != nil else {
      result(FlutterError(code: "BAD_ARGS", message: "serviceUuid is not a UUID", details: nil))
      return
    }
    let uuid = CBUUID(string: text)
    if started && uuid == serviceUuid {
      result(nil)
      return
    }
    if started { stopAll() }

    switch CBManager.authorization {
    case .denied, .restricted:
      result(FlutterError(code: "PERMISSION_DENIED", message: "Bluetooth is not allowed for this app", details: nil))
      return
    default:
      break
    }

    serviceUuid = uuid
    started = true
    pendingStart = result
    // Creating the managers is what asks the person for Bluetooth access the
    // first time. The answer arrives as a state update, which resolves `start`.
    let quiet = [CBCentralManagerOptionShowPowerAlertKey: false]
    central = CBCentralManager(delegate: self, queue: nil, options: quiet)
    peripheralManager = CBPeripheralManager(
      delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
  }

  private func resolveStart(_ error: FlutterError?) {
    guard let pending = pendingStart else { return }
    pendingStart = nil
    pending(error)
  }

  private func stopAll() {
    resolveStart(FlutterError(code: "STOPPED", message: "stopped before Bluetooth was ready", details: nil))
    started = false
    dropAllLinks()
    scanTimer?.invalidate()
    scanTimer = nil
    if central?.state == .poweredOn { central?.stopScan() }
    if peripheralManager?.state == .poweredOn {
      peripheralManager?.stopAdvertising()
      peripheralManager?.removeAllServices()
    }
    central?.delegate = nil
    peripheralManager?.delegate = nil
    central = nil
    peripheralManager = nil
    characteristic = nil
    serviceAdded = false
    serviceUuid = nil
  }

  /// Ends every link and reports each one. Used by stop, and when Bluetooth goes
  /// off — iOS does not call the disconnect callbacks in that case.
  private func dropAllLinks() {
    for link in Array(outbound.values) { endOutbound(link, cooldown: false) }
    for link in Array(inbound.values) { endInbound(link) }
    let queued = notifyQueue
    notifyQueue.removeAll()
    for item in queued {
      item.result(FlutterError(code: "STOPPED", message: "the radio stopped", details: nil))
    }
  }

  // MARK: Central role

  private func startScanning() {
    guard started, let central = central, central.state == .poweredOn, let uuid = serviceUuid else { return }
    central.stopScan()
    central.scanForPeripherals(
      withServices: [uuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    if scanTimer == nil {
      // Without duplicates iOS reports each advertiser once per scan, so a phone
      // that left and came back would never be seen again. Restarting the scan
      // is how it is seen again.
      scanTimer = Timer.scheduledTimer(withTimeInterval: MeshBleRadio.scanRestartInterval, repeats: true) {
        [weak self] _ in
        self?.startScanning()
      }
    }
  }

  private func endOutbound(_ link: OutboundLink, cooldown: Bool) {
    guard outbound.removeValue(forKey: link.peripheral.identifier) != nil else { return }
    if let pending = link.pendingWrite {
      link.pendingWrite = nil
      pending(FlutterError(code: "DISCONNECTED", message: "the link closed", details: nil))
    }
    if cooldown {
      cooldownUntil[link.peripheral.identifier] = Date().addingTimeInterval(MeshBleRadio.reconnectCooldown)
    }
    link.peripheral.delegate = nil
    if let central = central, central.state == .poweredOn {
      central.cancelPeripheralConnection(link.peripheral)
    }
    if link.reported {
      link.reported = false
      emitPeer(link.peerId, connected: false, mtu: nil)
    }
  }

  private func link(for peripheral: CBPeripheral) -> OutboundLink? {
    outbound[peripheral.identifier]
  }

  // MARK: Peripheral role

  private func publishService() {
    guard started, !serviceAdded, let manager = peripheralManager, manager.state == .poweredOn,
      let uuid = serviceUuid
    else { return }
    let characteristic = CBMutableCharacteristic(
      type: MeshBleRadio.characteristicUuid,
      properties: [.write, .notify],
      value: nil,
      permissions: [.writeable])
    let service = CBMutableService(type: uuid, primary: true)
    service.characteristics = [characteristic]
    self.characteristic = characteristic
    serviceAdded = true
    manager.add(service)
  }

  private func endInbound(_ link: InboundLink) {
    guard inbound.removeValue(forKey: link.central.identifier) != nil else { return }
    let mine = notifyQueue.filter { $0.link === link }
    notifyQueue.removeAll { $0.link === link }
    for item in mine {
      item.result(FlutterError(code: "DISCONNECTED", message: "the link closed", details: nil))
    }
    emitPeer(link.peerId, connected: false, mtu: nil)
  }

  // MARK: Writing

  private func write(peerId: String?, data: Data?, result: @escaping FlutterResult) {
    guard started else {
      result(FlutterError(code: "STOPPED", message: "the radio is not running", details: nil))
      return
    }
    guard let peerId = peerId, !peerId.isEmpty, let data = data, !data.isEmpty else {
      result(FlutterError(code: "BAD_ARGS", message: "peerId and bytes are required", details: nil))
      return
    }

    if let link = outbound.values.first(where: { $0.peerId == peerId && $0.reported }) {
      writeOutbound(link, data: data, result: result)
      return
    }
    if let link = inbound.values.first(where: { $0.peerId == peerId }) {
      guard data.count <= link.mtu - 3 else {
        result(FlutterError(code: "TOO_LARGE", message: "\(data.count) bytes exceeds MTU \(link.mtu)", details: nil))
        return
      }
      let item = PendingNotify(link: link, data: data, result: result)
      notifyQueue.append(item)
      DispatchQueue.main.asyncAfter(deadline: .now() + MeshBleRadio.writeTimeout) { [weak self] in
        guard let self = self, let index = self.notifyQueue.firstIndex(where: { $0 === item }) else { return }
        self.notifyQueue.remove(at: index)
        item.result(FlutterError(code: "TIMEOUT", message: "the notification could not be queued", details: nil))
      }
      pumpNotifies()
      return
    }
    result(FlutterError(code: "NO_PEER", message: "no such link", details: nil))
  }

  private func writeOutbound(_ link: OutboundLink, data: Data, result: @escaping FlutterResult) {
    guard let characteristic = link.characteristic else {
      result(FlutterError(code: "NO_PEER", message: "link not ready", details: nil))
      return
    }
    guard link.pendingWrite == nil else {
      result(FlutterError(code: "BUSY", message: "a write is already in flight", details: nil))
      return
    }
    guard data.count <= link.mtu - 3 else {
      result(FlutterError(code: "TOO_LARGE", message: "\(data.count) bytes exceeds MTU \(link.mtu)", details: nil))
      return
    }
    link.pendingWrite = result
    link.writeToken += 1
    let token = link.writeToken
    link.peripheral.writeValue(data, for: characteristic, type: .withResponse)
    DispatchQueue.main.asyncAfter(deadline: .now() + MeshBleRadio.writeTimeout) { [weak link] in
      guard let link = link, link.writeToken == token, let pending = link.pendingWrite else { return }
      link.pendingWrite = nil
      pending(FlutterError(code: "TIMEOUT", message: "the write was not acknowledged", details: nil))
    }
  }

  /// Sends queued notifications until iOS's transmit queue is full; the rest
  /// wait for `peripheralManagerIsReady(toUpdateSubscribers:)`.
  private func pumpNotifies() {
    guard let manager = peripheralManager, let characteristic = characteristic else { return }
    while let next = notifyQueue.first {
      guard inbound[next.link.central.identifier] === next.link else {
        notifyQueue.removeFirst()
        next.result(FlutterError(code: "NO_PEER", message: "link closed before the write", details: nil))
        continue
      }
      let sent = manager.updateValue(next.data, for: characteristic, onSubscribedCentrals: [next.link.central])
      if !sent { return }
      notifyQueue.removeFirst()
      next.result(nil)
    }
  }
}

// MARK: - CBCentralManagerDelegate

extension MeshBleRadio: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      resolveStart(nil)
      startScanning()
    case .unauthorized:
      let error = FlutterError(code: "PERMISSION_DENIED", message: "Bluetooth is not allowed for this app", details: nil)
      if pendingStart != nil {
        resolveStart(error)
        stopAll()
      } else {
        dropAllLinks()
      }
    case .unsupported:
      resolveStart(FlutterError(code: "UNSUPPORTED", message: "this device has no Bluetooth LE", details: nil))
      stopAll()
    case .poweredOff:
      if pendingStart != nil {
        resolveStart(FlutterError(code: "BLUETOOTH_OFF", message: "Bluetooth is switched off", details: nil))
        stopAll()
      } else {
        // Running, and the person switched Bluetooth off. Keep the managers so
        // relaying resumes by itself when it comes back on.
        dropAllLinks()
      }
    default:
      break
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    guard started, outbound[peripheral.identifier] == nil,
      outbound.count < MeshBleRadio.maxOutboundLinks
    else { return }
    if let until = cooldownUntil[peripheral.identifier] {
      if Date() < until { return }
      cooldownUntil.removeValue(forKey: peripheral.identifier)
    }
    let link = OutboundLink(peripheral: peripheral)
    outbound[peripheral.identifier] = link
    peripheral.delegate = self
    central.connect(peripheral, options: nil)
    // iOS never times a connection out by itself.
    DispatchQueue.main.asyncAfter(deadline: .now() + MeshBleRadio.setupTimeout) { [weak self, weak link] in
      guard let self = self, let link = link, !link.reported,
        self.outbound[link.peripheral.identifier] === link
      else { return }
      self.endOutbound(link, cooldown: true)
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard let link = link(for: peripheral), let uuid = serviceUuid else {
      central.cancelPeripheralConnection(peripheral)
      return
    }
    link.peripheral.discoverServices([uuid])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    if let link = link(for: peripheral) { endOutbound(link, cooldown: true) }
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    if let link = link(for: peripheral) { endOutbound(link, cooldown: true) }
  }
}

// MARK: - CBPeripheralDelegate (this phone as a central)

extension MeshBleRadio: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let link = link(for: peripheral) else { return }
    guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceUuid }) else {
      endOutbound(link, cooldown: true)
      return
    }
    peripheral.discoverCharacteristics([MeshBleRadio.characteristicUuid], for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard let link = link(for: peripheral) else { return }
    guard error == nil,
      let characteristic = service.characteristics?.first(where: { $0.uuid == MeshBleRadio.characteristicUuid })
    else {
      endOutbound(link, cooldown: true)
      return
    }
    link.characteristic = characteristic
    peripheral.setNotifyValue(true, for: characteristic)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?
  ) {
    guard let link = link(for: peripheral), !link.reported else { return }
    guard error == nil, characteristic.isNotifying else {
      endOutbound(link, cooldown: true)
      return
    }
    // Connected, subscribed, MTU settled by iOS: only now is this a peer.
    link.mtu = MeshBleRadio.clampMtu(peripheral.maximumWriteValueLength(for: .withoutResponse) + 3)
    link.reported = true
    emitPeer(link.peerId, connected: true, mtu: link.mtu)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard error == nil, let link = link(for: peripheral), link.reported,
      characteristic.uuid == MeshBleRadio.characteristicUuid,
      let value = characteristic.value, !value.isEmpty
    else { return }
    emit(["event": "data", "peerId": link.peerId, "bytes": FlutterStandardTypedData(bytes: value)])
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard let link = link(for: peripheral), let pending = link.pendingWrite else { return }
    link.pendingWrite = nil
    if let error = error {
      pending(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
    } else {
      pending(nil)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
    if let link = link(for: peripheral), invalidatedServices.contains(where: { $0.uuid == serviceUuid }) {
      endOutbound(link, cooldown: true)
    }
  }
}

// MARK: - CBPeripheralManagerDelegate (this phone as a peripheral)

extension MeshBleRadio: CBPeripheralManagerDelegate {
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state == .poweredOn {
      publishService()
    } else {
      // Published services do not survive the radio going off.
      serviceAdded = false
      for link in Array(inbound.values) { endInbound(link) }
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    guard started, let uuid = serviceUuid else { return }
    if error != nil {
      // Central-only: this phone can still reach others.
      serviceAdded = false
      return
    }
    // Requirement 3: the service UUID and nothing else. No local name.
    peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [uuid]])
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic
  ) {
    guard started, characteristic.uuid == MeshBleRadio.characteristicUuid,
      inbound[central.identifier] == nil
    else { return }
    let link = InboundLink(central: central)
    inbound[central.identifier] = link
    emitPeer(link.peerId, connected: true, mtu: link.mtu)
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic
  ) {
    if let link = inbound[central.identifier] { endInbound(link) }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    guard let first = requests.first else { return }
    var outcome: CBATTError.Code = .success
    for request in requests {
      // Long writes (non-zero offsets) are refused: a chunk fits one packet, and
      // assembling a long write means buffering bytes a stranger chose.
      guard request.characteristic.uuid == MeshBleRadio.characteristicUuid else {
        outcome = .requestNotSupported
        continue
      }
      guard request.offset == 0 else {
        outcome = .invalidOffset
        continue
      }
      guard started, let link = inbound[request.central.identifier],
        let value = request.value, !value.isEmpty
      else { continue }
      emit(["event": "data", "peerId": link.peerId, "bytes": FlutterStandardTypedData(bytes: value)])
    }
    peripheral.respond(to: first, withResult: outcome)
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    pumpNotifies()
  }
}
