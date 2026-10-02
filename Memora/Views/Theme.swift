import SwiftUI
import UIKit

enum MemoraStyle {
    static let background = Color(red: 0.045, green: 0.055, blue: 0.06)
    static let surface = Color(red: 0.095, green: 0.105, blue: 0.11)
    static let raised = Color(red: 0.135, green: 0.145, blue: 0.15)
    static let border = Color.white.opacity(0.12)
    static let muted = Color(red: 0.62, green: 0.65, blue: 0.69)
    static let cream = Color(red: 0.95, green: 0.91, blue: 0.86)

    static func title(_ size: CGFloat = 39) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static let pagePadding: CGFloat = 20
    static let panelRadius: CGFloat = 18
    static let controlHeight: CGFloat = 52
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
            Text(title).font(MemoraStyle.title()).foregroundStyle(.white)
            Text(subtitle).font(.subheadline).foregroundStyle(MemoraStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }
}

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: MemoraStyle.panelRadius))
            .overlay(RoundedRectangle(cornerRadius: MemoraStyle.panelRadius).stroke(MemoraStyle.border))
    }
}

struct SectionHeading: View {
    let title: String
    var body: some View {
        Text(title)
            .font(MemoraStyle.title(25))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
    }
}

struct EmptyMemory: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        Panel {
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(MemoraStyle.cream)
                Text(title).font(MemoraStyle.title(24)).multilineTextAlignment(.center)
                Text(message).font(.subheadline).foregroundStyle(MemoraStyle.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }
}

struct MemoryRow: View {
    let symbol: String
    let title: String
    let detail: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 46, height: 46)
                .background(MemoraStyle.raised, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(MemoraStyle.muted)
            }
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.caption).foregroundStyle(MemoraStyle.muted) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(MemoraStyle.muted)
        }
        .padding(.vertical, 8)
        .frame(minHeight: MemoraStyle.controlHeight)
        .contentShape(Rectangle())
    }
}

struct MemoryCard: View {
    let asset: MemoryAsset
    let image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 13).fill(MemoraStyle.raised)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            } else {
                Image(systemName: asset.kind.symbol).font(.system(size: 31, weight: .ultraLight))
                    .foregroundStyle(MemoraStyle.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if asset.kind == .video {
                Image(systemName: "play.fill")
                    .padding(8).background(.black.opacity(0.6), in: Circle())
                    .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .accessibilityLabel(asset.name)
    }
}

struct StatTile: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.title3)
                .frame(width: 46, height: 46)
                .background(MemoraStyle.raised, in: RoundedRectangle(cornerRadius: 12))
            Text(title).font(.caption).foregroundStyle(MemoraStyle.muted)
            Text(value).font(.title2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MemoraStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(MemoraStyle.border))
    }
}

struct MemoraButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? MemoraStyle.background : .white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: MemoraStyle.controlHeight)
            .padding(.horizontal, 14)
            .background(prominent ? MemoraStyle.cream : MemoraStyle.raised,
                        in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension View {
    func memoraPage() -> some View {
        background(MemoraBackground())
            .preferredColorScheme(.dark)
            .tint(MemoraStyle.cream)
    }
}
