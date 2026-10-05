package com.RainbowEwer.RainbowEwer

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.UUID

/**
 * THE MESH RADIO — the Android half of `lib/core/mesh/method_channel_ble_radio.dart`.
 *
 * Everything above this file (sealing, chunking, relaying, the gossip schedule)
 * is Dart and is tested in CI. This file does only what the contract there
 * asks: find phones running the app, keep one link to each, move opaque chunks
 * across those links, and say when a link appears, changes MTU, or goes.
 *
 * ## Shape
 *
 * Every phone is BOTH roles at once, because a mesh has no servers:
 *
 *  * **Peripheral.** A GATT server with one service ([serviceUuid]) holding one
 *    characteristic ([MESH_CHARACTERISTIC_UUID]) that is writable and notifiable,
 *    advertised with the service UUID and nothing else.
 *  * **Central.** A scanner filtered on that service UUID, which connects to what
 *    it finds, raises the MTU, subscribes to the characteristic, and only then
 *    reports the peer.
 *
 * A chunk travels central→peripheral as a characteristic WRITE, and
 * peripheral→central as a NOTIFICATION. So each link is bidirectional, and
 * which way round it was opened makes no difference to the Dart side.
 *
 * Two phones that both find each other open two links. That is accepted rather
 * than prevented: telling them apart would need an identity in the
 * advertisement, which is exactly what requirement 3 forbids, and the relay
 * above deduplicates by envelope id anyway.
 *
 * ## The four requirements, and where each is met
 *
 *  1. **peerId is not an identity.** It is a random UUID minted per LINK, never
 *     derived from the device address. The address is used here only to open a
 *     connection and to stop reconnecting to the same advertiser in a tight
 *     loop; it never crosses the channel.
 *  2. **Report the MTU actually negotiated.** 23 until `onMtuChanged` says
 *     otherwise, and 23 if the request fails. A write larger than the link's
 *     MTU - 3 is refused here rather than handed to a stack that might
 *     truncate it.
 *  3. **Advertise no identity.** `setIncludeDeviceName(false)`, no TX power, no
 *     manufacturer or service data. The service UUID is the only thing in it.
 *  4. **Report disconnects promptly.** Every path that ends a link — remote
 *     disconnect, failed setup, timeout, unsubscribe, stop() — goes through one
 *     function that emits `connected: false` if the peer had been reported.
 *
 * ## Threading
 *
 * Binder callbacks arrive on arbitrary threads. Each one posts straight to the
 * main looper and all state is touched only there, which is also the thread the
 * Flutter event sink requires.
 *
 * ## What is NOT verified
 *
 * Written against the platform documentation and compiled, but not yet run on
 * a handset. Discovery, MTU negotiation across vendors, background behaviour and
 * battery cost are field questions, listed in docs/OFFLINE_CHANNELS_DESIGN.md.
 */
@SuppressLint("MissingPermission") // Every entry point is gated by hasPermissions().
class MeshBleRadio(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "com.operationrainbow.app/mesh_ble"
        const val EVENT_CHANNEL = "com.operationrainbow.app/mesh_ble/events"

        /**
         * The one characteristic inside the mesh service. Fixed, and identical in
         * the iOS half: the contract only carries the service UUID, and the two
         * platforms have to agree on this one without being told.
         */
        val MESH_CHARACTERISTIC_UUID: UUID =
            UUID.fromString("6f726e62-6f77-4d65-7368-000000000002")

        /** The standard Client Characteristic Configuration descriptor. */
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val TAG = "MeshBleRadio"
        private const val MIN_MTU = 23
        private const val REQUESTED_MTU = 517

        /** Outbound links held at once. Android stacks manage about seven in total. */
        private const val MAX_CENTRAL_LINKS = 4

        /** A link must be usable within this, or it is abandoned. */
        private const val SETUP_TIMEOUT_MS = 15_000L

        /** A write or notification that has not completed by now has failed. */
        private const val WRITE_TIMEOUT_MS = 10_000L

        /** Do not reconnect to the same advertiser sooner than this after a link ends. */
        private const val RECONNECT_COOLDOWN_MS = 30_000L

        /**
         * How often the radio checks on itself. Android quietly downgrades a scan
         * that has run for ~30 minutes, and a scan does not survive Bluetooth
         * being switched off and on, so both are re-armed from here.
         */
        private const val WATCHDOG_MS = 60_000L
        private const val SCAN_RESTART_EVERY_TICKS = 5
    }

    private val appContext: Context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var events: EventChannel.EventSink? = null

    private var started = false
    private var serviceUuid: UUID? = null
    private var server: BluetoothGattServer? = null
    private var serverCharacteristic: BluetoothGattCharacteristic? = null
    private var advertising = false
    private var scanning = false
    private var bluetoothWasOff = false
    private var watchdogTicks = 0

    /** Links this phone opened, by peerId. */
    private val outbound = HashMap<String, OutboundLink>()

    /** Links other phones opened to this one, by device address (internal only). */
    private val inbound = HashMap<String, InboundLink>()

    /** Addresses with a link in progress or open, so one advertiser gets one link. */
    private val busyAddresses = HashSet<String>()

    /** When each address may be tried again. */
    private val cooldownUntil = HashMap<String, Long>()

    /**
     * Notifications go one at a time across the whole server: Android refuses a
     * second while the first is in flight, and on API 33+ says so with BUSY.
     */
    private val notifyQueue = ArrayDeque<PendingNotify>()
    private var notifyInFlight: PendingNotify? = null

    private class OutboundLink(
        val peerId: String,
        val address: String,
        val gatt: BluetoothGatt,
    ) {
        var mtu = MIN_MTU
        var characteristic: BluetoothGattCharacteristic? = null
        var reported = false
        var pendingWrite: MethodChannel.Result? = null
        var writeTimeout: Runnable? = null
        var setupTimeout: Runnable? = null
    }

    private class InboundLink(val peerId: String, val device: BluetoothDevice) {
        var mtu = MIN_MTU
        var subscribed = false
    }

    private class PendingNotify(
        val link: InboundLink,
        val bytes: ByteArray,
        val result: MethodChannel.Result,
    ) {
        var timeout: Runnable? = null
    }

    init {
        methods.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    /** Called when the engine goes away. */
    fun dispose() {
        stopAll()
        methods.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ── Channel plumbing ────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call.argument<String>("serviceUuid"), result)
            "stop" -> {
                stopAll()
                result.success(null)
            }
            "write" -> write(call.argument<String>("peerId"), call.argument<ByteArray>("bytes"), result)
            else -> result.notImplemented()
        }
    }

    private fun emit(event: Map<String, Any?>) {
        events?.success(event)
    }

    private fun emitPeer(peerId: String, connected: Boolean, mtu: Int?) {
        emit(mapOf("event" to "peer", "peerId" to peerId, "connected" to connected, "mtu" to mtu))
    }

    // ── Start / stop ────────────────────────────────────────────────────────

    private fun adapter(): BluetoothAdapter? =
        (appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun hasPermissions(): Boolean {
        val needed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            )
        } else {
            // Before Android 12 a BLE scan returns nothing without location.
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return needed.all {
            appContext.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun start(uuidText: String?, result: MethodChannel.Result) {
        val uuid = try {
            UUID.fromString(uuidText ?: "")
        } catch (e: IllegalArgumentException) {
            result.error("BAD_ARGS", "serviceUuid is not a UUID", null)
            return
        }
        if (started && uuid == serviceUuid) {
            result.success(null)
            return
        }
        if (started) stopAll()

        val adapter = adapter()
        if (adapter == null || !appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            result.error("UNSUPPORTED", "this device has no Bluetooth LE", null)
            return
        }
        if (!hasPermissions()) {
            result.error("PERMISSION_DENIED", "Bluetooth permissions are not granted", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BLUETOOTH_OFF", "Bluetooth is switched off", null)
            return
        }

        serviceUuid = uuid
        started = true
        bluetoothWasOff = false
        watchdogTicks = 0
        bringUp()
        main.postDelayed(watchdog, WATCHDOG_MS)
        result.success(null)
    }

    /** Opens the server (advertising follows once its service is added) and scans. */
    private fun bringUp() {
        openServer()
        startScan()
    }

    private fun stopAll() {
        main.removeCallbacks(watchdog)
        started = false
        tearDown()
        serviceUuid = null
    }

    /** Releases every radio resource and ends every link, reporting each one. */
    private fun tearDown() {
        stopScan()
        stopAdvertising()

        for (link in outbound.values.toList()) endOutbound(link, cooldown = false)
        for (link in inbound.values.toList()) endInbound(link)
        failAllNotifies("STOPPED")

        try {
            server?.clearServices()
            server?.close()
        } catch (e: Exception) {
            Log.w(TAG, "closing the GATT server: ${e.message}")
        }
        server = null
        serverCharacteristic = null
        busyAddresses.clear()
    }

    private val watchdog = object : Runnable {
        override fun run() {
            if (!started) return
            val adapter = adapter()
            if (adapter == null || !adapter.isEnabled || !hasPermissions()) {
                // Links have already dropped with the radio. Remember, so the whole
                // stack is rebuilt when it comes back rather than half of it.
                if (!bluetoothWasOff) {
                    bluetoothWasOff = true
                    tearDown()
                }
            } else if (bluetoothWasOff) {
                bluetoothWasOff = false
                watchdogTicks = 0
                bringUp()
            } else {
                watchdogTicks++
                if (watchdogTicks % SCAN_RESTART_EVERY_TICKS == 0) {
                    stopScan()
                    startScan()
                }
                if (!advertising && server != null) startAdvertising()
            }
            main.postDelayed(this, WATCHDOG_MS)
        }
    }

    // ── Peripheral role: the GATT server and the advertisement ──────────────

    private fun openServer() {
        val manager = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return
        val uuid = serviceUuid ?: return
        val opened = try {
            manager.openGattServer(appContext, serverCallback)
        } catch (e: Exception) {
            Log.w(TAG, "openGattServer failed: ${e.message}")
            null
        }
        if (opened == null) {
            // Central-only: this phone can still reach others, others cannot
            // reach it. Worth having rather than nothing.
            Log.w(TAG, "no GATT server; running as a central only")
            return
        }
        val characteristic = BluetoothGattCharacteristic(
            MESH_CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        characteristic.addDescriptor(
            BluetoothGattDescriptor(
                CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        val service = BluetoothGattService(uuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(characteristic)
        server = opened
        serverCharacteristic = characteristic
        // Advertising starts in onServiceAdded: advertising a service the server
        // does not have yet invites a connection to an empty GATT table.
        if (!opened.addService(service)) {
            Log.w(TAG, "addService was refused; running as a central only")
        }
    }

    private fun startAdvertising() {
        val uuid = serviceUuid ?: return
        val advertiser = adapter()?.bluetoothLeAdvertiser
        if (advertiser == null) {
            Log.w(TAG, "this device cannot advertise; others will not find it")
            return
        }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        // Requirement 3: the service UUID and nothing else. No name, no TX power,
        // no manufacturer data, no service data.
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(ParcelUuid(uuid))
            .build()
        try {
            advertiser.startAdvertising(settings, data, advertiseCallback)
            advertising = true
        } catch (e: Exception) {
            Log.w(TAG, "startAdvertising failed: ${e.message}")
            advertising = false
        }
    }

    private fun stopAdvertising() {
        if (!advertising) return
        advertising = false
        try {
            adapter()?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        } catch (e: Exception) {
            Log.w(TAG, "stopAdvertising: ${e.message}")
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {}

        override fun onStartFailure(errorCode: Int) {
            main.post {
                // ALREADY_STARTED is success by another name.
                advertising = errorCode == ADVERTISE_FAILED_ALREADY_STARTED
                if (!advertising) Log.w(TAG, "advertising failed: $errorCode")
            }
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            main.post {
                if (started && status == BluetoothGatt.GATT_SUCCESS) startAdvertising()
            }
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            main.post {
                if (!started) return@post
                val address = device.address
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    // Not reported yet: a central is a peer only once it has
                    // subscribed, because until then it cannot be written to.
                    // This also fires for links this phone opened as a central;
                    // those never subscribe here, so they are never reported twice.
                    inbound.getOrPut(address) { InboundLink(UUID.randomUUID().toString(), device) }
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    inbound[address]?.let { endInbound(it) }
                }
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            main.post {
                val link = inbound[device.address] ?: return@post
                link.mtu = mtu.coerceIn(MIN_MTU, REQUESTED_MTU)
                if (link.subscribed) {
                    emit(mapOf("event" to "mtu", "peerId" to link.peerId, "mtu" to link.mtu))
                }
            }
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor,
        ) {
            main.post {
                val subscribed = inbound[device.address]?.subscribed == true
                val value = if (subscribed) {
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                } else {
                    BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                }
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            main.post {
                val ok = started && descriptor.uuid == CCCD_UUID && !preparedWrite && offset == 0
                if (responseNeeded) {
                    server?.sendResponse(
                        device,
                        requestId,
                        if (ok) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE,
                        0,
                        null,
                    )
                }
                if (!ok) return@post
                val link = inbound.getOrPut(device.address) {
                    InboundLink(UUID.randomUUID().toString(), device)
                }
                val wantsUpdates = value != null && value.isNotEmpty() && (value[0].toInt() and 0x03) != 0
                if (wantsUpdates && !link.subscribed) {
                    link.subscribed = true
                    emitPeer(link.peerId, true, link.mtu)
                } else if (!wantsUpdates && link.subscribed) {
                    endInbound(link)
                }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            main.post {
                // Long (prepared) writes are refused. A chunk is sized to fit one
                // ATT packet, so a peer sending a long write is not this app, and
                // assembling one would mean buffering bytes a stranger chose.
                val acceptable = started &&
                    characteristic.uuid == MESH_CHARACTERISTIC_UUID &&
                    !preparedWrite &&
                    offset == 0
                if (responseNeeded) {
                    server?.sendResponse(
                        device,
                        requestId,
                        if (acceptable) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
                        0,
                        null,
                    )
                }
                if (!acceptable || value == null || value.isEmpty()) return@post
                val link = inbound[device.address] ?: return@post
                // Bytes from a central that never subscribed are dropped: the Dart
                // side has not been told this peer exists.
                if (!link.subscribed) return@post
                emit(mapOf("event" to "data", "peerId" to link.peerId, "bytes" to value))
            }
        }

        override fun onExecuteWrite(device: BluetoothDevice, requestId: Int, execute: Boolean) {
            main.post {
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
            }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            main.post {
                val pending = notifyInFlight ?: return@post
                if (pending.link.device.address != device.address) return@post
                finishNotify(pending, if (status == BluetoothGatt.GATT_SUCCESS) null else "notify status $status")
            }
        }
    }

    private fun endInbound(link: InboundLink) {
        inbound.remove(link.device.address)
        failNotifiesFor(link, "DISCONNECTED")
        if (link.subscribed) {
            link.subscribed = false
            emitPeer(link.peerId, false, null)
        }
    }

    // ── Central role: scanning and outbound links ───────────────────────────

    private fun startScan() {
        val uuid = serviceUuid ?: return
        val scanner = adapter()?.bluetoothLeScanner ?: return
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(uuid)).build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
            .build()
        try {
            scanner.startScan(listOf(filter), settings, scanCallback)
            scanning = true
        } catch (e: Exception) {
            Log.w(TAG, "startScan failed: ${e.message}")
            scanning = false
        }
    }

    private fun stopScan() {
        if (!scanning) return
        scanning = false
        try {
            adapter()?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: Exception) {
            Log.w(TAG, "stopScan: ${e.message}")
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            main.post { maybeConnect(result.device) }
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            main.post { results.forEach { maybeConnect(it.device) } }
        }

        override fun onScanFailed(errorCode: Int) {
            main.post {
                scanning = false
                Log.w(TAG, "scan failed: $errorCode")
            }
        }
    }

    private fun maybeConnect(device: BluetoothDevice) {
        if (!started) return
        val address = device.address
        if (address in busyAddresses) return
        if (outbound.size >= MAX_CENTRAL_LINKS) return
        val until = cooldownUntil[address]
        if (until != null && SystemClock.elapsedRealtime() < until) return
        cooldownUntil.remove(address)

        val gatt = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(appContext, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(appContext, false, gattCallback)
            }
        } catch (e: Exception) {
            Log.w(TAG, "connectGatt failed: ${e.message}")
            null
        } ?: return

        val link = OutboundLink(UUID.randomUUID().toString(), address, gatt)
        busyAddresses.add(address)
        outbound[link.peerId] = link
        val timeout = Runnable {
            if (outbound[link.peerId] === link && !link.reported) endOutbound(link, cooldown = true)
        }
        link.setupTimeout = timeout
        main.postDelayed(timeout, SETUP_TIMEOUT_MS)
    }

    private fun linkFor(gatt: BluetoothGatt): OutboundLink? = outbound.values.firstOrNull { it.gatt === gatt }

    private fun endOutbound(link: OutboundLink, cooldown: Boolean) {
        if (outbound.remove(link.peerId) == null) return
        busyAddresses.remove(link.address)
        link.setupTimeout?.let { main.removeCallbacks(it) }
        link.writeTimeout?.let { main.removeCallbacks(it) }
        link.pendingWrite?.error("DISCONNECTED", "the link closed", null)
        link.pendingWrite = null
        if (cooldown) cooldownUntil[link.address] = SystemClock.elapsedRealtime() + RECONNECT_COOLDOWN_MS
        try {
            link.gatt.disconnect()
            link.gatt.close() // releases the client slot; Android has few of them
        } catch (e: Exception) {
            Log.w(TAG, "closing a GATT client: ${e.message}")
        }
        if (link.reported) {
            link.reported = false
            emitPeer(link.peerId, false, null)
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                val link = linkFor(gatt)
                if (link == null) {
                    gatt.close()
                    return@post
                }
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    // MTU first, then discovery: some stacks drop a discovery that
                    // overlaps an MTU exchange.
                    if (!gatt.requestMtu(REQUESTED_MTU)) gatt.discoverServices()
                } else {
                    endOutbound(link, cooldown = true)
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            main.post {
                val link = linkFor(gatt) ?: return@post
                link.mtu = if (status == BluetoothGatt.GATT_SUCCESS) mtu.coerceIn(MIN_MTU, REQUESTED_MTU) else MIN_MTU
                if (link.reported) {
                    emit(mapOf("event" to "mtu", "peerId" to link.peerId, "mtu" to link.mtu))
                } else if (!gatt.discoverServices()) {
                    endOutbound(link, cooldown = true)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            main.post {
                val link = linkFor(gatt) ?: return@post
                val uuid = serviceUuid
                val characteristic = if (status == BluetoothGatt.GATT_SUCCESS && uuid != null) {
                    gatt.getService(uuid)?.getCharacteristic(MESH_CHARACTERISTIC_UUID)
                } else {
                    null
                }
                val cccd = characteristic?.getDescriptor(CCCD_UUID)
                if (characteristic == null || cccd == null || !gatt.setCharacteristicNotification(characteristic, true)) {
                    endOutbound(link, cooldown = true)
                    return@post
                }
                link.characteristic = characteristic
                val queued = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) ==
                        BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    gatt.writeDescriptor(cccd)
                }
                if (!queued) endOutbound(link, cooldown = true)
            }
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            main.post {
                val link = linkFor(gatt) ?: return@post
                if (descriptor.uuid != CCCD_UUID || link.reported) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    endOutbound(link, cooldown = true)
                    return@post
                }
                // Connected, MTU settled, subscribed: only now is this a peer.
                link.setupTimeout?.let { main.removeCallbacks(it) }
                link.setupTimeout = null
                link.reported = true
                emitPeer(link.peerId, true, link.mtu)
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            main.post {
                val link = linkFor(gatt) ?: return@post
                val pending = link.pendingWrite ?: return@post
                link.pendingWrite = null
                link.writeTimeout?.let { main.removeCallbacks(it) }
                link.writeTimeout = null
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    pending.success(null)
                } else {
                    pending.error("WRITE_FAILED", "status $status", null)
                }
            }
        }

        // API 33+ calls this one AND, for compatibility, the deprecated one below.
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            val copy = value.copyOf()
            main.post { deliverNotification(gatt, characteristic, copy) }
        }

        @Deprecated("Replaced by the three-argument form on API 33")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            @Suppress("DEPRECATION")
            val copy = characteristic.value?.copyOf() ?: return
            main.post { deliverNotification(gatt, characteristic, copy) }
        }
    }

    private fun deliverNotification(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
        val link = linkFor(gatt) ?: return
        if (!link.reported || characteristic.uuid != MESH_CHARACTERISTIC_UUID || value.isEmpty()) return
        emit(mapOf("event" to "data", "peerId" to link.peerId, "bytes" to value))
    }

    // ── Writing ─────────────────────────────────────────────────────────────

    private fun write(peerId: String?, bytes: ByteArray?, result: MethodChannel.Result) {
        if (!started) {
            result.error("STOPPED", "the radio is not running", null)
            return
        }
        if (peerId.isNullOrEmpty() || bytes == null || bytes.isEmpty()) {
            result.error("BAD_ARGS", "peerId and bytes are required", null)
            return
        }

        val out = outbound[peerId]
        if (out != null && out.reported) {
            writeOutbound(out, bytes, result)
            return
        }
        val into = inbound.values.firstOrNull { it.peerId == peerId && it.subscribed }
        if (into != null) {
            // Requirement 2, enforced: never hand a stack more than it agreed to.
            if (bytes.size > into.mtu - 3) {
                result.error("TOO_LARGE", "${bytes.size} bytes exceeds MTU ${into.mtu}", null)
                return
            }
            notifyQueue.addLast(PendingNotify(into, bytes, result))
            pumpNotifies()
            return
        }
        result.error("NO_PEER", "no such link", null)
    }

    private fun writeOutbound(link: OutboundLink, bytes: ByteArray, result: MethodChannel.Result) {
        val characteristic = link.characteristic
        if (characteristic == null) {
            result.error("NO_PEER", "link not ready", null)
            return
        }
        if (link.pendingWrite != null) {
            // The Dart transport writes one chunk at a time per peer, so this is a
            // contract violation rather than load. Refuse it rather than queue it.
            result.error("BUSY", "a write is already in flight", null)
            return
        }
        if (bytes.size > link.mtu - 3) {
            result.error("TOO_LARGE", "${bytes.size} bytes exceeds MTU ${link.mtu}", null)
            return
        }
        val queued = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            link.gatt.writeCharacteristic(
                characteristic,
                bytes,
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
            ) == BluetoothStatusCodes.SUCCESS
        } else {
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            @Suppress("DEPRECATION")
            characteristic.value = bytes
            @Suppress("DEPRECATION")
            link.gatt.writeCharacteristic(characteristic)
        }
        if (!queued) {
            result.error("WRITE_FAILED", "the stack refused the write", null)
            return
        }
        link.pendingWrite = result
        val timeout = Runnable {
            if (link.pendingWrite === result) {
                link.pendingWrite = null
                link.writeTimeout = null
                result.error("TIMEOUT", "the write was not acknowledged", null)
            }
        }
        link.writeTimeout = timeout
        main.postDelayed(timeout, WRITE_TIMEOUT_MS)
    }

    private fun pumpNotifies() {
        if (notifyInFlight != null) return
        val server = server
        val characteristic = serverCharacteristic
        while (notifyQueue.isNotEmpty()) {
            val next = notifyQueue.removeFirst()
            if (server == null || characteristic == null || !next.link.subscribed) {
                next.result.error("NO_PEER", "link closed before the write", null)
                continue
            }
            val queued = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                server.notifyCharacteristicChanged(next.link.device, characteristic, false, next.bytes) ==
                    BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                characteristic.value = next.bytes
                @Suppress("DEPRECATION")
                server.notifyCharacteristicChanged(next.link.device, characteristic, false)
            }
            if (!queued) {
                next.result.error("WRITE_FAILED", "the stack refused the notification", null)
                continue
            }
            notifyInFlight = next
            val timeout = Runnable {
                if (notifyInFlight === next) finishNotify(next, "TIMEOUT")
            }
            next.timeout = timeout
            main.postDelayed(timeout, WRITE_TIMEOUT_MS)
            return
        }
    }

    private fun finishNotify(pending: PendingNotify, error: String?) {
        if (notifyInFlight !== pending) return
        notifyInFlight = null
        pending.timeout?.let { main.removeCallbacks(it) }
        if (error == null) {
            pending.result.success(null)
        } else {
            pending.result.error("WRITE_FAILED", error, null)
        }
        pumpNotifies()
    }

    private fun failNotifiesFor(link: InboundLink, code: String) {
        val inFlight = notifyInFlight
        val iterator = notifyQueue.iterator()
        while (iterator.hasNext()) {
            val next = iterator.next()
            if (next.link === link) {
                iterator.remove()
                next.result.error(code, "the link closed", null)
            }
        }
        if (inFlight != null && inFlight.link === link) finishNotify(inFlight, code)
    }

    private fun failAllNotifies(code: String) {
        val inFlight = notifyInFlight
        notifyInFlight = null
        inFlight?.timeout?.let { main.removeCallbacks(it) }
        inFlight?.result?.error(code, "the radio stopped", null)
        while (notifyQueue.isNotEmpty()) notifyQueue.removeFirst().result.error(code, "the radio stopped", null)
    }
}
