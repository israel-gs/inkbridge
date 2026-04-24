# Spec: Transport

## Purpose

Defines how inkbridge frames (specified in `wire-protocol.md`) are carried between the Android client and the macOS server over two transport paths: UDP over Wi-Fi and TCP over USB via `adb reverse`. The transport layer is responsible for connection lifecycle, port assignment, and the selection contract. It is NOT responsible for frame parsing or event injection — those are handled by the codec and the injector respectively.

---

## Requirements

### R1. Single Port for Both Transports

Both the UDP and TCP paths MUST use port **4545** by default. The same port number MUST be used on both ends, making `adb reverse tcp:4545 tcp:4545` the correct setup command for the USB path.

#### Scenario: default port
- **Given** the user launches the Android app without having changed any port setting
- **When** the app attempts to connect
- **Then** it MUST target port 4545 on the configured host

#### Scenario: user-configured port
- **Given** the user enters a custom port (e.g., 9000) in the connection UI
- **When** the app connects
- **Then** it MUST use port 9000 for both transport types, and the UI MUST display the current effective port

---

### R2. Transport Selection

The user MUST explicitly choose between UDP (Wi-Fi) and TCP (USB) via the Android connection UI. There is no automatic transport detection in this change.

#### Scenario: UDP selected
- **Given** the user selects "Wi-Fi (UDP)" in the transport selector
- **When** the app connects
- **Then** the Android side MUST open a UDP socket and send frames as individual datagrams to `host:port`

#### Scenario: TCP selected
- **Given** the user selects "USB (TCP)" in the transport selector
- **When** the app connects
- **Then** the Android side MUST open a TCP connection to `127.0.0.1:port` (loopback, via `adb reverse`)

---

### R3. UDP Transport (Wi-Fi Path)

The Android client MUST send each inkbridge frame as a single UDP datagram. The macOS server MUST listen on a UDP socket bound to `0.0.0.0:4545`.

- Each frame MUST fit in a single datagram. The maximum frame size defined by the wire protocol (36 bytes for `STYLUS_MOVE`) is well within any practical MTU.
- The sender MUST NOT fragment frames across multiple datagrams.
- The receiver MUST process each datagram independently and MUST NOT assume ordering between datagrams.
- The receiver MUST apply the sequence-number drop policy from `wire-protocol.md R9` to handle reordering.

#### Scenario: datagram delivery
- **Given** a STYLUS_MOVE frame of 36 bytes is serialized
- **When** the Android UDP sender transmits it
- **Then** exactly one UDP datagram of 36 bytes MUST be sent; the receiver reads exactly 36 bytes from a single `recvfrom` call

#### Scenario: out-of-order datagram drop
- **Given** datagrams arrive with sequences [5, 7, 6] due to Wi-Fi reordering
- **When** the macOS UDP receiver processes them
- **Then** sequences 5 and 7 are accepted; sequence 6 MUST be discarded per R9 of wire-protocol.md

---

### R4. TCP Transport (USB Path via adb reverse)

The Android client MUST establish a TCP connection to `127.0.0.1:port`. The macOS server MUST listen on a TCP socket bound to `127.0.0.1:4545` (loopback only — this transport is only meaningful when `adb reverse` is configured).

- The Android app MUST connect only after the user explicitly taps the connect action. It MUST NOT attempt automatic reconnection on failure in this change.
- Frames MUST be written to the TCP stream as contiguous byte sequences. Because TCP is a stream protocol, the receiver MUST read frames by first reading the fixed 16-byte header, then reading the payload of length determined by `event_type`, as specified in wire-protocol.md.
- The server MUST accept at most one client connection at a time. If a new TCP connection arrives while one is already active, the server MUST close the existing connection before accepting the new one.

#### Scenario: TCP connection establishment
- **Given** the macOS server is running and listening on TCP 127.0.0.1:4545, and `adb reverse tcp:4545 tcp:4545` has been set up
- **When** the Android app selects USB (TCP) and taps Connect with host `127.0.0.1`
- **Then** the TCP handshake MUST complete and the connection MUST be active within 3 seconds, or the app MUST surface a connection error to the user

#### Scenario: stream framing
- **Given** a TCP connection is active and three STYLUS_MOVE frames (36 bytes each) are written back-to-back
- **When** the macOS TCP reader processes the stream
- **Then** it MUST parse exactly 3 frames by reading 16+20 bytes per iteration, regardless of how TCP segments deliver the bytes

#### Scenario: connection closed by client
- **Given** a TCP connection is active
- **When** the Android app disconnects (user action or app goes to background)
- **Then** the macOS server MUST detect the closed connection (EOF or read error), stop attempting to read, and return to the listening state

---

### R5. Manual IP Configuration (Wi-Fi Path)

For the UDP path, the user MUST manually enter the macOS host IP address in the Android connection UI. There is no automatic discovery in this change.

- The app MUST accept any valid IPv4 address or hostname as input.
- The app MUST validate that the entered value is a non-empty string before enabling the Connect action. The app SHOULD show an inline validation error if the format is clearly invalid (e.g., contains illegal characters), but MUST NOT perform network validation (DNS lookup, ping) before connecting.
- The app MUST NOT store the IP address between sessions in this change (the field resets on relaunch).

#### Scenario: empty host field
- **Given** the user leaves the host field empty
- **When** the user taps the Connect button
- **Then** the Connect action MUST be disabled and MUST NOT initiate a connection

#### Scenario: invalid IP format
- **Given** the user types `999.999.999.999` in the host field
- **When** the user views the field
- **Then** the app SHOULD show an inline error indicating the address format is invalid; the Connect button MUST remain disabled

---

### R6. Connection State Contract

Both the Android and macOS sides MUST track a well-defined connection state and surface it in the UI (see `ui.md`).

Android connection states:
- `DISCONNECTED` — no active transport, initial state on launch
- `CONNECTING` — transport is in the process of establishing a connection (TCP only; UDP is stateless so this state transitions immediately)
- `CONNECTED` — transport is active and frames are being sent (or ready to send)
- `ERROR` — last connection attempt failed; error reason MUST be available for display

macOS connection states:
- `IDLE` — server is not listening (permission not granted, or explicitly stopped)
- `LISTENING` — server is bound and waiting for a client
- `CONNECTED` — a client is actively sending frames
- `ERROR` — a transport error occurred; reason MUST be available for display

#### Scenario: UDP "connected" state
- **Given** the user selects UDP and taps Connect with a valid host
- **When** the UDP socket is successfully bound and the first frame is ready to send
- **Then** the Android state MUST transition directly from `CONNECTING` to `CONNECTED` without waiting for a server acknowledgment (UDP is connectionless)

#### Scenario: TCP error on refused connection
- **Given** the macOS server is not running and the user taps Connect on Android with TCP selected
- **When** the TCP connection is refused
- **Then** the Android state MUST transition to `ERROR` and MUST display a user-readable message within 3 seconds

---

### R7. No HELLO Handshake

This change does NOT define a HELLO or version-negotiation handshake frame. The first frame sent MUST be a real event frame (STYLUS_MOVE, STYLUS_PROXIMITY, or STYLUS_BUTTON). Version compatibility is determined by the `version` byte in every frame header (see wire-protocol.md R2).

This is an open question carried forward: a future change MAY introduce a HELLO frame for clean version negotiation before the first event.

#### Scenario: first frame is a real event
- **Given** a TCP or UDP connection is established
- **When** the first stylus event occurs on Android
- **Then** the first bytes transmitted MUST be a valid inkbridge frame with `version = 0x01` and a real event type; there MUST be no preamble or greeting bytes before it
