import SwiftUI
import UIKit

enum MemoraStyle {
    static let background = Color(red: 0.045, green: 0.055, blue: 0.06)
    static let surface = Color(red: 0.095, green: 0.105, blue: 0.11)
    static let raised = Color(red: 0.135, green: 0.145, blue: 0.15)
    static let border = Color.white.opacity(0.12)
    static let line = Color.white.opacity(0.12)
    static let surfaceElevated = Color(red: 0.16, green: 0.17, blue: 0.18)
    static let muted = Color(red: 0.62, green: 0.65, blue: 0.69)
    static let cream = Color(red: 0.95, green: 0.91, blue: 0.86)

    static func title(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static let pagePadding: CGFloat = 16
    static let panelRadius: CGFloat = 16
    static let controlHeight: CGFloat = 50
}

struct MemoraBackground: View {
    var body: some View {
        MemoraStyle.background.ignoresSafeArea()
    }
}

struct MemoraHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(MemoraStyle.title(32))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(MemoraStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
}

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: MemoraStyle.panelRadius))
            .overlay(RoundedRectangle(cornerRadius: MemoraStyle.panelRadius).stroke(MemoraStyle.border))
    }
}

struct SectionHeading: View {
    let title: String
    var body: some View {
        Text(title)
            .font(MemoraStyle.title(22))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
    }
}

struct EmptyMemory: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        Panel {
            VStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundStyle(MemoraStyle.cream)
                Text(title)
                    .font(MemoraStyle.title(22))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(MemoraStyle.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }
}

struct MemoryRow: View {
    let symbol: String
    let title: String
    let detail: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 42, height: 42)
                .background(MemoraStyle.raised, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(MemoraStyle.muted)
            }
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(MemoraStyle.muted)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(MemoraStyle.muted)
        }
        .padding(.vertical, 6)
        .frame(minHeight: MemoraStyle.controlHeight)
        .contentShape(Rectangle())
    }
}

struct MemoryCard: View {
    let asset: MemoryAsset
    let image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12).fill(MemoraStyle.raised)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            } else {
                Image(systemName: asset.kind.symbol)
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(MemoraStyle.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if asset.kind == .video {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .padding(6).background(.black.opacity(0.65), in: Circle())
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(asset.name)
    }
}

struct StatTile: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 38, height: 38)
                .background(MemoraStyle.raised, in: RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(MemoraStyle.muted)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(MemoraStyle.border))
    }
}

struct MemoraButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(prominent ? MemoraStyle.background : .white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: MemoraStyle.controlHeight)
            .padding(.horizontal, 10)
            .background(prominent ? MemoraStyle.cream : MemoraStyle.raised,
                        in: RoundedRectangle(cornerRadius: 13))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension View {
    func memoraPage() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MemoraBackground())
            .preferredColorScheme(.dark)
            .tint(MemoraStyle.cream)
    }
}
