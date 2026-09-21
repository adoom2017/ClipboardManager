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
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
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
            } else if prominent {
                glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.12)),
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else if interactive {
                glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.20), lineWidth: 0.75)
            }
        }
    }

    @ViewBuilder
    func adaptiveGlassIconControl(tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                glassEffect(.regular.tint(tint).interactive(), in: .circle)
            } else {
                glassEffect(.regular.interactive(), in: .circle)
            }
        } else {
            background(.thinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.20), lineWidth: 0.75)
                }
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
