import Foundation
import Core

/// Discord Rich Presence client for macOS.
/// Communicates with Discord via its local IPC Unix socket to show the currently
/// playing track in the user's Discord status.
public final class DiscordRichPresence: @unchecked Sendable {

    /// Discord application client ID (register at discord.com/developers)
    private let clientId: String
    private let appName: String

    /// Connection state
    private var socket: Int32 = -1
    private var isConnected = false
    private let queue = DispatchQueue(label: "com.panoscrobbler.discord-rpc", qos: .utility)

    public init(clientId: String, appName: String = "Pano Scrobbler") {
        self.clientId = clientId
        self.appName = appName
    }

    deinit {
        closeSocket()
    }

    // MARK: - Public API

    /// Connect to Discord IPC socket.
    public func connect() -> Bool {
        queue.sync {
            guard !isConnected else { return true }

            for i in 0..<10 {
                let path = discordSocketPath(index: i)
                let fd = socket_connect(path: path)
                if fd >= 0 {
                    socket = fd
                    if handshake() {
                        isConnected = true
                        return true
                    }
                    close(fd)
                }
            }
            return false
        }
    }

    /// Update Discord activity with current track.
    public func updateActivity(
        track: String,
        artist: String,
        album: String?,
        elapsed: TimeInterval?,
        duration: TimeInterval?,
        artworkURL: String? = nil
    ) {
        queue.async { [self] in
            if !isConnected {
                guard connect() else { return }
            }

            let now = Date().timeIntervalSince1970
            var timestamps: [String: Any] = [:]
            if let elapsed {
                timestamps["start"] = Int(now - elapsed)
            }
            if let duration, duration > 0, let elapsed {
                timestamps["end"] = Int(now - elapsed + duration)
            }

            var assets: [String: Any] = [:]
            if let artworkURL, !artworkURL.isEmpty {
                assets["large_image"] = artworkURL
                assets["large_text"] = album ?? track
            } else {
                assets["large_image"] = "pano_scrobbler"
                assets["large_text"] = appName
            }
            assets["small_image"] = "pano_scrobbler"
            assets["small_text"] = appName

            var activity: [String: Any] = [
                "type": 2, // Listening
                "details": track,
                "state": "by \(artist)",
            ]

            if !timestamps.isEmpty {
                activity["timestamps"] = timestamps
            }
            activity["assets"] = assets

            let payload: [String: Any] = [
                "cmd": "SET_ACTIVITY",
                "args": ["pid": ProcessInfo.processInfo.processIdentifier, "activity": activity],
                "nonce": UUID().uuidString
            ]

            sendFrame(opcode: 1, data: payload)
        }
    }

    /// Clear the Discord activity.
    public func clearActivity() {
        queue.async { [self] in
            guard isConnected else { return }

            let payload: [String: Any] = [
                "cmd": "SET_ACTIVITY",
                "args": ["pid": ProcessInfo.processInfo.processIdentifier],
                "nonce": UUID().uuidString
            ]

            sendFrame(opcode: 1, data: payload)
        }
    }

    /// Disconnect from Discord.
    public func disconnect() {
        queue.async { [self] in
            closeSocket()
        }
    }

    // MARK: - IPC Protocol

    private func discordSocketPath(index: Int) -> String {
        // macOS: /var/folders/.../T/discord-ipc-{index}
        // Also check common XDG paths
        let tmpDir = NSTemporaryDirectory()

        // Check standard macOS temp location
        let path = (tmpDir as NSString).appendingPathComponent("discord-ipc-\(index)")
        if FileManager.default.fileExists(atPath: path) {
            return path
        }

        // Check XDG_RUNTIME_DIR (for Linux compat / Flatpak)
        if let xdg = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] {
            let xdgPath = (xdg as NSString).appendingPathComponent("discord-ipc-\(index)")
            if FileManager.default.fileExists(atPath: xdgPath) {
                return xdgPath
            }
        }

        // Also check common snap / flatpak paths
        let appPath = (tmpDir as NSString).appendingPathComponent("app/com.discordapp.Discord/discord-ipc-\(index)")
        if FileManager.default.fileExists(atPath: appPath) {
            return appPath
        }

        return path
    }

    private func socket_connect(path: String) -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            return -1
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: buf.count)
            }
        }

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, len)
            }
        }

        guard result == 0 else {
            close(fd)
            return -1
        }

        return fd
    }

    private func handshake() -> Bool {
        let payload: [String: Any] = [
            "v": 1,
            "client_id": clientId
        ]
        return sendFrame(opcode: 0, data: payload)
    }

    private func closeSocket() {
        guard socket >= 0 else {
            isConnected = false
            return
        }
        close(socket)
        socket = -1
        isConnected = false
    }

    @discardableResult
    private func sendFrame(opcode: UInt32, data: [String: Any]) -> Bool {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return false }

        // Discord IPC frame: [opcode: UInt32][length: UInt32][json payload]
        var header = Data(count: 8)
        header.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: opcode.littleEndian, as: UInt32.self)
            ptr.storeBytes(of: UInt32(jsonData.count).littleEndian, toByteOffset: 4, as: UInt32.self)
        }

        let frame = header + jsonData
        return writeAll(frame)
    }

    private func writeAll(_ data: Data) -> Bool {
        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return true }
            var offset = 0

            while offset < data.count {
                let written = Darwin.write(socket, baseAddress.advanced(by: offset), data.count - offset)
                if written > 0 {
                    offset += written
                } else if written == -1 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }

            return true
        }
    }
}
