import Foundation
import Security

protocol AppleCompanionRuntimeCodeSignatureVerifying: Sendable {
    func verify(bundleURL: URL) -> Bool
}

struct AppleCompanionRuntimeCodeSignatureVerifier:
    AppleCompanionRuntimeCodeSignatureVerifying,
    Sendable
{
    func verify(bundleURL: URL) -> Bool {
        guard let currentIdentity = signingIdentity(forCurrentProcess: true, code: nil),
              let requirement = requirement(for: currentIdentity),
              let staticCode = staticCode(at: bundleURL),
              SecStaticCodeCheckValidity(
                  staticCode,
                  SecCSFlags(
                      rawValue: kSecCSCheckAllArchitectures
                          | kSecCSCheckNestedCode
                          | kSecCSStrictValidate
                  ),
                  requirement
              ) == errSecSuccess,
              let bundleIdentity = signingIdentity(
                  forCurrentProcess: false,
                  code: staticCode
              ),
              bundleIdentity == currentIdentity else {
            return false
        }
        return true
    }

    private func requirement(for identity: SigningIdentity) -> SecRequirement? {
        let identifierCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: ".-")
        )
        let teamCharacters = CharacterSet.alphanumerics
        guard identity.identifier.unicodeScalars.allSatisfy(identifierCharacters.contains),
              identity.teamIdentifier.unicodeScalars.allSatisfy(teamCharacters.contains) else {
            return nil
        }
        let expression = """
        anchor apple generic and identifier "\(identity.identifier)" and \
        certificate leaf[subject.OU] = "\(identity.teamIdentifier)"
        """
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            expression as CFString,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess else {
            return nil
        }
        return requirement
    }

    private func staticCode(at bundleURL: URL) -> SecStaticCode? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess else {
            return nil
        }
        return staticCode
    }

    private func signingIdentity(
        forCurrentProcess: Bool,
        code: SecStaticCode?
    ) -> SigningIdentity? {
        let inspectedCode: SecStaticCode
        if forCurrentProcess {
            var currentCode: SecCode?
            guard SecCodeCopySelf(SecCSFlags(), &currentCode) == errSecSuccess,
                  let currentCode else {
                return nil
            }
            var currentStaticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(
                currentCode,
                SecCSFlags(),
                &currentStaticCode
            ) == errSecSuccess,
                  let currentStaticCode else {
                return nil
            }
            inspectedCode = currentStaticCode
        } else {
            guard let code else { return nil }
            inspectedCode = code
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            inspectedCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
              let information = signingInformation as? [CFString: Any],
              let identifier = information[kSecCodeInfoIdentifier] as? String,
              let teamIdentifier = information[kSecCodeInfoTeamIdentifier] as? String,
              !identifier.isEmpty,
              !teamIdentifier.isEmpty else {
            return nil
        }
        return SigningIdentity(identifier: identifier, teamIdentifier: teamIdentifier)
    }
}

private struct SigningIdentity: Equatable {
    let identifier: String
    let teamIdentifier: String
}
