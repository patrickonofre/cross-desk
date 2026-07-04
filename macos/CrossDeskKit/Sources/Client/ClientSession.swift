import Foundation
import CoreGraphics

/// Client orchestration (R6–R8, R17–R19): receives remote input over DTLS and
/// injects it locally; freezes/hides this machine's arrow while connected but
/// unfocused; releases everything held on LEAVE/disconnect (R7).
public final class ClientSession: @unchecked Sendable {
    private let transport: DTLSClient
    private let injector: InputInjector
    private let sentinel: CursorSentinel
    private let concealer: CursorConcealer
    private let observer: SystemStateObserver
    private let metrics: InputMetrics
    private let cursorLocation: @Sendable () -> CGPoint

    /// Called on the transport queue.
    public var onState: (@Sendable (SessionState) -> Void)?

    public init(
        host: String,
        port: UInt16,
        pairingCode: String,
        deviceName: String,
        conceal: Bool = true,
        injector: InputInjector = InputInjector(),
        concealer: CursorConcealer = CursorConcealer(),
        observer: SystemStateObserver = SystemStateObserver(),
        metrics: InputMetrics = InputMetrics(),
        cursorLocation: @escaping @Sendable () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero }
    ) {
        self.transport = DTLSClient(
            host: host,
            port: port,
            psk: PairingKey.psk(fromCode: pairingCode),
            deviceName: deviceName
        )
        self.injector = injector
        self.concealer = concealer
        self.observer = observer
        self.metrics = metrics
        self.cursorLocation = cursorLocation

        // The sentinel drives the arrow lock (R18). onLock/onUnlock let it hide
        // the cursor via the concealer when the user enabled it (R17) without
        // the sentinel knowing about the config.
        let conc = concealer
        let doConceal = conceal
        self.sentinel = CursorSentinel(effects: .live(
            onLock: { if doConceal { conc.hide() } },
            onUnlock: { conc.show() }
        ))
        wire()
    }

    public func start() {
        transport.start()
        observer.start()
        onState?(.waitingPeer)
    }

    public func stop() {
        // Order matters: unlock the arrow before tearing the transport down so
        // the machine is never left pinned behind a dead link (R18).
        sentinel.release()
        injector.releaseEverything()
        observer.stop()
        transport.stop()
        metrics.bump(.warpsRecovered, by: sentinel.warpsRecovered)
        metrics.logSummary(context: "client")
        onState?(.stopped)
    }

    private func wire() {
        // Return edge crossed locally (client owns its own topology, R3): ask
        // the server for control back. Repeats on further outward moves until
        // the server's LEAVE lands — natural retry over lossy UDP.
        injector.onExitEdge = { [weak self] exit in
            self?.transport.send([.leaveRequest(x: Float(exit.x), y: Float(exit.y))])
        }
        // ENTER: injection takes over — release the lock, show the arrow.
        injector.onFocusGained = { [weak self] in
            self?.sentinel.release()
        }
        // LEAVE: freeze the arrow at the return-edge park point (+ hide it).
        injector.onFocusLost = { [weak self] park in
            self?.sentinel.engage(park: park)
        }
        // System woke / screensaver ended / displays changed: the WindowServer
        // may have dropped the dissociation and hide — re-assert them (R19).
        observer.onReassert = { [weak self] _ in
            guard let self else { return }
            self.metrics.bump(.reasserts)
            self.sentinel.reassert()
        }
        transport.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .connected:
                Log.session.info("client session: connected to server")
                // Connected and unfocused: freeze this machine's arrow wherever
                // it currently sits (R16/R18). ENTER unlocks it; LEAVE re-locks;
                // disconnection below always unlocks — worst case the lock dies
                // with the heartbeat (6 s).
                self.sentinel.engage(park: self.cursorLocation())
                self.onState?(.connected(peer: "servidor"))
            case .disconnected:
                Log.session.info("client session: disconnected — releasing held keys")
                // Wire gone mid-chord: synthesize key-ups so nothing stays stuck
                // (R7) and NEVER keep the cursor locked behind a dead link (R18).
                // The transport keeps reconnecting on its own.
                self.sentinel.release()
                self.injector.releaseEverything()
                self.onState?(.waitingPeer)
            case let .messages(messages):
                // Injected directly from the transport queue (design.md T2).
                self.metrics.bump(.datagramsReceived)
                for message in messages {
                    self.metrics.bump(.injectedMessages)
                    self.injector.apply(message)
                }
            }
        }
    }
}
