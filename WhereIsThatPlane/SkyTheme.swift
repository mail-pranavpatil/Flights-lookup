import SwiftUI
import UIKit

/// Raw colour tokens from the UI spec. Views read them through `SkyAppearance`, not directly.
enum SkyPalette {
    static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255.0, green: Double((value >> 8) & 0xFF) / 255.0,
              blue: Double(value & 0xFF) / 255.0, opacity: opacity)
    }

    static let dayTop = hex(0xA7D4FF)
    static let dayBottom = hex(0xEAF6FF)
    static let dayText = hex(0x13264F)
    static let daySecondary = hex(0x45669D)
    static let dayAccent = hex(0x3478F6)

    static let nightTop = hex(0x071638)
    static let nightMiddle = hex(0x102C70)
    static let nightBottom = hex(0x070D26)
    static let nightCloud = hex(0x4058A0)
    static let nightText = hex(0xF7FAFF)
    static let nightSecondary = hex(0xB6C8F5)
    static let nightAccent = hex(0x65A8FF)
    static let nightCard = hex(0x10265A)
    static let nightCardBorder = hex(0x8FB9FF)

    static let violet = hex(0x6B5BD6)
    static let liveGreen = hex(0x36D98A)
    static let warningAmber = hex(0xF2B84B)
}

/// Visual theme chosen from local device time. Fixed bands, not sunrise/sunset.
enum SkyAppearance: CaseIterable, Equatable {
    case day, evening, night

    static func current(for date: Date, calendar: Calendar = .current) -> SkyAppearance {
        switch calendar.component(.hour, from: date) {
        case 7..<17: return .day
        case 17..<20: return .evening
        default: return .night
        }
    }

    static func greeting(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }

    var colorScheme: ColorScheme { self == .day ? .light : .dark }

    var background: [Color] {
        switch self {
        case .day: return [SkyPalette.dayTop, SkyPalette.dayBottom]
        case .evening: return [SkyPalette.hex(0x2E3A8C), SkyPalette.hex(0x4F4A9E), SkyPalette.hex(0x101E4E)]
        case .night: return [SkyPalette.nightTop, SkyPalette.nightMiddle, SkyPalette.nightBottom]
        }
    }
    var cloud: Color { self == .day ? .white.opacity(0.75) : SkyPalette.nightCloud.opacity(0.35) }

    var text: Color { self == .day ? SkyPalette.dayText : SkyPalette.nightText }
    var secondary: Color { self == .day ? SkyPalette.daySecondary : SkyPalette.nightSecondary }
    var accent: Color { self == .day ? SkyPalette.dayAccent : SkyPalette.nightAccent }

    var card: Color {
        switch self {
        case .day: return .white.opacity(0.8)
        case .evening: return SkyPalette.hex(0x1A2766, 0.82)
        case .night: return SkyPalette.nightCard.opacity(0.85)
        }
    }
    var cardBorder: Color { self == .day ? .white.opacity(0.7) : SkyPalette.nightCardBorder.opacity(0.2) }
    var shadow: Color { self == .day ? SkyPalette.hex(0x4A6C9B, 0.18) : .black.opacity(0.35) }

    /// Hero card: light sky blue by day (navy text), periwinkle dusk, navy/indigo night (white text).
    var hero: [Color] {
        switch self {
        case .day: return [SkyPalette.hex(0xDDF0FF), SkyPalette.hex(0xA7D4FF), SkyPalette.hex(0x7DBBFF)]
        case .evening: return [SkyPalette.hex(0x5B63C7), SkyPalette.hex(0x2B3A9E), SkyPalette.hex(0x16236A)]
        case .night: return [SkyPalette.hex(0x13306F), SkyPalette.hex(0x0B1A47), SkyPalette.hex(0x1B1650)]
        }
    }
    var heroTile: Color { self == .day ? .white.opacity(0.55) : .white.opacity(0.1) }
    var buttonFill: Color { self == .day ? SkyPalette.dayAccent : SkyPalette.nightText }
    var buttonText: Color { self == .day ? .white : SkyPalette.dayText }

    /// Sky activity card: blue → lilac, deep enough for white text.
    var activity: [Color] {
        self == .day ? [SkyPalette.hex(0x3E6FE0), SkyPalette.hex(0x6A5AE0)]
                     : [SkyPalette.hex(0x1C3A8A), SkyPalette.hex(0x3B2F8F)]
    }
}

/// The clock the theme and greeting follow. DEBUG builds accept `-SkyClockHour N` (screenshots).
enum SkyClock {
    static var now: Date {
        #if DEBUG
        if let hour = UserDefaults.standard.string(forKey: "SkyClockHour").flatMap(Int.init),
           let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) { return date }
        #endif
        return Date()
    }
}

private struct SkyAppearanceKey: EnvironmentKey {
    static let defaultValue = SkyAppearance.day
}

extension EnvironmentValues {
    var skyAppearance: SkyAppearance {
        get { self[SkyAppearanceKey.self] }
        set { self[SkyAppearanceKey.self] = newValue }
    }
}

// MARK: - Backgrounds

/// Full-screen sky. Each theme is a layer so a change cross-fades instead of snapping.
struct SkyBackground: View {
    @Environment(\.skyAppearance) private var sky

    var body: some View {
        ZStack {
            ForEach(SkyAppearance.allCases, id: \.self) { theme in
                ZStack {
                    LinearGradient(colors: theme.background, startPoint: .top, endPoint: .bottom)
                    CloudHaze(color: theme.cloud)
                    if theme != .day { Stars(count: theme == .night ? 45 : 18).opacity(theme == .night ? 1 : 0.5) }
                }
                .opacity(theme == sky ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Soft cloud forms built from radial gradients; no images, nothing behind small text.
struct CloudHaze: View {
    let color: Color

    var body: some View {
        ZStack {
            RadialGradient(colors: [color, .clear], center: UnitPoint(x: 0.1, y: 0.08), startRadius: 0, endRadius: 220)
            RadialGradient(colors: [color.opacity(0.8), .clear], center: UnitPoint(x: 0.95, y: 0.22), startRadius: 0, endRadius: 180)
            RadialGradient(colors: [color.opacity(0.6), .clear], center: UnitPoint(x: 0.4, y: 0.62), startRadius: 0, endRadius: 260)
        }
        .allowsHitTesting(false)
    }
}

/// Faint fixed star field (seeded, so it doesn't reshuffle on every render).
struct Stars: View {
    var count = 40

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x5EED
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt64(1) << 31)
            }
            for _ in 0..<count {
                let x = next() * size.width, y = next() * size.height * 0.55, d = 0.8 + next() * 1.6
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white.opacity(0.3 + next() * 0.4)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Airline logo

/// Official logo only for an airline identified by a verified route's ICAO code with a bundled asset
/// (see docs/airline-logo-sources.md); otherwise the neutral airplane glyph. Never recoloured.
struct AirlineLogo: View {
    let airline: Airline?
    var height: CGFloat = 26
    var maxWidth: CGFloat = 130
    @Environment(\.skyAppearance) private var sky

    var body: some View {
        if let icao = airline?.icao, let image = UIImage(named: "Airline_\(icao)") {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(maxWidth: maxWidth, maxHeight: height)
                .padding(.horizontal, 10).padding(.vertical, 7)
                // Neutral backing keeps every wordmark legible on day and night cards.
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("\(airline?.name ?? icao) logo")
        } else {
            Image(systemName: "airplane")
                .font(.system(size: height * 0.7, weight: .semibold))
                .foregroundStyle(sky.accent)
                .frame(width: height + 14, height: height + 14)
                .background(sky.heroTile, in: Circle())
                .accessibilityHidden(true)
        }
    }
}
