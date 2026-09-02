import Foundation
import Darwin

public final class AppleCompanionHelperProcess: @unchecked Sendable {
    private let helperURL: URL
    private let socketPath: String
    private let processLock = NSLock()
    private var process: Process?

    public init(helperURL: URL, socketPath: String) {
        self.helperURL = helperURL
        self.socketPath = socketPath
    }

    public var isRunning: Bool {
        processLock.withLock { process?.isRunning == true }
    }

    public func start(
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws(AppleCompanionProtocolError) {
        guard !isRunning else { return }
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw .unavailable
        }
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw .unavailable
        }
        let socketDirectory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        try prepareSocketDirectory(socketDirectory)
        try removeExistingOwnedSocket()

        let process = Process()
        process.executableURL = helperURL
        process.arguments = []
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "MEDIA_CONTROL_RELAY_SOCKET": socketPath,
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONNOUSERSITE": "1",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw .unavailable
        }
        processLock.withLock {
            self.process = process
        }

        let deadline = DispatchTime.now().uptimeNanoseconds &+ timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if isOwnedSocketReady() {
                return
            }
            guard process.isRunning else {
                processLock.withLock {
                    if self.process === process {
                        self.process = nil
                    }
                }
                throw .unavailable
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        stop()
        throw .unavailable
    }

    public func stop() {
        guard let process = processLock.withLock({
            defer { self.process = nil }
            return self.process
        }) else { return }
        if process.isRunning {
            process.terminate()
            let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            while process.isRunning, DispatchTime.now().uptimeNanoseconds < deadline {
                usleep(10_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }
    }

    private func isOwnedSocketReady() -> Bool {
        var info = stat()
        return lstat(socketPath, &info) == 0
            && (info.st_mode & S_IFMT) == S_IFSOCK
            && info.st_uid == getuid()
            && (info.st_mode & 0o077) == 0
    }

    private func prepareSocketDirectory(
        _ socketDirectory: URL
    ) throws(AppleCompanionProtocolError) {
        var info = stat()
        if lstat(socketDirectory.path, &info) != 0 {
            guard errno == ENOENT else { throw .unavailable }
            do {
                try FileManager.default.createDirectory(
                    at: socketDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw .unavailable
            }
            guard lstat(socketDirectory.path, &info) == 0 else { throw .unavailable }
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == getuid(),
              (info.st_mode & 0o077) == 0 else {
            throw .unavailable
        }
    }

    private func removeExistingOwnedSocket() throws(AppleCompanionProtocolError) {
        var info = stat()
        guard lstat(socketPath, &info) == 0 else {
            guard errno == ENOENT else { throw .unavailable }
            return
        }
        guard (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(),
              (info.st_mode & 0o077) == 0,
              unlink(socketPath) == 0 else {
            throw .unavailable
        }
    }
}
