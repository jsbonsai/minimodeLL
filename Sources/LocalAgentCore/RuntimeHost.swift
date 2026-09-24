import Foundation
import Darwin

/// Real operating-system services for `RuntimeManager`.
public struct SystemRuntimeHost: RuntimeHost {
    public init() {}

    public func reserveLoopbackPort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentError.rejected("Could not reserve a loopback port.") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                bind(fd, pointer, length) == 0 && getsockname(fd, pointer, &length) == 0
            }
        }
        let port = UInt16(bigEndian: address.sin_port)
        guard bound, port != 0 else { throw AgentError.rejected("Could not reserve a loopback port.") }
        return port
    }

    public func launch(executable: URL, arguments: [String], environment: [String: String]) throws -> any RuntimeProcess {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        // Server output can include request content; discard it rather than log it.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let wrapper = SystemRuntimeProcess(process)
        do { try process.run() } catch { throw AgentError.rejected("The bundled runtime could not be launched.") }
        return wrapper
    }

    public func get(_ url: URL, bearer: String?) async throws -> (status: Int, body: Data) {
        guard url.scheme == "http", url.host == "127.0.0.1" else { throw AgentError.rejected("Runtime probes are loopback-only.") }
        var request = URLRequest(url: url)
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.connectionProxyDictionary = [kCFNetworkProxiesHTTPEnable: false, kCFNetworkProxiesHTTPSEnable: false]
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        for try await byte in bytes {
            guard data.count < 65536 else { throw AgentError.rejected("Runtime probe response too large.") }
            data.append(byte)
        }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    public func isListening(pid: Int32, port: UInt16) -> Bool {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return false }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride + 16)
        let used = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard used > 0 else { return false }
        for fd in fds.prefix(Int(used) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
            let tcp = info.psi.soi_proto.pri_tcp
            let localPort = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
            if tcp.tcpsi_state == Int32(TSI_S_LISTEN), localPort == port { return true }
        }
        return false
    }
}

final class SystemRuntimeProcess: RuntimeProcess, @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var status: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []
    init(_ process: Process) {
        self.process = process
        process.terminationHandler = { [weak self] finished in self?.finish(finished.terminationStatus) }
    }
    private func finish(_ code: Int32) {
        let resume: [CheckedContinuation<Int32, Never>] = lock.withLock {
            status = code; defer { waiters = [] }; return waiters
        }
        for waiter in resume { waiter.resume(returning: code) }
    }
    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }
    func terminate() { if process.isRunning { process.terminate() } }
    func forceKill() { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
    func exitStatus() async -> Int32 {
        await withCheckedContinuation { continuation in
            let done: Int32? = lock.withLock {
                if let status { return status }
                waiters.append(continuation); return nil
            }
            if let done { continuation.resume(returning: done) }
        }
    }
}
