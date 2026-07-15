import Foundation

@main
struct FloatingMiniPlayerDragTest {
    static func main() {
        let bounds = CGRect(x: 50, y: 50, width: 200, height: 400)
        var state = FloatingMiniPlayerDragState(position: CGPoint(x: 250, y: 300))

        state.begin(at: CGPoint(x: 240, y: 290))
        state.move(to: CGPoint(x: 170, y: 200), within: bounds)
        precondition(state.position == CGPoint(x: 180, y: 210))

        state.move(to: CGPoint(x: 110, y: 130), within: bounds)
        precondition(state.position == CGPoint(x: 120, y: 140))

        state.move(to: CGPoint(x: 10, y: 590), within: bounds)
        precondition(state.position == CGPoint(x: 50, y: 450))

        let result = state.snap(to: CGPoint(x: 200, y: 190), within: bounds)
        precondition(result.side == .right)
        precondition(result.position == CGPoint(x: 250, y: 200))

        print("Floating mini player drag behavior OK")
    }
}
