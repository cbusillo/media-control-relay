import AppleCompanionSupport
import Foundation
import MediaControlCore

enum RemoteControlRuntimeFactory {
    @MainActor
    static func make() -> RemoteControlModel? {
        RemoteControlModel(runtimeProvider: AppleCompanionRemoteRuntimeProvider())
    }
}

private struct AppleCompanionRemoteRuntimeProvider: RemoteControlRuntimeProviding {
    func resolve() -> RemoteControlRuntimeResolution {
        let resolution = AppleCompanionRuntime.makeSession()
        switch resolution.availability {
        case .notInstalled:
            return RemoteControlRuntimeResolution(
                availability: .helperNotInstalled,
                actuator: nil
            )
        case .damaged:
            return RemoteControlRuntimeResolution(
                availability: .helperDamaged,
                actuator: nil
            )
        case .installed:
            guard let session = resolution.session,
                  let helperProcess = resolution.helperProcess else {
                return RemoteControlRuntimeResolution(
                    availability: .helperDamaged,
                    actuator: nil
                )
            }
            return RemoteControlRuntimeResolution(
                availability: .available,
                actuator: AppleCompanionRemoteActuator(
                    session: session,
                    helperProcess: helperProcess
                )
            )
        }
    }
}

private struct AppleCompanionRemoteActuator: RemoteControlActuating {
    let session: AppleCompanionSession
    let helperProcess: AppleCompanionHelperProcess

    func hasStoredCredential() async throws -> Bool {
        do {
            return try await session.storedSecret() != nil
        } catch let error as AppleCompanionKeychainError {
            throw map(error, operation: .read)
        } catch {
            throw RemoteControlFailure.credential(.read)
        }
    }

    func resume() async throws -> MediaRemoteTargetState {
        do {
            return map(try await session.resume())
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func discover() async throws -> [RemoteControlDiscoveryChoice] {
        do {
            return try await session.discover().map {
                RemoteControlDiscoveryChoice(id: $0.id, name: $0.name)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func beginPairing(targetID: String) async throws {
        do {
            _ = try await session.beginPairing(targetID: targetID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func finishPairing(pin: Int) async throws -> MediaRemoteTargetState {
        do {
            return map(try await session.finishPairing(pin: pin))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func execute(_ action: MediaRemoteAction) async throws -> MediaRemoteTargetState {
        do {
            return map(try await session.execute(action))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func stop() async {
        await session.stop()
    }

    func clearStoredCredential() async throws {
        do {
            try await session.clearStoredSecret()
        } catch let error as AppleCompanionKeychainError {
            throw map(error, operation: .remove)
        } catch {
            throw RemoteControlFailure.credential(.remove)
        }
    }

    func stopImmediately() {
        helperProcess.stop()
    }

    private func map(_ reply: AppleCompanionReply) -> MediaRemoteTargetState {
        switch reply.state {
        case .dormant: .unconfigured
        case .pairingRequired: .pairingRequired
        case .connecting: .connecting
        case .ready: .ready(capabilities: reply.capabilities)
        case .offline: .offline
        case .unsupported: .unsupported
        }
    }

    private func map(_ error: Error) -> RemoteControlFailure {
        guard let error = error as? AppleCompanionProtocolError else {
            return .unavailable
        }
        switch error {
        case .remote(.pairingFailed):
            return RemoteControlFailure.pairingFailed
        case .remote(.unsupportedAction):
            return RemoteControlFailure.unsupportedAction
        case .remote(.malformedRequest), .remote(.oversizedFrame):
            return RemoteControlFailure.unsupported
        case .remote(.offline), .connectionLost, .timeout:
            return RemoteControlFailure.offline
        case .remote(.pairingRequired):
            return RemoteControlFailure.pairingFailed
        case .remote(.unavailable), .malformedFrame, .oversizedFrame, .invalidMessage,
             .generationInvalidated, .unavailable:
            return RemoteControlFailure.unavailable
        }
    }

    private func map(
        _ error: AppleCompanionKeychainError,
        operation: RemoteControlCredentialOperation
    ) -> RemoteControlFailure {
        _ = error
        return .credential(operation)
    }
}
