import Foundation

public struct UPnPMediaTargetVolumeCapability: Equatable, Sendable {
    public static let ui2Maximum = Int(UInt16.max)

    public let minimumVolume: Int
    public let maximumVolume: Int
    public let step: Int

    public init(
        minimumVolume: Int,
        maximumVolume: Int,
        step: Int
    ) throws(UPnPMediaTargetError) {
        guard (0...Self.ui2Maximum).contains(minimumVolume),
              (0...Self.ui2Maximum).contains(maximumVolume),
              minimumVolume < maximumVolume else {
            throw .invalidVolumeCapability
        }
        let span = maximumVolume - minimumVolume
        guard step >= 1, step <= span else {
            throw .invalidVolumeCapability
        }

        self.minimumVolume = minimumVolume
        self.maximumVolume = maximumVolume
        self.step = step
    }

    public func accepts(_ volume: Int) -> Bool {
        guard contains(volume) else {
            return false
        }
        return volume == maximumVolume || (volume - minimumVolume).isMultiple(of: step)
    }

    public func contains(_ volume: Int) -> Bool {
        (minimumVolume...maximumVolume).contains(volume)
    }
}
