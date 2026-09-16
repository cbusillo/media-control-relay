import AppKit

@MainActor
enum RelayMenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { @Sendable _ in

            let color = NSColor.black
            color.setFill()
            color.setStroke()

            let leftNode = NSBezierPath(
                ovalIn: NSRect(x: 0.9, y: 7.1, width: 3.8, height: 3.8)
            )
            leftNode.fill()

            let rightNode = NSBezierPath(
                ovalIn: NSRect(x: 13.3, y: 7.1, width: 3.8, height: 3.8)
            )
            rightNode.fill()

            let connector = NSBezierPath()
            connector.move(to: NSPoint(x: 5, y: 9))
            connector.line(to: NSPoint(x: 11.6, y: 9))
            connector.move(to: NSPoint(x: 11.6, y: 9))
            connector.line(to: NSPoint(x: 9.1, y: 11.5))
            connector.move(to: NSPoint(x: 11.6, y: 9))
            connector.line(to: NSPoint(x: 9.1, y: 6.5))
            connector.lineWidth = 1.8
            connector.lineCapStyle = .round
            connector.lineJoinStyle = .round
            connector.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }()
}
