import Foundation
import Testing
import MediaControlCore
@testable import UPnPMediaTarget

@Suite("UPnP RenderingControl volume capability")
struct UPnPMediaTargetVolumeCapabilityTests {
    @Test("Validates the ui2 range and step")
    func validatesRangeAndStep() throws {
        let capability = try UPnPMediaTargetVolumeCapability(
            minimumVolume: 5,
            maximumVolume: 95,
            step: 5
        )

        #expect(capability.minimumVolume == 5)
        #expect(capability.maximumVolume == 95)
        #expect(capability.step == 5)
        #expect(capability.contains(7))
        #expect(capability.accepts(10))
        #expect(capability.accepts(95))
        #expect(!capability.accepts(7))
    }

    @Test("Rejects unsafe or contradictory ranges")
    func rejectsUnsafeRanges() {
        let invalidRanges: [(Int, Int, Int)] = [
            (-1, 10, 1),
            (0, 65_536, 1),
            (10, 10, 1),
            (0, 10, 0),
            (0, 10, 11),
        ]

        for (minimum, maximum, step) in invalidRanges {
            #expect(throws: UPnPMediaTargetError.invalidVolumeCapability) {
                try UPnPMediaTargetVolumeCapability(
                    minimumVolume: minimum,
                    maximumVolume: maximum,
                    step: step
                )
            }
        }
    }

    @Test("Accepts the full ui2 boundary")
    func acceptsUI2Boundary() throws {
        let capability = try UPnPMediaTargetVolumeCapability(
            minimumVolume: 0,
            maximumVolume: Int(UInt16.max),
            step: 1
        )

        #expect(capability.accepts(Int(UInt16.max)))
    }
}

extension UPnPMediaTargetDescriptor {
    init(identity: MediaTargetIdentity, renderingControlURL: URL) {
        self.init(
            identity: identity,
            renderingControlURL: renderingControlURL,
            volumeCapability: try! UPnPMediaTargetVolumeCapability(
                minimumVolume: 0,
                maximumVolume: 100,
                step: 1
            )
        )
    }
}
