import Foundation
import Security

public enum AppleCompanionKeychainError: Error, Equatable, Sendable {
    case unavailable
    case invalidData
    case accessDenied
}

public protocol AppleCompanionKeychain: Sendable {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func delete(account: String) throws
}

protocol AppleCompanionKeychainSecurity: Sendable {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, result: Any?)
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

private struct SystemAppleCompanionKeychainSecurity: AppleCompanionKeychainSecurity {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, result: Any?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)
        return (status, result)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        SecItemAdd(attributes, nil)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

public struct SystemAppleCompanionKeychain: AppleCompanionKeychain, Sendable {
    private let service: String
    private let security: any AppleCompanionKeychainSecurity

    public init(service: String = "com.shinycomputers.media-control-relay.apple-companion") {
        self.service = service
        security = SystemAppleCompanionKeychainSecurity()
    }

    init(service: String, security: any AppleCompanionKeychainSecurity) {
        self.service = service
        self.security = security
    }

    public func read(account: String) throws -> Data? {
        if let data = try read(account: account, usesDataProtectionKeychain: false) {
            return data
        }
        let legacyData: Data?
        do {
            legacyData = try read(account: account, usesDataProtectionKeychain: true)
        } catch {
            return nil
        }
        guard let legacyData else {
            return nil
        }
        do {
            try write(legacyData, account: account)
        } catch {
            return legacyData
        }
        _ = security.delete(
            baseQuery(account: account, usesDataProtectionKeychain: true) as CFDictionary
        )
        return legacyData
    }

    private func read(
        account: String,
        usesDataProtectionKeychain: Bool
    ) throws -> Data? {
        var query = baseQuery(
            account: account,
            usesDataProtectionKeychain: usesDataProtectionKeychain
        )
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let response = security.copyMatching(query as CFDictionary)
        let status = response.status
        switch status {
        case errSecSuccess:
            guard let data = response.result as? Data else {
                throw AppleCompanionKeychainError.invalidData
            }
            return data
        case errSecItemNotFound:
            return nil
        case errSecAuthFailed, errSecInteractionNotAllowed:
            throw AppleCompanionKeychainError.accessDenied
        default:
            throw AppleCompanionKeychainError.unavailable
        }
    }

    public func write(_ data: Data, account: String) throws {
        let query = baseQuery(account: account, usesDataProtectionKeychain: false)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = security.update(query as CFDictionary, attributes: attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw map(updateStatus)
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = security.add(addQuery as CFDictionary)
        guard addStatus == errSecSuccess else {
            throw map(addStatus)
        }
    }

    public func delete(account: String) throws {
        let legacyStatus = security.delete(
            baseQuery(account: account, usesDataProtectionKeychain: true) as CFDictionary
        )
        guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound else {
            throw map(legacyStatus)
        }
        let currentStatus = security.delete(
            baseQuery(account: account, usesDataProtectionKeychain: false) as CFDictionary
        )
        guard currentStatus == errSecSuccess || currentStatus == errSecItemNotFound else {
            throw map(currentStatus)
        }
    }

    private func baseQuery(
        account: String,
        usesDataProtectionKeychain: Bool
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    private func map(_ status: OSStatus) -> AppleCompanionKeychainError {
        switch status {
        case errSecAuthFailed, errSecInteractionNotAllowed:
            return .accessDenied
        default:
            return .unavailable
        }
    }
}
