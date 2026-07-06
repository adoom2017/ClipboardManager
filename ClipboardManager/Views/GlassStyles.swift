import SwiftUI

extension View {
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
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.75)
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
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.75)
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
