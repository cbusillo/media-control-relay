import Testing
@testable import MediaControlCore

@Suite("System-defined volume key decoding")
struct SystemDefinedKeyDecoderTests {
    @Test("Volume keys decode on press and release", arguments: [
        (0, VolumeAction.up),
        (1, VolumeAction.down),
        (7, VolumeAction.mute),
    ])
    func volumeKeys(keyCode: Int, action: VolumeAction) {
        #expect(SystemDefinedKeyDecoder.decode(
            subtype: 8,
            data1: payload(keyCode: keyCode, state: 0xA),
            timestamp: 1
        ) == VolumeKeyEvent(
            action: action,
            phase: .pressed,
            isRepeat: false,
            timestamp: 1
        ))
        #expect(SystemDefinedKeyDecoder.decode(
            subtype: 8,
            data1: payload(keyCode: keyCode, state: 0xB),
            timestamp: 2
        ) == VolumeKeyEvent(
            action: action,
            phase: .released,
            isRepeat: false,
            timestamp: 2
        ))
    }

    @Test("Repeat is retained only for key presses")
    func repeatFlag() {
        #expect(SystemDefinedKeyDecoder.decode(
            subtype: 8,
            data1: payload(keyCode: 0, state: 0xA, isRepeat: true),
            timestamp: 1
        )?.isRepeat == true)
        #expect(SystemDefinedKeyDecoder.decode(
            subtype: 8,
            data1: payload(keyCode: 0, state: 0xB, isRepeat: true),
            timestamp: 1
        )?.isRepeat == false)
    }

    @Test("Unrelated system events are ignored")
    func unrelatedEvents() {
        #expect(SystemDefinedKeyDecoder.decode(
            subtype: 7,
            data1: payload(keyCode: 0, state: 0xA),
            timestamp: 1
        ) == nil)
        #expect(SystemDefinedKeyDecoder.decode(
            subtype: 8,
            data1: payload(keyCode: 16, state: 0xA),
            timestamp: 1
        ) == nil)
        #expect(SystemDefinedKeyDecoder.decode(
            subtype: 8,
            data1: payload(keyCode: 0, state: 0xC),
            timestamp: 1
        ) == nil)
    }

    private func payload(
        keyCode: Int,
        state: Int,
        isRepeat: Bool = false
    ) -> Int {
        (keyCode << 16) | (state << 8) | (isRepeat ? 1 : 0)
    }
}
