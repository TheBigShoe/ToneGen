// Pure mapping from playback state to now-playing metadata.
import MediaPlayer
import XCTest
@testable import Tonegen

final class NowPlayingSnapshotTests: XCTestCase {
    func testPlayingSnapshot() {
        let snap = NowPlayingSnapshot.make(playing: true)
        XCTAssertEqual(snap.state, .playing)
        XCTAssertEqual(snap.info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.0)
        XCTAssertEqual(snap.info[MPMediaItemPropertyTitle] as? String, "ToneGen")
        XCTAssertEqual(snap.info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, true)
    }

    func testPausedSnapshot() {
        let snap = NowPlayingSnapshot.make(playing: false)
        XCTAssertEqual(snap.state, .paused)
        XCTAssertEqual(snap.info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0.0)
        XCTAssertEqual(snap.info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, true)
    }

    func testSnapshotsDifferByPlayingState() {
        XCTAssertNotEqual(
            NowPlayingSnapshot.make(playing: true),
            NowPlayingSnapshot.make(playing: false)
        )
        XCTAssertEqual(
            NowPlayingSnapshot.make(playing: true),
            NowPlayingSnapshot.make(playing: true)
        )
    }
}
