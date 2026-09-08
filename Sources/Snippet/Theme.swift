import SwiftUI
import AppKit

struct ThemePalette: Codable, Equatable {
    var name: String
    var background: UInt32
    var surface: UInt32
    var text: UInt32
    var secondary: UInt32
    var accent: UInt32
    var selection: UInt32
    var isDark: Bool {
        let r = Double((background >> 16) & 255), g = Double((background >> 8) & 255), b = Double(background & 255)
        return (r * 0.299 + g * 0.587 + b * 0.114) < 145
    }
    static let presets: [ThemePalette] = [
        .init(name: "Midnight", background: 0x13151C, surface: 0x20232D, text: 0xF1F0F7, secondary: 0x9D9CAA, accent: 0xA496FF, selection: 0x302B49),
        .init(name: "Paper", background: 0xF7F5F0, surface: 0xEAE6DF, text: 0x26232D, secondary: 0x6E6877, accent: 0x6C48C5, selection: 0xE5DCF7),
        .init(name: "Ocean", background: 0x0D202D, surface: 0x163345, text: 0xE4F5FF, secondary: 0x96B6C8, accent: 0x61D4F2, selection: 0x184559),
        .init(name: "Forest", background: 0x15231D, surface: 0x24372D, text: 0xEAF5E8, secondary: 0xA0B6A2, accent: 0xA1D88F, selection: 0x354C34),
        .init(name: "Rose", background: 0x291B25, surface: 0x3C2935, text: 0xFBEAF0, secondary: 0xC2A0B2, accent: 0xF2A5C6, selection: 0x563449)
    ]
}

final class ThemeStore: ObservableObject {
    @Published var palette: ThemePalette { didSet { save() } }
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        palette = defaults.data(forKey: "themePalette").flatMap { try? JSONDecoder().decode(ThemePalette.self, from: $0) } ?? ThemePalette.presets[0]
    }
    func save() { if let data = try? JSONEncoder().encode(palette) { defaults.set(data, forKey: "themePalette") } }
    var background: Color { Color(hex: palette.background) }
    var surface: Color { Color(hex: palette.surface) }
    var text: Color { Color(hex: palette.text) }
    var secondary: Color { Color(hex: palette.secondary) }
    var accent: Color { Color(hex: palette.accent) }
    var selection: Color { Color(hex: palette.selection) }
    func color(_ key: WritableKeyPath<ThemePalette, UInt32>) -> Binding<Color> {
        Binding(get: { Color(hex: self.palette[keyPath: key]) }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            let r = UInt32((rgb.redComponent * 255).rounded()), g = UInt32((rgb.greenComponent * 255).rounded()), b = UInt32((rgb.blueComponent * 255).rounded())
            self.palette[keyPath: key] = (r << 16) | (g << 8) | b
            self.palette.name = "Custom"
        })
    }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

struct PointerCursor: ViewModifier {
    @Environment(\.isEnabled) var enabled
    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active: if enabled { NSCursor.pointingHand.set() }
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}
extension View { func pointerCursor() -> some View { modifier(PointerCursor()) } }
struct PointerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.65 : 1).contentShape(Rectangle()).pointerCursor() }
}

struct LogoMark: View {
    var color: Color = Color(hex: 0xB4A4FF)
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.12).fill(color.opacity(0.5)).frame(width: s * 0.62, height: s * 0.72).offset(x: s * 0.12, y: -s * 0.1)
                RoundedRectangle(cornerRadius: s * 0.12).fill(color).frame(width: s * 0.62, height: s * 0.72).offset(x: -s * 0.08, y: s * 0.08)
                VStack(alignment: .leading, spacing: s * 0.08) {
                    Capsule().frame(width: s * 0.32, height: s * 0.055)
                    Capsule().frame(width: s * 0.24, height: s * 0.055)
                    Capsule().frame(width: s * 0.16, height: s * 0.055)
                }.foregroundStyle(Color(hex: 0x211A39)).offset(x: -s * 0.08, y: s * 0.08)
            }.frame(width: geo.size.width, height: geo.size.height)
        }.accessibilityHidden(true)
    }
}

final class ThemeColorPanel: NSObject {
    static let shared = ThemeColorPanel()
    var theme: ThemeStore?
    var key: WritableKeyPath<ThemePalette, UInt32>?
    func show(theme: ThemeStore, key: WritableKeyPath<ThemePalette, UInt32>, title: String) {
        self.theme = theme; self.key = key
        let panel = NSColorPanel.shared
        panel.title = title + " color"
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(Color(hex: theme.palette[keyPath: key]))
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)
    }
    @objc func changed(_ sender: NSColorPanel) {
        guard let theme, let key else { return }
        theme.color(key).wrappedValue = Color(nsColor: sender.color)
    }
}

struct ThemeSettingsView: View {
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { LogoMark(color: theme.accent).frame(width: 38, height: 38); VStack(alignment: .leading) { Text("Make it yours").font(.headline); Text("Colors update instantly and are saved automatically.").font(.caption).foregroundStyle(theme.secondary) } }
            HStack(spacing: 8) {
                ForEach(ThemePalette.presets, id: \.name) { preset in
                    Button { theme.palette = preset } label: {
                        VStack(spacing: 7) {
                            ZStack { RoundedRectangle(cornerRadius: 8).fill(Color(hex: preset.background)); HStack(spacing: 4) { Circle().fill(Color(hex: preset.accent)); Circle().fill(Color(hex: preset.text)); Circle().fill(Color(hex: preset.selection)) }.padding(12) }.frame(height: 42)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.palette.name == preset.name ? theme.accent : .clear, lineWidth: 2))
                            Text(preset.name).font(.system(size: 10))
                        }
                    }.buttonStyle(PointerButtonStyle())
                }
            }
            Text("\(theme.palette.name) colors").font(.subheadline.bold())
            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 14) {
                GridRow { colorControl("Background", key: \.background); colorControl("Surface", key: \.surface) }
                GridRow { colorControl("Text", key: \.text); colorControl("Muted text", key: \.secondary) }
                GridRow { colorControl("Accent", key: \.accent); colorControl("Selection", key: \.selection) }
            }
            HStack { Image(systemName: "magnifyingglass"); Text("A preview of your theme"); Spacer(); Text("↵").foregroundStyle(theme.accent) }.padding(14).background(theme.selection, in: RoundedRectangle(cornerRadius: 9))
            Button("Reset to Midnight") { theme.palette = ThemePalette.presets[0] }.buttonStyle(.bordered).pointerCursor()
        }
    }
    func colorControl(_ title: String, key: WritableKeyPath<ThemePalette, UInt32>) -> some View {
        Button { ThemeColorPanel.shared.show(theme: theme, key: key, title: title) } label: {
            HStack {
                Text(title).font(.system(size: 12))
                Spacer()
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: theme.palette[keyPath: key])).frame(width: 40, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.secondary.opacity(0.5), lineWidth: 1))
            }.frame(width: 220)
        }.buttonStyle(PointerButtonStyle()).help("Choose " + title.lowercased() + " color")
    }
}
