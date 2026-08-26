import AppKit
import Testing
@testable import Media_Control_Relay

@Suite("System route observer", .serialized)
@MainActor
struct SystemRouteObserverTests {
    @Test("Wake callback follows a real sleep and wake transition")
    func wakeCallbackFollowsLifecycleTransition() async {
        let center = NotificationCenter()
        let observer = SystemRouteObserver(workspaceNotificationCenter: center)
        let wakeEvents = AsyncStream<Void>.makeStream()
        var wakeCount = 0
        observer.onWake = {
            wakeCount += 1
            wakeEvents.continuation.yield()
        }

        observer.start()
        #expect(wakeCount == 0)

        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        var iterator = wakeEvents.stream.makeAsyncIterator()
        _ = await iterator.next()

        #expect(wakeCount == 1)
        wakeEvents.continuation.finish()
        observer.stop()
    }
}
