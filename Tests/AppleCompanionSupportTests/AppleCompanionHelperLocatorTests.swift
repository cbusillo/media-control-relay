import Darwin
import Foundation
import Testing
@testable import AppleCompanionSupport

@Suite("Apple Companion helper locator", .serialized)
struct AppleCompanionHelperLocatorTests {
    @Test("Absent installation remains a normal unavailable state")
    func absentInstallation() throws {
        let temporary = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }

        let root = temporary.appendingPathComponent("missing")
        let availability = ApplicationSupportAppleCompanionHelperLocator(root: root).locate()
        #expect(availability == .notInstalled)

        let runtime = AppleCompanionRuntime.makeSession(
            locator: FixedHelperLocator(availability: availability),
            keychain: LocatorFakeKeychain(),
            socketPath: temporary.appendingPathComponent("helper.sock").path
        )
        #expect(runtime.availability == .notInstalled)
        #expect(runtime.session == nil)
    }

    @Test("Secure content-addressed installation resolves its launcher")
    func secureInstallation() throws {
        let fixture = try makeInstallationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }

        let availability = ApplicationSupportAppleCompanionHelperLocator(
            root: fixture.installationRoot
        ).locate()
        guard case let .installed(installation) = availability else {
            Issue.record("Secure installation was not located")
            return
        }
        #expect(installation.manifest.digest == fixture.digest)
        #expect(installation.manifest.pythonVersion == "3.13.7")
        #expect(installation.executableURL.lastPathComponent == "apple-companion-helper")

        let runtime = AppleCompanionRuntime.makeSession(
            locator: FixedHelperLocator(availability: availability),
            keychain: LocatorFakeKeychain(),
            socketPath: fixture.temporaryRoot.appendingPathComponent("helper.sock").path
        )
        #expect(runtime.session != nil)
    }

    @Test("Mutated content fails closed")
    func mutatedContent() throws {
        let fixture = try makeInstallationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }
        let helper = fixture.versionRoot.appendingPathComponent("helper.py")
        try Data("changed".utf8).write(to: helper)
        try setPermissions(0o600, at: helper)

        #expect(
            ApplicationSupportAppleCompanionHelperLocator(root: fixture.installationRoot).locate()
                == .damaged
        )
    }

    @Test("Escaping current symlink and loose permissions fail closed")
    func unsafeInstallation() throws {
        let fixture = try makeInstallationFixture()
        defer { try? FileManager.default.removeItem(at: fixture.temporaryRoot) }
        let current = fixture.installationRoot.appendingPathComponent("current")
        try FileManager.default.removeItem(at: current)
        try FileManager.default.createSymbolicLink(
            at: current,
            withDestinationURL: fixture.temporaryRoot
        )
        #expect(
            ApplicationSupportAppleCompanionHelperLocator(root: fixture.installationRoot).locate()
                == .damaged
        )

        try FileManager.default.removeItem(at: current)
        try FileManager.default.createSymbolicLink(
            atPath: current.path,
            withDestinationPath: "versions/\(fixture.digest)"
        )
        try setPermissions(0o755, at: fixture.versionRoot)
        #expect(
            ApplicationSupportAppleCompanionHelperLocator(root: fixture.installationRoot).locate()
                == .damaged
        )
    }

    @Test("Shell and Swift compute the same source digest")
    func sharedDigest() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let helperRoot = repositoryRoot.appendingPathComponent("AppleCompanionHelper")
        let script = repositoryRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("apple-companion-helper.sh")
        let process = Process()
        let output = Pipe()
        process.executableURL = script
        process.arguments = ["digest"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let shellDigest = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let swiftDigest = try AppleCompanionHelperContent.digest(at: helperRoot)
        #expect(process.terminationStatus == 0)
        #expect(shellDigest == swiftDigest)
    }

    @Test("Overlong Unix socket paths fail before helper launch")
    func overlongSocketPath() async {
        let process = AppleCompanionHelperProcess(
            helperURL: URL(fileURLWithPath: "/usr/bin/true"),
            socketPath: "/tmp/" + String(repeating: "x", count: 120)
        )
        do {
            try await process.start(timeoutNanoseconds: 10_000_000)
            Issue.record("Overlong socket path unexpectedly launched")
        } catch let error {
            #expect(error == .unavailable)
        }
    }
}

private struct InstallationFixture {
    let temporaryRoot: URL
    let installationRoot: URL
    let versionRoot: URL
    let digest: String
}

private func makeInstallationFixture() throws -> InstallationFixture {
    let temporaryRoot = try makeTemporaryDirectory()
    let installationRoot = temporaryRoot.appendingPathComponent("AppleCompanionHelper")
    let versions = installationRoot.appendingPathComponent("versions")
    let pythonRoot = installationRoot.appendingPathComponent("python")
    let pending = versions.appendingPathComponent("pending")
    let bin = pending.appendingPathComponent("bin")
    try FileManager.default.createDirectory(
        at: bin,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    let venvBin = pending
        .appendingPathComponent("venv", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(
        at: venvBin,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.createDirectory(
        at: pythonRoot,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    for directory in [installationRoot, versions, pythonRoot, pending, bin, venvBin] {
        try setPermissions(0o700, at: directory)
    }
    let rootMarker = installationRoot.appendingPathComponent(
        ".media-control-relay-apple-companion-helper"
    )
    try Data("media-control-relay-apple-companion-helper-v1\n".utf8).write(to: rootMarker)
    try setPermissions(0o600, at: rootMarker)

    let content: [String: String] = [
        "helper.py": "fixture-helper",
        "pyproject.toml": "fixture-project",
        "uv.lock": "fixture-lock",
        ".python-version": "3.13.7\n",
    ]
    for (fileName, value) in content {
        let url = pending.appendingPathComponent(fileName)
        try Data(value.utf8).write(to: url)
        try setPermissions(0o600, at: url)
    }
    let launcher = bin.appendingPathComponent("apple-companion-helper")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: launcher)
    try setPermissions(0o700, at: launcher)
    let pythonExecutable = venvBin.appendingPathComponent("python3")
    try Data("fixture-python".utf8).write(to: pythonExecutable)
    try setPermissions(0o700, at: pythonExecutable)

    let digest = try AppleCompanionHelperContent.digest(at: pending)
    let versionRoot = versions.appendingPathComponent(digest)
    try FileManager.default.moveItem(at: pending, to: versionRoot)
    let manifest = AppleCompanionHelperManifest(
        digest: digest,
        pythonVersion: "3.13.7"
    )
    let manifestURL = versionRoot.appendingPathComponent("manifest.json")
    try JSONEncoder().encode(manifest).write(to: manifestURL)
    try setPermissions(0o600, at: manifestURL)
    try FileManager.default.createSymbolicLink(
        atPath: installationRoot.appendingPathComponent("current").path,
        withDestinationPath: "versions/\(digest)"
    )
    return InstallationFixture(
        temporaryRoot: temporaryRoot,
        installationRoot: installationRoot,
        versionRoot: versionRoot,
        digest: digest
    )
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    return url
}

private func setPermissions(_ permissions: Int, at url: URL) throws {
    try FileManager.default.setAttributes(
        [.posixPermissions: permissions],
        ofItemAtPath: url.path
    )
}

private struct FixedHelperLocator: AppleCompanionHelperLocating {
    let availability: AppleCompanionHelperAvailability

    func locate() -> AppleCompanionHelperAvailability {
        availability
    }
}

private final class LocatorFakeKeychain: AppleCompanionKeychain, @unchecked Sendable {
    func read(account: String) throws -> Data? { nil }
    func write(_ data: Data, account: String) throws {}
    func delete(account: String) throws {}
}
