import SwiftUI

/// Wadah tabel: kartu rounded berisi header (opsional) dan area baris yang
/// bisa digulir.
///
/// Kenapa `LazyVStack`, bukan `Table`: baris harus bisa dibulatkan sendiri
/// (highlight terpilih) dan kolomnya butuh lebar persis seperti desain.
/// `LazyVStack` tetap hanya mematerialisasi baris yang terlihat, jadi daftar
/// server cheesecake ribuan baris tidak membebani memory.
///
/// `freepnGlass` yang lama (Material + stroke putih) tidak lagi cocok dengan
/// palet gelap, jadi alias-nya diarahkan ke kartu baru. Tidak ada pemakai
/// lama yang tertinggal.
public struct TableCard<Header: View, Content: View>: View {
    private var header: Header
    private var content: Content
    private var padding: CGFloat

    public init(padding: CGFloat = 14, @ViewBuilder header: () -> Header,
                @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.header = header()
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if !(header is EmptyView) {
                Hairline().padding(.horizontal, padding)
            }
            content
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 14, y: 6)
    }
}

public extension TableCard where Header == EmptyView {
    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.init(padding: padding, header: { EmptyView() }, content: content)
    }
}

/// Satu baris tabel: tinggi tetap, padding seragam, sorot rounded saat dipilih.
public struct TableRowView<Content: View>: View {
    private var selected: Bool
    private var content: Content

    public init(selected: Bool = false, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Palette.cardRaised.opacity(0.85) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Palette.mint.opacity(0.35) : Color.clear,
                                  lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

/// Area baris yang bisa digulir, dengan baris dipisah garis rambut.
public struct TableRows<Content: View>: View {
    private var content: Content
    private var emptyMessage: LocalizedStringKey?

    public init(emptyMessage: LocalizedStringKey? = nil,
                @ViewBuilder content: () -> Content) {
        self.emptyMessage = emptyMessage
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                content
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            if let emptyMessage = emptyMessage {
                Text(emptyMessage)
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            }
        }
    }
}

/// Kartu "klik untuk lanjut" — dipakai untuk kartu Sumber/server yang punya
/// chevron di kanan.
public struct NavigableCard<Content: View>: View {
    private var action: () -> Void
    private var content: Content

    public init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                content
                Image(systemName: "chevron.right")
                    .font(.system(size: 12 * Theme.uiScale, weight: .semibold))
                    .foregroundColor(Palette.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.navyDeep.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Baris yang teksnya tidak boleh membelah jadi dua baris.
///
/// Kartu ringkasan (mis. "Subscription Sources") lebarnya terbatas kolom
/// dashboard; judul dua baris terlihat lebih rusak daripada judul satu baris
/// yang sedikit diperkecil.
public struct SingleLineLabel: View {
    private let text: Text
    private let tint: Color

    public init(_ text: Text, tint: Color = Palette.textPrimary) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        text
            .font(Theme.font(.callout))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

public extension View {
    /// Alias lama: dulu Material, sekarang permukaan kartu gelap.
    func freepnGlass(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        modifier(FreePNCard(radius: cornerRadius))
    }
}