// L / R / Link tab selector for the channel section.
import SwiftUI

enum ActiveChannel: Equatable {
    case left, right, linked
}

struct ChannelTabs: View {
    @Binding var active: ActiveChannel

    var body: some View {
        HStack(spacing: 0) {
            tab(.left, label: "CH·L", color: Tokens.Color.channelL)
            Spacer(minLength: 0)
            tab(.right, label: "CH·R", color: Tokens.Color.channelR)
            Spacer(minLength: 0)
            tab(.linked, symbol: "link", color: Tokens.Color.linked)
        }
        .background(Tokens.Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.chip))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                .stroke(Tokens.Color.stroke, lineWidth: Tokens.Stroke.hairline)
        )
    }

    @ViewBuilder
    private func tabContent(label: String?, symbol: String?) -> some View {
        if let symbol {
            Image(systemName: symbol).font(Tokens.Font.labelLg)
        } else if let label {
            Text(label).font(Tokens.Font.labelLg).tracking(1)
        }
    }

    private func tab(
        _ channel: ActiveChannel,
        label: String? = nil,
        symbol: String? = nil,
        color: Color
    ) -> some View {
        let selected = active == channel
        let a11yLabel = switch channel {
        case .left: "Channel L"
        case .right: "Channel R"
        case .linked: "Link both channels"
        }
        return Button {
            active = channel
        } label: {
            tabContent(label: label, symbol: symbol)
                .foregroundStyle(selected ? color : Tokens.Color.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tokens.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                        .fill(selected ? Tokens.Color.panelActive : .clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                                .stroke(
                                    selected ? color.opacity(0.5) : .clear,
                                    lineWidth: Tokens.Stroke.hairline
                                )
                        )
                        .padding(2)
                )
                .expandedHitArea()
                .animation(.easeOut(duration: 0.15), value: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var active: ActiveChannel = .left
        ChannelTabs(active: $active)
            .padding()
            .background(Tokens.Color.bg)
    }
#endif
