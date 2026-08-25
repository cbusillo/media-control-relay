import AppKit
import CoreGraphics
import MediaControlCore

private let systemDefinedEventTypeRawValue: UInt32 = 14

enum VolumeKeyMonitorError: Error {
    case eventTapUnavailable
    case runLoopSourceUnavailable
}

private final class VolumeKeyEventTapContext {
    let continuation: AsyncStream<VolumeKeyEvent>.Continuation
    var eventTap: CFMachPort?

    init(continuation: AsyncStream<VolumeKeyEvent>.Continuation) {
        self.continuation = continuation
    }
}

@MainActor
final class EventTapVolumeKeyMonitor {
    let events: AsyncStream<VolumeKeyEvent>

    private let context: VolumeKeyEventTapContext
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedContext: UnsafeMutableRawPointer?

    var isRunning: Bool {
        eventTap != nil
    }

    init() {
        let stream = AsyncStream<VolumeKeyEvent>.makeStream()
        events = stream.stream
        context = VolumeKeyEventTapContext(continuation: stream.continuation)
    }

    func start() throws {
        guard eventTap == nil else {
            return
        }

        let systemDefinedEventType = CGEventType(
            rawValue: systemDefinedEventTypeRawValue
        )!
        let eventMask = CGEventMask(1) << systemDefinedEventType.rawValue
        let contextPointer = Unmanaged.passRetained(context).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: volumeKeyEventTapCallback,
            userInfo: contextPointer
        ) else {
            Unmanaged<VolumeKeyEventTapContext>
                .fromOpaque(contextPointer)
                .release()
            throw VolumeKeyMonitorError.eventTapUnavailable
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            CFMachPortInvalidate(eventTap)
            Unmanaged<VolumeKeyEventTapContext>
                .fromOpaque(contextPointer)
                .release()
            throw VolumeKeyMonitorError.runLoopSourceUnavailable
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        retainedContext = contextPointer
        context.eventTap = eventTap
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        context.eventTap = nil
        runLoopSource = nil
        eventTap = nil
        if let retainedContext {
            Unmanaged<VolumeKeyEventTapContext>
                .fromOpaque(retainedContext)
                .release()
        }
        retainedContext = nil
    }
}

private func volumeKeyEventTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    precondition(Thread.isMainThread)
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let context = Unmanaged<VolumeKeyEventTapContext>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTap = context.eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type.rawValue == systemDefinedEventTypeRawValue,
          let appKitEvent = NSEvent(cgEvent: event),
          let decoded = SystemDefinedKeyDecoder.decode(
              subtype: Int(appKitEvent.subtype.rawValue),
              data1: appKitEvent.data1,
              timestamp: appKitEvent.timestamp
          ) else {
        return Unmanaged.passUnretained(event)
    }

    context.continuation.yield(decoded)
    return Unmanaged.passUnretained(event)
}
