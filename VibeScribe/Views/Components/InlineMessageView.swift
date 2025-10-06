import SwiftUI
import AppKit

struct InlineMessageView: View {
    enum Style {
        case error
        case warning
        case info

        var iconName: String {
            switch self {
            case .error:
                return "exclamationmark.triangle.fill"
            case .warning:
                return "exclamationmark.circle.fill"
            case .info:
                return "info.circle.fill"
            }
        }

        var accentColor: Color {
            switch self {
            case .error:
                return Color(nsColor: .systemRed)
            case .warning:
                return Color(nsColor: .systemOrange)
            case .info:
                return Color(nsColor: .systemBlue)
            }
        }

        var accessibilityPrefix: String {
            switch self {
            case .error:
                return "Error"
            case .warning:
                return "Warning"
            case .info:
                return "Info"
            }
        }

        func backgroundColor() -> Color {
            let nsColor: NSColor
            switch self {
            case .error:
                nsColor = NSColor.systemRed
            case .warning:
                nsColor = NSColor.systemOrange
            case .info:
                nsColor = NSColor.systemBlue
            }
            return Color(nsColor: nsColor.withAlphaComponent(0.12))
        }

        func borderColor() -> Color {
            let nsColor: NSColor
            switch self {
            case .error:
                nsColor = NSColor.systemRed
            case .warning:
                nsColor = NSColor.systemOrange
            case .info:
                nsColor = NSColor.systemBlue
            }
            return Color(nsColor: nsColor.withAlphaComponent(0.3))
        }
    }

    let style: Style
    let message: String

    init(_ message: String, style: Style = .error) {
        self.message = message
        self.style = style
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: style.iconName)
                .imageScale(.medium)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(style.accentColor)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .labelColor))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(style.backgroundColor())
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(style.borderColor(), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(style.accessibilityPrefix): \(message)"))
    }
}

extension InlineMessageView {
    init(error: Error) {
        self.init(error.localizedDescription, style: .error)
    }
}
