// Lock-screen and Control Center integration.
import MediaPlayer

/// Registers remote commands and publishes now-playing info so the tone can be
/// controlled from the lock screen, Control Center and headset buttons.
@MainActor
final class NowPlayingController {
    private let store: TonegenStore
    private var targets: [(MPRemoteCommand, Any)] = []

    init(store: TonegenStore) {
        self.store = store
        registerCommands()
        refresh()
    }

    /// Publishes the store's current playing state. Call whenever it changes.
    func refresh() {
        let snapshot = NowPlayingSnapshot.make(playing: store.playing)
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = snapshot.info
        center.playbackState = snapshot.state
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand) { $0.set(true) }
        add(center.pauseCommand) { $0.set(false) }
        add(center.togglePlayPauseCommand) { $0.set(!$0.store.playing) }

        // A tone generator has no timeline or queue; hide those controls.
        let unsupported: [MPRemoteCommand] = [
            center.nextTrackCommand, center.previousTrackCommand,
            center.seekForwardCommand, center.seekBackwardCommand,
            center.skipForwardCommand, center.skipBackwardCommand,
            center.changePlaybackPositionCommand
        ]
        for command in unsupported {
            command.isEnabled = false
        }
    }

    private func add(
        _ command: MPRemoteCommand,
        _ action: @escaping @MainActor (NowPlayingController) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        // Delivery thread is not documented, so hop to main explicitly rather than
        // trusting assumeIsolated alone.
        let target = command.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let run: () -> MPRemoteCommandHandlerStatus = {
                MainActor.assumeIsolated { action(self) }
            }
            return Thread.isMainThread ? run() : DispatchQueue.main.sync(execute: run)
        }
        targets.append((command, target))
    }

    /// Applies a remote play/pause request and reports whether it took effect.
    private func set(_ on: Bool) -> MPRemoteCommandHandlerStatus {
        store.setPlaying(on)
        refresh()
        return store.playing == on ? .success : .commandFailed
    }
}
