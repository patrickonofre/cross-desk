import Foundation
import CoreGraphics

/// High-level session state reported to the UI.
public enum SessionState: Equatable, Sendable {
    case stopped
    case waitingPeer
    case connected(peer: String)
    /// Server only: control is on the client (REMOTE).
    case controllingRemote(peer: String)
    case error(String)
}

/// Server orchestration (R1–R5): owns the event tap, the LOCAL ⇄ REMOTE state
/// machine, edge detection and the DTLS server. See design.md state machine.
public final class ServerSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "crossdesk.session.server", qos: .userInteractive)
    private let capture: InputCapture
    private let transport: DTLSServer
    private let detector: EdgeDetector
    private let screens: @Sendable () -> [CGRect]

    private var remote = false
    private var exitScreen = CGRect.zero
    private var escape = EmergencyEscape()
    private var peerName = ""

    /// Called on the session queue.
    public var onState: (@Sendable (SessionState) -> Void)?

    public init(
        port: UInt16,
        pairingCode: String,
        edgeSide: EdgeSide,
        capture: InputCapture = InputCapture(),
        screens: @escaping @Sendable () -> [CGRect] = Displays.activeBounds
    ) {
        self.capture = capture
        self.transport = DTLSServer(port: port, psk: PairingKey.psk(fromCode: pairingCode))
        self.detector = EdgeDetector(side: edgeSide)
        self.screens = screens
        wire()
    }

    public func start() throws {
        Log.session.info("server session: starting (edge \(self.detector.side.rawValue, privacy: .public))")
        try capture.start()
        try transport.start()
        onState?(.waitingPeer)
    }

    public func stop() {
        queue.async { [self] in
            if remote {
                returnToLocal(sendLeave: true)
            }
            capture.stop()
            transport.stop()
            onState?(.stopped)
        }
    }

    // MARK: - Wiring

    private func wire() {
        capture.onEvent = { [weak self] event in
            guard let self else { return }
            self.queue.async { self.handleCaptured(event) }
        }
        transport.onEvent = { [weak self] event in
            guard let self else { return }
            self.queue.async { self.handleTransport(event) }
        }
    }

    private func handleTransport(_ event: TransportEvent) {
        switch event {
        case let .connected(peer):
            Log.session.info("server session: client '\(peer, privacy: .public)' connected")
            peerName = peer
            onState?(.connected(peer: peer))
        case let .disconnected(reason):
            Log.session.info("server session: client disconnected (\(reason, privacy: .public))")
            // Never stay suppressed with a dead link — the server would be
            // uncontrollable (R4 rationale).
            if remote {
                returnToLocal(sendLeave: false)
            }
            peerName = ""
            onState?(.waitingPeer)
        case let .messages(messages):
            for message in messages {
                // Client crossed its return edge (client-side detection — it
                // owns its own topology). May arrive duplicated (UDP retry);
                // once LOCAL, extras are ignored.
                if case let .leaveRequest(x, y) = message, remote {
                    let coordinate: CGFloat = switch detector.side {
                    case .left, .right: CGFloat(y)
                    case .top, .bottom: CGFloat(x)
                    }
                    Log.session.info("server session: LEAVE_REQUEST from client")
                    returnToLocal(sendLeave: true, exitCoordinate: coordinate)
                }
            }
        }
    }

    private func handleCaptured(_ event: CapturedEvent) {
        remote ? handleRemote(event) : handleLocal(event)
    }

    // MARK: - LOCAL

    private func handleLocal(_ event: CapturedEvent) {
        guard !peerName.isEmpty else { return } // no client — nothing to do
        guard case let .mouseMoved(_, _, location) = event else { return }
        let allScreens = screens()
        guard let entry = detector.crossing(at: location, in: allScreens) else { return }

        // Crossed: freeze the local cursor and start streaming to the client.
        let screen = allScreens.first { $0.insetBy(dx: -1, dy: -1).contains(location) } ?? .zero
        exitScreen = screen
        remote = true
        capture.suppressing = true
        CGAssociateMouseAndMouseCursorPosition(0)
        Log.session.info("server session: edge crossed → REMOTE")
        // The client enters through the edge opposite to ours and detects the
        // return crossing itself (LEAVE_REQUEST) — no server-side simulation
        // of the remote cursor.
        transport.send([.enter(x: Float(entry.x), y: Float(entry.y), edge: detector.side.opposite)])
        onState?(.controllingRemote(peer: peerName))
    }

    // MARK: - REMOTE

    private func handleRemote(_ event: CapturedEvent) {
        switch event {
        case let .mouseMoved(dx, dy, _):
            transport.send([.mouseMove(dx: Float(dx), dy: Float(dy))])
        case let .mouseButton(button, isDown):
            transport.send([.mouseButton(button: button, pressed: isDown)])
        case let .scroll(dx, dy):
            transport.send([.scroll(dx: Float(dx), dy: Float(dy))])
        case let .key(macKeycode, isDown):
            // Emergency escape (R4): Esc 3× within 1 s always returns control.
            // The Esc presses do reach the client first — acceptable MVP noise.
            if macKeycode == 0x35, isDown,
               escape.registerEscapeDown(at: ProcessInfo.processInfo.systemUptime) {
                returnToLocal(sendLeave: true)
                return
            }
            guard let usage = HIDKeycodes.hidUsage(forMacKeycode: macKeycode) else { return }
            transport.send([.key(hidUsage: usage, pressed: isDown)])
        }
    }

    private func returnToLocal(sendLeave: Bool, exitCoordinate: CGFloat? = nil) {
        Log.session.info("server session: → LOCAL (sendLeave \(sendLeave, privacy: .public))")
        remote = false
        capture.suppressing = false
        CGAssociateMouseAndMouseCursorPosition(1)

        // Re-place the physical cursor on the edge it conceptually re-entered.
        if let exitCoordinate, exitScreen != .zero {
            let point: CGPoint = switch detector.side {
            case .left:
                CGPoint(x: exitScreen.minX + 2, y: exitScreen.minY + exitCoordinate * exitScreen.height)
            case .right:
                CGPoint(x: exitScreen.maxX - 2, y: exitScreen.minY + exitCoordinate * exitScreen.height)
            case .top:
                CGPoint(x: exitScreen.minX + exitCoordinate * exitScreen.width, y: exitScreen.minY + 2)
            case .bottom:
                CGPoint(x: exitScreen.minX + exitCoordinate * exitScreen.width, y: exitScreen.maxY - 2)
            }
            CGWarpMouseCursorPosition(point)
        }

        if sendLeave {
            transport.send([.leave])
        }
        onState?(peerName.isEmpty ? .waitingPeer : .connected(peer: peerName))
    }
}
