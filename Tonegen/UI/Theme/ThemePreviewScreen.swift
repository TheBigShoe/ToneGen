// Debug-only: renders every design token so regressions are immediately visible.
#if DEBUG
    import SwiftUI

    struct ThemePreviewScreen: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                    Text("DESIGN TOKENS")
                        .font(Tokens.Font.label)
                        .tracking(2)
                        .foregroundStyle(Tokens.Color.textSecondary)

                    colorSection
                    typographySection
                    spacingSection
                }
                .padding(Tokens.Spacing.panelPadH)
            }
            .background(Tokens.Color.bg)
        }

        private var colorSection: some View {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                sectionHeader("COLORS")
                colorRow("bg", Tokens.Color.bg, "0x0A0908")
                colorRow("surface", Tokens.Color.surface, "0x0C0A09")
                colorRow("panel", Tokens.Color.panel, "0x0E0C0A")
                colorRow("panelActive", Tokens.Color.panelActive, "0x16130F")
                colorRow("stroke", Tokens.Color.stroke, "0x2A2522")
                colorRow("strokeSoft", Tokens.Color.strokeSoft, "0x1F1C19")
                colorRow("textPrimary", Tokens.Color.textPrimary, "0xF5F0E8")
                colorRow("textSecondary", Tokens.Color.textSecondary, "0xBDB6AC")
                colorRow("textMuted", Tokens.Color.textMuted, "0x9B948B")
                colorRow("textGhost", Tokens.Color.textGhost, "0x81796F")
                colorRow("channelL", Tokens.Color.channelL, "0xFFB147")
                colorRow("channelR", Tokens.Color.channelR, "0x5DDEF4")
                colorRow("linked", Tokens.Color.linked, "0xD4D0C8")
                colorRow("meterNormal", Tokens.Color.meterNormal, "0x7DD3A0")
                colorRow("meterWarn", Tokens.Color.meterWarn, "0xFFB147")
                colorRow("meterHot", Tokens.Color.meterHot, "0xFF5A4A")
                colorRow("live", Tokens.Color.live, "0x10B981")
            }
        }

        private var typographySection: some View {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                sectionHeader("TYPOGRAPHY")
                Text("label (10 medium mono)").font(Tokens.Font.label)
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text("labelLg (11 medium)").font(Tokens.Font.labelLg)
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text("body (14)").font(Tokens.Font.body).foregroundStyle(Tokens.Color.textPrimary)
                Text("title (20 medium)").font(Tokens.Font.title)
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text("readoutXL (48)").font(Tokens.Font.readoutXL)
                    .foregroundStyle(Tokens.Color.channelL)
                Text("readoutLg (18)").font(Tokens.Font.readoutLg)
                    .foregroundStyle(Tokens.Color.channelL)
                Text("readoutMd (14)").font(Tokens.Font.readoutMd)
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text("readoutSm (11)").font(Tokens.Font.readoutSm)
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text("readoutXs (9)").font(Tokens.Font.readoutXs)
                    .foregroundStyle(Tokens.Color.textMuted)
            }
        }

        private var spacingSection: some View {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                sectionHeader("SPACING")
                ForEach([
                    ("xxs", Tokens.Spacing.xxs),
                    ("xs", Tokens.Spacing.xs),
                    ("sm", Tokens.Spacing.sm),
                    ("md", Tokens.Spacing.md),
                    ("lg", Tokens.Spacing.lg),
                    ("xl", Tokens.Spacing.xl),
                    ("xxl", Tokens.Spacing.xxl)
                ], id: \.0) { name, value in
                    HStack(spacing: Tokens.Spacing.sm) {
                        Rectangle()
                            .fill(Tokens.Color.channelL)
                            .frame(width: value, height: 10)
                        Text("\(name) = \(Int(value)) pt")
                            .font(Tokens.Font.readoutSm)
                            .foregroundStyle(Tokens.Color.textSecondary)
                    }
                }
            }
        }

        private func sectionHeader(_ text: String) -> some View {
            Text(text)
                .font(Tokens.Font.label)
                .tracking(2)
                .foregroundStyle(Tokens.Color.textMuted)
                .padding(.top, Tokens.Spacing.lg)
        }

        private func colorRow(_ name: String, _ color: Color, _ hex: String) -> some View {
            HStack(spacing: Tokens.Spacing.md) {
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(color)
                    .frame(width: 32, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .stroke(Tokens.Color.stroke, lineWidth: Tokens.Stroke.hairline)
                    )
                Text(name)
                    .font(Tokens.Font.readoutSm)
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .frame(width: 120, alignment: .leading)
                Text(hex)
                    .font(Tokens.Font.readoutSm)
                    .foregroundStyle(Tokens.Color.textMuted)
            }
        }
    }

    #Preview {
        ThemePreviewScreen()
    }
#endif
