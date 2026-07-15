import Foundation

@main
struct MiniPlayerLyricsTest {
    static func main() {
        let synced = [
            LyricLine(id: 0, time: 2, text: "第一句"),
            LyricLine(id: 1, time: 8, text: "第二句")
        ]
        precondition(
            LyricsParser.activeLine(in: synced, at: 1, duration: 20)?.text == "第一句"
        )
        precondition(
            LyricsParser.activeLine(in: synced, at: 9, duration: 20)?.text == "第二句"
        )

        let plain = [
            LyricLine(id: 0, time: nil, text: "甲"),
            LyricLine(id: 1, time: nil, text: "乙"),
            LyricLine(id: 2, time: nil, text: "丙")
        ]
        precondition(
            LyricsParser.activeLine(in: plain, at: 0, duration: 90)?.text == "甲"
        )
        precondition(
            LyricsParser.activeLine(in: plain, at: 45, duration: 90)?.text == "乙"
        )
        precondition(
            LyricsParser.activeLine(in: plain, at: 90, duration: 90)?.text == "丙"
        )

        print("Mini player lyric rotation OK")
    }
}
