import Foundation

@main
struct FixedMiniPlayerSwipeTest {
    static func main() {
        precondition(FixedMiniPlayerSwipe.action(for: CGSize(width: -70, height: 8)) == .next)
        precondition(FixedMiniPlayerSwipe.action(for: CGSize(width: 75, height: -5)) == .previous)
        precondition(FixedMiniPlayerSwipe.action(for: CGSize(width: 45, height: 0)) == nil)
        precondition(FixedMiniPlayerSwipe.action(for: CGSize(width: 60, height: 80)) == nil)
        print("Fixed mini player swipe behavior OK")
    }
}
