// Root layout — status bar, header, master, channel strip, footer.
import SwiftUI

struct ContentView: View {
    @State var store: TonegenStore
    let scopeL: SampleRingBuffer
    let scopeR: SampleRingBuffer
    let outputRate: OutputRate

    /// Which single channel the compact tabs show while unlinked. Pure view selection —
    /// the link flag itself lives in the store.
    @State private var soloChannel: ActiveChannel = .left
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        ZStack {
            Tokens.Color.bg.ignoresSafeArea()
            GrainOverlay().ignoresSafeArea()

            if hSizeClass == .regular {
                wideLayout
            } else {
                compactLayout
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Tab selection for the compact layout, derived from the store's link flag so
    /// both layouts stay in step when the size class changes mid-session.
    private var activeChannel: Binding<ActiveChannel> {
        Binding(
            get: { store.linked ? .linked : soloChannel },
            set: { newValue in
                if newValue == .linked {
                    store.linked = true
                } else {
                    soloChannel = newValue
                    store.linked = false
                }
            }
        )
    }

    // MARK: - Compact layout (iPhone, iPhone Duo outer display)

    private var compactLayout: some View {
        VStack(spacing: 0) {
            appHeader
            Divider().overlay(Tokens.Color.stroke)

            ScrollView {
                VStack(spacing: 0) {
                    // Master section
                    MasterSection(store: store, scopeL: scopeL, scopeR: scopeR)
                    Divider().overlay(Tokens.Color.stroke)

                    // Channel tabs
                    ChannelTabs(active: activeChannel)
                        .padding(.horizontal, Tokens.Spacing.panelPadH)
                        .padding(.vertical, Tokens.Spacing.sm)

                    // Channel strip
                    ChannelView(store: store, active: activeChannel.wrappedValue)
                }
            }

            Divider().overlay(Tokens.Color.stroke)
            appFooter
        }
    }

    // MARK: - Wide layout (iPad, iPhone Duo inner display)

    /// The two channel columns split at the horizontal centre, so on a book-style
    /// foldable the hinge falls on the divider rather than through a control.
    private var wideLayout: some View {
        VStack(spacing: 0) {
            appHeader
            Divider().overlay(Tokens.Color.stroke)

            MasterSection(store: store, scopeL: scopeL, scopeR: scopeR, showLinkButton: true)
            Divider().overlay(Tokens.Color.stroke)

            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        channelHeader("CH · L", color: Tokens.Color.channelL)
                        ChannelView(store: store, active: .left)
                    }
                }
                Divider().overlay(Tokens.Color.stroke)
                ScrollView {
                    VStack(spacing: 0) {
                        channelHeader("CH · R", color: Tokens.Color.channelR)
                        ChannelView(store: store, active: .right)
                    }
                }
            }

            Divider().overlay(Tokens.Color.stroke)
            appFooter
        }
    }

    // MARK: - Wide-layout channel column header

    private func channelHeader(_ title: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(Tokens.Font.label)
                .tracking(2)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.panelPadH)
        .padding(.vertical, Tokens.Spacing.sm)
        .background(Tokens.Color.panel)
        .overlay(
            Rectangle()
                .fill(color.opacity(0.4))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Header / footer

    private var appHeader: some View {
        HStack {
            Text("TONEGEN")
                .font(Tokens.Font.label)
                .tracking(2)
                .foregroundStyle(Tokens.Color.textSecondary)
            Spacer()
            SampleRateMenu(store: store, outputRate: outputRate)
        }
        .padding(.horizontal, Tokens.Spacing.panelPadH)
        .padding(.vertical, Tokens.Spacing.md)
    }

    private var appFooter: some View {
        HStack {
            Text(versionLabel)
                .font(Tokens.Font.readoutXs)
                .foregroundStyle(Tokens.Color.textGhost)
            Spacer()
            if store.playing {
                HStack(spacing: Tokens.Spacing.xs) {
                    Circle()
                        .fill(Tokens.Color.live)
                        .frame(width: 6, height: 6)
                        .shadow(color: Tokens.Color.live.opacity(0.7), radius: 3)
                    Text("GENERATING")
                        .font(Tokens.Font.readoutXs)
                        .foregroundStyle(Tokens.Color.live)
                }
                .transition(.opacity)
            } else if store.outputFailed {
                Text("AUDIO OUTPUT UNAVAILABLE")
                    .font(Tokens.Font.readoutXs)
                    .foregroundStyle(Tokens.Color.meterHot)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Tokens.Spacing.panelPadH)
        .padding(.vertical, Tokens.Spacing.md)
        .animation(.easeOut(duration: 0.3), value: store.playing)
        .animation(.easeOut(duration: 0.3), value: store.outputFailed)
    }

    private var versionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(v)"
    }
}

#if DEBUG
    #Preview {
        let engine = ToneEngine()
        let store = TonegenStore(bridge: engine.bridge)
        ContentView(
            store: store,
            scopeL: engine.scopeL,
            scopeR: engine.scopeR,
            outputRate: OutputRate(sampleRate: engine.sampleRate)
        )
    }
#endif
