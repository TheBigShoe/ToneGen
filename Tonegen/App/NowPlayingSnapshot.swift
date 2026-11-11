// Now-playing metadata for a given transport state.
import MediaPlayer

/// What the system's now-playing surface should show for a given transport state.
struct NowPlayingSnapshot: Equatable {
    let info: [String: Any]
    let state: MPNowPlayingPlaybackState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state == rhs.state && NSDictionary(dictionary: lhs.info).isEqual(to: rhs.info)
    }

    /// Pure mapping from playback state to now-playing metadata, kept free of
    /// system singletons so it can be unit-tested.
    static func make(playing: Bool) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            info: [
                MPMediaItemPropertyTitle: "ToneGen",
                MPMediaItemPropertyArtist: "Test tone",
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
                MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
            ],
            state: playing ? .playing : .paused
        )
    }
}
