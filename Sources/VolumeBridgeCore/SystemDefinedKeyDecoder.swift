import Foundation

public enum SystemDefinedKeyDecoder {
    public static let auxiliaryControlButtonsSubtype = 8

    public static func decode(
        subtype: Int,
        data1: Int,
        timestamp: TimeInterval
    ) -> VolumeKeyEvent? {
        guard subtype == auxiliaryControlButtonsSubtype else {
            return nil
        }

        let payload = UInt32(truncatingIfNeeded: data1)
        let keyCode = Int((payload >> 16) & 0xFFFF)
        let keyState = Int((payload >> 8) & 0xFF)
        let isRepeat = payload & 0x1 != 0

        let action: VolumeAction
        switch keyCode {
        case 0:
            action = .up
        case 1:
            action = .down
        case 7:
            action = .mute
        default:
            return nil
        }

        let phase: VolumeKeyPhase
        switch keyState {
        case 0xA:
            phase = .pressed
        case 0xB:
            phase = .released
        default:
            return nil
        }

        return VolumeKeyEvent(
            action: action,
            phase: phase,
            isRepeat: phase == .pressed && isRepeat,
            timestamp: timestamp
        )
    }
}
