import Foundation
import CoreGraphics

struct FloatingMiniPlayerDragState {
    enum Side: String {
        case left
        case right
    }

    struct SnapResult {
        let side: Side
        let position: CGPoint
    }

    private(set) var position: CGPoint
    private var fingerOffset: CGSize?

    init(position: CGPoint) {
        self.position = position
    }

    mutating func begin(at fingerLocation: CGPoint) {
        fingerOffset = CGSize(
            width: position.x - fingerLocation.x,
            height: position.y - fingerLocation.y
        )
    }

    mutating func move(to fingerLocation: CGPoint, within bounds: CGRect) {
        if fingerOffset == nil { begin(at: fingerLocation) }
        let offset = fingerOffset ?? .zero
        position = CGPoint(
            x: min(max(fingerLocation.x + offset.width, bounds.minX), bounds.maxX),
            y: min(max(fingerLocation.y + offset.height, bounds.minY), bounds.maxY)
        )
    }

    mutating func snap(to fingerLocation: CGPoint, within bounds: CGRect) -> SnapResult {
        move(to: fingerLocation, within: bounds)
        let side: Side = position.x < bounds.midX ? .left : .right
        position.x = side == .left ? bounds.minX : bounds.maxX
        return SnapResult(side: side, position: position)
    }
}
