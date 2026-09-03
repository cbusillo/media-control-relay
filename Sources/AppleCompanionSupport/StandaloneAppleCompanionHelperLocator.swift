import Darwin
import Foundation

public struct AppleCompanionRuntimeManifest: Codable, Equatable, Sendable {
    public struct ArchitecturePolicy: Codable, Equatable, Sendable {
        public let helperRuntime: String
        public let intelBehavior: String

        public init(helperRuntime: String, intelBehavior: String) {
            self.helperRuntime = helperRuntime
            self.intelBehavior = intelBehavior
        }
    }

    public let schema: Int
    public let pythonVersion: String
    public let architecturePolicy: ArchitecturePolicy
    public let contentSha256: String

    public init(
        schema: Int,
        pythonVersion: String,
        architecturePolicy: ArchitecturePolicy,
        contentSha256: String
    ) {
        self.schema = schema
        self.pythonVersion = pythonVersion
        self.architecturePolicy = architecturePolicy
        self.contentSha256 = contentSha256
    }
}

struct AppleCompanionStandaloneRuntimeContract: Codable, Equatable, Sendable {
    struct Marker: Codable, Equatable, Sendable {
        let relativePath: String
        let contents: String
    }

    static let current = AppleCompanionStandaloneRuntimeContract(
        schema: 1,
        bundleRelativePath: "Contents/Helpers/AppleCompanionRuntime",
        marker: Marker(
            relativePath: ".media-control-relay-apple-companion-runtime-candidate",
            contents: "media-control-relay-apple-companion-runtime-candidate-v1\n"
        ),
        manifestRelativePath: "manifest.json",
        launcherRelativePath: "bin/apple-companion-helper",
        interpreterRelativePath: "python/bin/python3.13",
        pythonVersion: "3.13.7",
        helperRuntimeArchitecture: "arm64",
        intelBehavior: "unsupported",
        contentSha256: "c67cc7c2b969581ead88e85a6d4427f83fafbe7da8ae262f7424b2088f441331"
    )

    let schema: Int
    let bundleRelativePath: String
    let marker: Marker
    let manifestRelativePath: String
    let launcherRelativePath: String
    let interpreterRelativePath: String
    let pythonVersion: String
    let helperRuntimeArchitecture: String
    let intelBehavior: String
    let contentSha256: String
}

public struct StandaloneAppleCompanionHelperLocator: AppleCompanionHelperLocating, Sendable {
    private let bundleURL: URL

    public init(bundleURL: URL = Bundle.main.bundleURL) {
        self.bundleURL = bundleURL.standardizedFileURL
    }

    public func locate() -> AppleCompanionHelperAvailability {
        let contract = AppleCompanionStandaloneRuntimeContract.current
        let runtimeRoot = bundleURL
            .appendingPathComponent(contract.bundleRelativePath, isDirectory: true)
            .standardizedFileURL
        var rootInfo = stat()
        guard lstat(runtimeRoot.path, &rootInfo) == 0 else {
            return errno == ENOENT ? .notInstalled : .damaged
        }
        let resolvedBundle = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRuntimeRoot = runtimeRoot.resolvingSymlinksInPath().standardizedFileURL
        let contentsDirectory = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let helpersDirectory = contentsDirectory.appendingPathComponent("Helpers", isDirectory: true)
        guard contains(resolvedRuntimeRoot, within: resolvedBundle),
              secureDirectory(at: contentsDirectory),
              secureDirectory(at: helpersDirectory),
              secureDirectory(at: runtimeRoot) else {
            return .damaged
        }

        let requiredDirectories = [
            runtimeRoot.appendingPathComponent("bin", isDirectory: true),
            runtimeRoot.appendingPathComponent("python", isDirectory: true),
            runtimeRoot
                .appendingPathComponent("python", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true),
        ]
        guard requiredDirectories.allSatisfy({ secureDirectory(at: $0) }) else {
            return .damaged
        }

        let markerURL = runtimeRoot.appendingPathComponent(contract.marker.relativePath)
        let manifestURL = runtimeRoot.appendingPathComponent(contract.manifestRelativePath)
        let launcherURL = runtimeRoot.appendingPathComponent(contract.launcherRelativePath)
        let interpreterURL = runtimeRoot.appendingPathComponent(contract.interpreterRelativePath)
        guard secureFile(at: markerURL, within: runtimeRoot, executable: false, maximumSize: 1_024),
              secureFile(at: manifestURL, within: runtimeRoot, executable: false, maximumSize: 4_194_304),
              secureFile(at: launcherURL, within: runtimeRoot, executable: true),
              secureFile(at: interpreterURL, within: runtimeRoot, executable: true),
              (try? String(contentsOf: markerURL, encoding: .utf8)) == contract.marker.contents,
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                  AppleCompanionRuntimeManifest.self,
                  from: manifestData
              ),
              manifest.schema == contract.schema,
              manifest.pythonVersion == contract.pythonVersion,
              manifest.architecturePolicy.helperRuntime == contract.helperRuntimeArchitecture,
              manifest.architecturePolicy.intelBehavior == contract.intelBehavior,
              validSha256(manifest.contentSha256),
              manifest.contentSha256 == contract.contentSha256 else {
            return .damaged
        }

        return .installed(
            AppleCompanionHelperInstallation(
                executableURL: launcherURL,
                kind: .bundledStandalone(manifest)
            )
        )
    }

    private func secureDirectory(at url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
            && (info.st_mode & S_IFMT) == S_IFDIR
            && allowedOwner(info.st_uid)
            && (info.st_mode & 0o022) == 0
    }

    private func secureFile(
        at url: URL,
        within root: URL,
        executable: Bool,
        maximumSize: off_t = .max
    ) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        var info = stat()
        guard contains(resolved, within: resolvedRoot),
              lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              allowedOwner(info.st_uid),
              (info.st_mode & 0o022) == 0,
              info.st_size <= maximumSize else {
            return false
        }
        return !executable || (info.st_mode & 0o100) != 0
    }

    private func allowedOwner(_ owner: uid_t) -> Bool {
        owner == 0 || owner == getuid()
    }

    private func contains(_ child: URL, within parent: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }

    private func validSha256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
        }
    }
}

public struct DefaultAppleCompanionHelperLocator: AppleCompanionHelperLocating, Sendable {
    private let standaloneLocator: any AppleCompanionHelperLocating
    private let ownerInstalledLocator: any AppleCompanionHelperLocating
    private let supportsArm64Host: @Sendable () -> Bool

    public init(
        bundleURL: URL = Bundle.main.bundleURL,
        ownerInstalledRoot: URL = ApplicationSupportAppleCompanionHelperLocator.defaultRoot
    ) {
        standaloneLocator = StandaloneAppleCompanionHelperLocator(bundleURL: bundleURL)
        ownerInstalledLocator = ApplicationSupportAppleCompanionHelperLocator(
            root: ownerInstalledRoot
        )
        supportsArm64Host = Self.liveSupportsArm64Host
    }

    init(
        standaloneLocator: any AppleCompanionHelperLocating,
        ownerInstalledLocator: any AppleCompanionHelperLocating,
        supportsArm64Host: @escaping @Sendable () -> Bool
    ) {
        self.standaloneLocator = standaloneLocator
        self.ownerInstalledLocator = ownerInstalledLocator
        self.supportsArm64Host = supportsArm64Host
    }

    public func locate() -> AppleCompanionHelperAvailability {
        guard supportsArm64Host() else { return .unsupportedArchitecture }
        let standaloneAvailability = standaloneLocator.locate()
        guard standaloneAvailability == .notInstalled else {
            return standaloneAvailability
        }
        return ownerInstalledLocator.locate()
    }

    private static func liveSupportsArm64Host() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }
}
