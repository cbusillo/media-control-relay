import Foundation
import Testing
@testable import AppleCompanionSupport

@Suite("Standalone Apple Companion helper locator", .serialized)
struct StandaloneAppleCompanionHelperLocatorTests {
    @Test("Checked-in runtime contract matches Swift layout")
    func checkedInContractMatchesSwift() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let contractURL = repositoryRoot
            .appendingPathComponent("AppleCompanionHelper", isDirectory: true)
            .appendingPathComponent("runtime-contract.json")
        let contract = try JSONDecoder().decode(
            AppleCompanionStandaloneRuntimeContract.self,
            from: Data(contentsOf: contractURL)
        )

        #expect(contract == .current)
    }

    @Test("Valid standalone runtime resolves its launcher")
    func validRuntime() throws {
        let fixture = try makeStandaloneFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }

        let availability = standaloneLocator(bundleURL: fixture.bundleURL).locate()
        guard case let .installed(installation) = availability,
              case let .bundledStandalone(manifest) = installation.kind else {
            Issue.record("Standalone runtime was not located")
            return
        }
        #expect(installation.executableURL.lastPathComponent == "apple-companion-helper")
        #expect(installation.pythonVersion == "3.13.7")
        #expect(
            manifest.contentSha256
                == AppleCompanionStandaloneRuntimeContract.current.contentSha256
        )
    }

    @Test("Missing standalone runtime remains absent")
    func missingRuntime() throws {
        let temporaryRoot = try makeStandaloneTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let bundleURL = temporaryRoot.appendingPathComponent("Media Control Relay.app")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        #expect(
            standaloneLocator(bundleURL: bundleURL, signatureValid: false).locate()
                == .notInstalled
        )
    }

    @Test("Damaged standalone runtime fails closed")
    func damagedRuntime() throws {
        let fixture = try makeStandaloneFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }
        let marker = fixture.runtimeRoot.appendingPathComponent(
            AppleCompanionStandaloneRuntimeContract.current.marker.relativePath
        )
        try Data("wrong\n".utf8).write(to: marker)
        try setStandalonePermissions(0o644, at: marker)

        #expect(
            standaloneLocator(bundleURL: fixture.bundleURL).locate()
                == .damaged
        )
    }

    @Test("Mismatched runtime manifest fails closed")
    func mismatchedManifest() throws {
        let fixture = try makeStandaloneFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }
        let contract = AppleCompanionStandaloneRuntimeContract.current
        let manifest = AppleCompanionRuntimeManifest(
            schema: contract.schema,
            pythonVersion: contract.pythonVersion,
            architecturePolicy: .init(
                helperRuntime: "x86_64",
                intelBehavior: contract.intelBehavior
            ),
            contentSha256: contract.contentSha256
        )
        let manifestURL = fixture.runtimeRoot.appendingPathComponent(
            contract.manifestRelativePath
        )
        try JSONEncoder().encode(manifest).write(to: manifestURL)
        try setStandalonePermissions(0o644, at: manifestURL)

        #expect(
            standaloneLocator(bundleURL: fixture.bundleURL).locate()
                == .damaged
        )
    }

    @Test("Writable and escaping standalone nodes fail closed")
    func unsafeRuntime() throws {
        let fixture = try makeStandaloneFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }
        let launcher = fixture.runtimeRoot.appendingPathComponent(
            AppleCompanionStandaloneRuntimeContract.current.launcherRelativePath
        )
        try setStandalonePermissions(0o775, at: launcher)
        #expect(
            standaloneLocator(bundleURL: fixture.bundleURL).locate()
                == .damaged
        )

        try setStandalonePermissions(0o755, at: launcher)
        let interpreter = fixture.runtimeRoot.appendingPathComponent(
            AppleCompanionStandaloneRuntimeContract.current.interpreterRelativePath
        )
        try FileManager.default.removeItem(at: interpreter)
        try FileManager.default.createSymbolicLink(
            at: interpreter,
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/true")
        )
        #expect(
            standaloneLocator(bundleURL: fixture.bundleURL).locate()
                == .damaged
        )
    }

    @Test("Intermediate bundle symlink cannot escape containment")
    func intermediateSymlinkEscape() throws {
        let fixture = try makeStandaloneFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }
        let resourcesDirectory = fixture.runtimeRoot.deletingLastPathComponent()
        let outsideRuntime = fixture.temporaryRoot.appendingPathComponent(
            "AppleCompanionRuntime",
            isDirectory: true
        )
        try FileManager.default.moveItem(at: fixture.runtimeRoot, to: outsideRuntime)
        try FileManager.default.removeItem(at: resourcesDirectory)
        try FileManager.default.createSymbolicLink(
            at: resourcesDirectory,
            withDestinationURL: fixture.temporaryRoot
        )

        #expect(
            standaloneLocator(bundleURL: fixture.bundleURL).locate()
                == .damaged
        )
    }

    @Test("Invalid application signature fails closed")
    func invalidApplicationSignature() throws {
        let fixture = try makeStandaloneFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }

        #expect(
            standaloneLocator(bundleURL: fixture.bundleURL, signatureValid: false).locate()
                == .damaged
        )
    }

    @Test("Live signature verifier rejects an unsigned bundle")
    func unsignedBundleSignature() throws {
        let fixture = try makeStandaloneFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }

        #expect(
            !AppleCompanionRuntimeCodeSignatureVerifier().verify(bundleURL: fixture.bundleURL)
        )
    }

    @Test("Unsupported hosts stop before filesystem fallback")
    func unsupportedHost() {
        let locator = DefaultAppleCompanionHelperLocator(
            standaloneLocator: StandaloneFixedLocator(availability: .notInstalled),
            ownerInstalledLocator: StandaloneFixedLocator(availability: .notInstalled),
            supportsArm64Host: { false }
        )

        #expect(locator.locate() == .unsupportedArchitecture)
    }

    @Test("Default locator falls back only when bundle is absent")
    func fallbackPolicy() {
        let installation = AppleCompanionHelperInstallation(
            executableURL: URL(fileURLWithPath: "/fixture/helper"),
            kind: .ownerInstalled(
                AppleCompanionHelperManifest(
                    digest: String(repeating: "b", count: 64),
                    pythonVersion: "3.13.7"
                )
            )
        )
        let ownerAvailability = AppleCompanionHelperAvailability.installed(installation)
        let fallback = DefaultAppleCompanionHelperLocator(
            standaloneLocator: StandaloneFixedLocator(availability: .notInstalled),
            ownerInstalledLocator: StandaloneFixedLocator(availability: ownerAvailability),
            supportsArm64Host: { true }
        )
        let damaged = DefaultAppleCompanionHelperLocator(
            standaloneLocator: StandaloneFixedLocator(availability: .damaged),
            ownerInstalledLocator: StandaloneFixedLocator(availability: ownerAvailability),
            supportsArm64Host: { true }
        )

        #expect(fallback.locate() == ownerAvailability)
        #expect(damaged.locate() == .damaged)
    }
}

private struct StandaloneFixture {
    let temporaryRoot: URL
    let bundleURL: URL
    let runtimeRoot: URL
}

private func makeStandaloneFixture() throws -> StandaloneFixture {
    let temporaryRoot = try makeStandaloneTemporaryDirectory()
    let bundleURL = temporaryRoot.appendingPathComponent("Media Control Relay.app")
    let contract = AppleCompanionStandaloneRuntimeContract.current
    let runtimeRoot = bundleURL.appendingPathComponent(
        contract.bundleRelativePath,
        isDirectory: true
    )
    let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
    let resources = contents.appendingPathComponent("Resources", isDirectory: true)
    let bin = runtimeRoot.appendingPathComponent("bin", isDirectory: true)
    let pythonBin = runtimeRoot
        .appendingPathComponent("python", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
    for directory in [bundleURL, contents, resources, runtimeRoot, bin, pythonBin] {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try setStandalonePermissions(0o755, at: directory)
    }

    let marker = runtimeRoot.appendingPathComponent(contract.marker.relativePath)
    try Data(contract.marker.contents.utf8).write(to: marker)
    try setStandalonePermissions(0o644, at: marker)
    let manifest = AppleCompanionRuntimeManifest(
        schema: contract.schema,
        pythonVersion: contract.pythonVersion,
        architecturePolicy: .init(
            helperRuntime: contract.helperRuntimeArchitecture,
            intelBehavior: contract.intelBehavior
        ),
        contentSha256: contract.contentSha256
    )
    let manifestURL = runtimeRoot.appendingPathComponent(contract.manifestRelativePath)
    try JSONEncoder().encode(manifest).write(to: manifestURL)
    try setStandalonePermissions(0o644, at: manifestURL)
    for relativePath in [contract.launcherRelativePath, contract.interpreterRelativePath] {
        let executable = runtimeRoot.appendingPathComponent(relativePath)
        try Data("fixture executable".utf8).write(to: executable)
        try setStandalonePermissions(0o755, at: executable)
    }
    return StandaloneFixture(
        temporaryRoot: temporaryRoot,
        bundleURL: bundleURL,
        runtimeRoot: runtimeRoot
    )
}

private func makeStandaloneTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    return url
}

private func setStandalonePermissions(_ permissions: Int, at url: URL) throws {
    try FileManager.default.setAttributes(
        [.posixPermissions: permissions],
        ofItemAtPath: url.path
    )
}

private func standaloneLocator(
    bundleURL: URL,
    signatureValid: Bool = true
) -> StandaloneAppleCompanionHelperLocator {
    StandaloneAppleCompanionHelperLocator(
        bundleURL: bundleURL,
        codeSignatureVerifier: StandaloneFixedSignatureVerifier(result: signatureValid)
    )
}

private struct StandaloneFixedSignatureVerifier:
    AppleCompanionRuntimeCodeSignatureVerifying
{
    let result: Bool

    func verify(bundleURL _: URL) -> Bool {
        result
    }
}

private struct StandaloneFixedLocator: AppleCompanionHelperLocating {
    let availability: AppleCompanionHelperAvailability

    func locate() -> AppleCompanionHelperAvailability {
        availability
    }
}
