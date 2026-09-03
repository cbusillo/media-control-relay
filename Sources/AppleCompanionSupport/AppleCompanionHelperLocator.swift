import CryptoKit
import Darwin
import Foundation

public struct AppleCompanionHelperManifest: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public let schema: Int
    public let digest: String
    public let pythonVersion: String

    public init(schema: Int = currentSchema, digest: String, pythonVersion: String) {
        self.schema = schema
        self.digest = digest
        self.pythonVersion = pythonVersion
    }
}

public struct AppleCompanionHelperInstallation: Equatable, Sendable {
    public let executableURL: URL
    public let manifest: AppleCompanionHelperManifest

    public init(executableURL: URL, manifest: AppleCompanionHelperManifest) {
        self.executableURL = executableURL
        self.manifest = manifest
    }
}

public enum AppleCompanionHelperAvailability: Equatable, Sendable {
    case installed(AppleCompanionHelperInstallation)
    case notInstalled
    case damaged
}

public protocol AppleCompanionHelperLocating: Sendable {
    func locate() -> AppleCompanionHelperAvailability
}

public struct ApplicationSupportAppleCompanionHelperLocator: AppleCompanionHelperLocating, Sendable {
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.shinycomputers.media-control-relay", isDirectory: true)
            .appendingPathComponent("AppleCompanionHelper", isDirectory: true)
    }

    private let root: URL

    public init(root: URL = Self.defaultRoot) {
        self.root = root.standardizedFileURL
    }

    public func locate() -> AppleCompanionHelperAvailability {
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0 else {
            return errno == ENOENT ? .notInstalled : .damaged
        }
        guard isOwnedDirectory(rootInfo) else { return .damaged }

        let versions = root.appendingPathComponent("versions", isDirectory: true)
        let pythonRoot = root.appendingPathComponent("python", isDirectory: true)
        let rootMarker = root.appendingPathComponent(
            ".media-control-relay-apple-companion-helper"
        )
        let current = root.appendingPathComponent("current")
        guard secureDirectory(at: versions),
              secureDirectory(at: pythonRoot),
              secureFile(at: rootMarker, executable: false),
              (try? String(contentsOf: rootMarker, encoding: .utf8))
                  == "media-control-relay-apple-companion-helper-v1\n",
              secureSymlink(at: current) else {
            return .damaged
        }

        let resolved = current.resolvingSymlinksInPath().standardizedFileURL
        let versionsPath = versions.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard resolved.path.hasPrefix(versionsPath), secureDirectory(at: resolved) else {
            return .damaged
        }

        let manifestURL = resolved.appendingPathComponent("manifest.json")
        let executableURL = resolved
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("apple-companion-helper")
        let pythonExecutableURL = resolved
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
        guard secureFile(at: manifestURL, executable: false),
              secureFile(at: executableURL, executable: true),
              secureResolvedExecutable(at: pythonExecutableURL, within: root),
              AppleCompanionHelperContent.fileNames.allSatisfy({
                  secureFile(
                      at: resolved.appendingPathComponent($0),
                      executable: false
                  )
              }),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                  AppleCompanionHelperManifest.self,
                  from: manifestData
              ),
              manifest.schema == AppleCompanionHelperManifest.currentSchema,
              resolved.lastPathComponent == manifest.digest,
              let digest = try? AppleCompanionHelperContent.digest(at: resolved),
              digest == manifest.digest else {
            return .damaged
        }

        return .installed(
            AppleCompanionHelperInstallation(
                executableURL: executableURL,
                manifest: manifest
            )
        )
    }

    private func secureDirectory(at url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && isOwnedDirectory(info)
    }

    private func secureSymlink(at url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
            && (info.st_mode & S_IFMT) == S_IFLNK
            && info.st_uid == getuid()
    }

    private func secureFile(at url: URL, executable: Bool) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(),
              (info.st_mode & 0o077) == 0 else {
            return false
        }
        return !executable || (info.st_mode & 0o100) != 0
    }

    private func secureResolvedExecutable(at url: URL, within root: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        var info = stat()
        return resolved.path.hasPrefix(rootPath)
            && stat(resolved.path, &info) == 0
            && (info.st_mode & S_IFMT) == S_IFREG
            && info.st_uid == getuid()
            && (info.st_mode & 0o100) != 0
    }

    private func isOwnedDirectory(_ info: stat) -> Bool {
        (info.st_mode & S_IFMT) == S_IFDIR
            && info.st_uid == getuid()
            && (info.st_mode & 0o077) == 0
    }
}

public struct AppleCompanionRuntimeResolution: Sendable {
    public let availability: AppleCompanionHelperAvailability
    public let session: AppleCompanionSession?
    public let helperProcess: AppleCompanionHelperProcess?

    public init(
        availability: AppleCompanionHelperAvailability,
        session: AppleCompanionSession?,
        helperProcess: AppleCompanionHelperProcess? = nil
    ) {
        self.availability = availability
        self.session = session
        self.helperProcess = helperProcess
    }
}

public enum AppleCompanionRuntime {
    public static var defaultSocketPath: String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("media-control-relay-\(getuid())", isDirectory: true)
            .appendingPathComponent("apple-companion.sock")
            .path
    }

    public static func makeSession(
        locator: any AppleCompanionHelperLocating = ApplicationSupportAppleCompanionHelperLocator(),
        keychain: any AppleCompanionKeychain = SystemAppleCompanionKeychain(),
        socketPath: String = defaultSocketPath
    ) -> AppleCompanionRuntimeResolution {
        let availability = locator.locate()
        guard case let .installed(installation) = availability else {
            return AppleCompanionRuntimeResolution(
                availability: availability,
                session: nil,
                helperProcess: nil
            )
        }

        let helperProcess = AppleCompanionHelperProcess(
            helperURL: installation.executableURL,
            socketPath: socketPath
        )
        let session = AppleCompanionSession(
            keychain: keychain,
            helperProcess: helperProcess,
            transportFactory: {
                AppleCompanionUnixSocketTransport(path: socketPath)
            }
        )
        return AppleCompanionRuntimeResolution(
            availability: availability,
            session: session,
            helperProcess: helperProcess
        )
    }
}

enum AppleCompanionHelperContent {
    static let fileNames = [
        "helper.py",
        "pyproject.toml",
        "uv.lock",
        ".python-version",
    ]

    static func digest(at root: URL) throws -> String {
        var hasher = SHA256()
        for fileName in fileNames {
            let url = root.appendingPathComponent(fileName)
            var info = stat()
            guard lstat(url.path, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG else {
                throw AppleCompanionProtocolError.unavailable
            }
            let fileDigest = SHA256.hash(data: try Data(contentsOf: url))
                .map { String(format: "%02x", $0) }
                .joined()
            hasher.update(data: Data("\(fileName):\(fileDigest)\n".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
