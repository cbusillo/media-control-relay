import Testing
@testable import MediaControlCore

@Suite("Media remote contract")
struct MediaRemoteContractTests {
    @Test("Actions expose every supported remote capability")
    func actionCapabilities() {
        let actions: [(MediaRemoteAction, MediaRemoteCapability)] = [
            (.navigate(.up), .navigation),
            (.navigate(.down), .navigation),
            (.navigate(.left), .navigation),
            (.navigate(.right), .navigation),
            (.select, .select),
            (.back, .back),
            (.home, .home),
            (.playPause, .playPause),
            (.previous, .previous),
            (.next, .next),
            (.seek(1), .relativeSeek),
            (.volume(-1), .relativeVolume),
        ]

        for (action, capability) in actions {
            #expect(action.requiredCapability == capability)
            #expect(action.requiredCapabilities == [capability])
        }
        #expect(MediaRemoteCapability.allCases.count == 9)
    }

    @Test("Ready state requires the matching capability")
    func readyStateRequirements() throws {
        let state = MediaRemoteTargetState.ready(
            capabilities: [.navigation, .select, .relativeSeek]
        )

        #expect(state.isReady)
        #expect(state.supports(.navigate(.left)))
        #expect(state.supports(.select))
        #expect(state.supports(.seek(-4)))
        #expect(!state.supports(.home))
        #expect(!state.supports(.volume(1)))
        #expect(state.capabilities == [.navigation, .select, .relativeSeek])
        try state.require(.navigate(.right))
        #expect(throws: MediaRemoteFailure.unsupportedAction(.home)) {
            try state.require(.home)
        }
    }

    @Test("Availability states produce explicit failures without fallback")
    func availabilityFailures() {
        let actions: [(MediaRemoteTargetState, MediaRemoteFailure)] = [
            (.unconfigured, .unconfigured),
            (.pairingRequired, .pairingRequired),
            (.connecting, .connecting),
            (.unsupported, .noFallback),
            (.offline, .offline),
        ]

        for (state, failure) in actions {
            #expect(!state.isReady)
            #expect(state.capabilities.isEmpty)
            #expect(throws: failure) {
                try state.require(.playPause)
            }
        }
    }

    @Test("Queue coalesces mixed signed seek directions")
    func mixedSeekDirectionsCoalesce() throws {
        var queue = MediaRemoteCommandQueue(
            capacity: 4,
            maximumSeekMagnitude: 20
        )

        try queue.enqueue(.seek(9))
        try queue.enqueue(.seek(-4))
        try queue.enqueue(.seek(-3))

        #expect(queue.pendingActions == [.seek(2)])
    }

    @Test("Queue coalesces mixed signed volume directions")
    func mixedVolumeDirectionsCoalesce() throws {
        var queue = MediaRemoteCommandQueue(
            capacity: 4,
            maximumVolumeMagnitude: 20
        )

        try queue.enqueue(.volume(-8))
        try queue.enqueue(.volume(5))
        try queue.enqueue(.volume(2))

        #expect(queue.pendingActions == [.volume(-1)])
    }

    @Test("Zero coalesced deltas cancel their pending segment")
    func zeroCancelsSegment() throws {
        var queue = MediaRemoteCommandQueue(capacity: 2)

        try queue.enqueue(.seek(5))
        try queue.enqueue(.seek(-5))
        #expect(queue.isEmpty)

        try queue.enqueue(.volume(4))
        try queue.enqueue(.volume(-4))
        #expect(queue.isEmpty)
    }

    @Test("Queue clamps individual and aggregate delta magnitudes")
    func deltaClamping() throws {
        var queue = MediaRemoteCommandQueue(
            capacity: 4,
            maximumSeekMagnitude: 7,
            maximumVolumeMagnitude: 3
        )

        try queue.enqueue(.seek(Int.max))
        try queue.enqueue(.seek(Int.max))
        try queue.enqueue(.volume(Int.min))
        try queue.enqueue(.volume(-3))

        #expect(queue.pendingActions == [.seek(7), .volume(-3)])
    }

    @Test("Queue rejects new segments at capacity but still coalesces")
    func queueCapacity() throws {
        var queue = MediaRemoteCommandQueue(capacity: 2)

        try queue.enqueue(.home)
        try queue.enqueue(.seek(1))
        #expect(throws: MediaRemoteFailure.queueFull) {
            try queue.enqueue(.next)
        }

        try queue.enqueue(.seek(2))
        #expect(queue.pendingActions == [.home, .seek(3)])
    }

    @Test("Discrete actions remain FIFO around coalesced segments")
    func discreteOrder() throws {
        var queue = MediaRemoteCommandQueue(capacity: 8)

        try queue.enqueue(.home)
        try queue.enqueue(.seek(3))
        try queue.enqueue(.seek(-1))
        try queue.enqueue(.select)
        try queue.enqueue(.volume(2))
        try queue.enqueue(.volume(1))
        try queue.enqueue(.back)

        #expect(queue.pendingActions == [
            .home,
            .seek(2),
            .select,
            .volume(3),
            .back,
        ])
        #expect(queue.dequeue() == .home)
        #expect(queue.dequeue() == .seek(2))
        #expect(queue.dequeue() == .select)
        #expect(queue.dequeue() == .volume(3))
        #expect(queue.dequeue() == .back)
        #expect(queue.dequeue() == nil)
    }

    @Test("Invalidation advances generation and drops stale work")
    func generationInvalidation() throws {
        var queue = MediaRemoteCommandQueue(capacity: 4)
        let originalGeneration = queue.generation

        try queue.enqueue(.home, generation: originalGeneration)
        try queue.enqueue(.seek(5), generation: originalGeneration)
        let newGeneration = queue.invalidate()

        #expect(newGeneration == originalGeneration + 1)
        #expect(queue.generation == newGeneration)
        #expect(queue.isEmpty)
        #expect(queue.dequeue() == nil)
        #expect(throws: MediaRemoteFailure.generationInvalidated) {
            try queue.enqueue(.back, generation: originalGeneration)
        }
        try queue.enqueue(.back, generation: newGeneration)
        #expect(queue.pendingActions == [.back])
    }
}
