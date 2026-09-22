import SwiftUI

extension View {
    /// A soft system-tinted backdrop that gives translucent surfaces something
    /// interesting to refract while remaining legible in both appearances.
    func glassBackdrop() -> some View {
        background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.14),
                        Color.clear,
                        Color(nsColor: .systemPurple).opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [Color.white.opacity(0.12), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 280
                )
            }
        }
    }

    func panelSectionSurface(
        cornerRadius: CGFloat = 14,
        tint: Color = Color(nsColor: .controlBackgroundColor),
        fillOpacity: Double = 0.48
    ) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(
            tint.opacity(fillOpacity),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(cornerRadius - 0.5, 0), style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.55)
        }
        .shadow(color: .black.opacity(0.15), radius: 18, y: 7)
    }

    private func glassSurfaceChrome(cornerRadius: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(cornerRadius - 0.5, 0), style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.55)
        }
        .shadow(color: .black.opacity(0.15), radius: 18, y: 7)
    }

    private func glassIconChrome() -> some View {
        overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
        }
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.55)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    @ViewBuilder
    func adaptiveGlassSurface(
        cornerRadius: CGFloat = 16,
        prominent: Bool = false,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            if prominent && interactive {
                glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.12)).interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .glassSurfaceChrome(cornerRadius: cornerRadius)
            } else if prominent {
                glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.12)),
                    in: .rect(cornerRadius: cornerRadius)
                )
                .glassSurfaceChrome(cornerRadius: cornerRadius)
            } else if interactive {
                glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                    .glassSurfaceChrome(cornerRadius: cornerRadius)
            } else {
                glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .glassSurfaceChrome(cornerRadius: cornerRadius)
            }
        } else {
            background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .glassSurfaceChrome(cornerRadius: cornerRadius)
        }
    }

    @ViewBuilder
    func adaptiveGlassIconControl(tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                glassEffect(.regular.tint(tint).interactive(), in: .circle)
                    .glassIconChrome()
            } else {
                glassEffect(.regular.interactive(), in: .circle)
                    .glassIconChrome()
            }
        } else {
            background(.regularMaterial, in: Circle())
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.20),
                    in: Circle()
                )
                .glassIconChrome()
        }
    }
}

struct GlassIconButton: View {
    let systemImage: String
    let helpText: String
    var tint: Color? = nil
    var role: ButtonRole? = nil
    var usesGlass = true
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if usesGlass {
            button
                .adaptiveGlassIconControl(tint: tint?.opacity(0.18))
        } else {
            button
        }
    }

    private var button: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}
