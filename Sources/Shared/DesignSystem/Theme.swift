import SwiftUI

/// Design language (spec 022): system colours and materials, one tint, player colours as the
/// main saturated colour. Tint and palette are open decisions; these are placeholders.
public enum Theme {
    public static let tint = Color.accentColor
}

/// The fixed player palette (open decision in 022 — placeholder set).
public enum PlayerColour: String, CaseIterable, Sendable, Codable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

    public var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

public extension PlayerColour {
    /// Resolves a palette key from a read model; unknown keys fall back to gray.
    static func color(_ key: String) -> Color { (PlayerColour(rawValue: key) ?? .gray).color }

    /// The first palette colour nobody uses yet, for new players.
    static func nextUnused(_ used: [String]) -> PlayerColour {
        allCases.first { !used.contains($0.rawValue) } ?? allCases[used.count % allCases.count]
    }

    var title: String { rawValue.capitalized }
}

/// Elapsed time as a clock: "4:07" or "1:02:13".
public func clockText(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    let (h, m, sec) = (s / 3600, s / 60 % 60, s % 60)
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

/// Spoken form of an elapsed time for VoiceOver.
public func spokenDuration(_ seconds: TimeInterval) -> String {
    let f = DateComponentsFormatter()
    f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
    f.unitsStyle = .full
    return f.string(from: max(0, seconds)) ?? ""
}

public extension View {
    /// Inline navigation title on iOS; no-op elsewhere (keeps `swift build` on macOS working).
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Name-entry text field behaviour.
    func nameEntry() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words).autocorrectionDisabled().submitLabel(.done)
        #else
        autocorrectionDisabled()
        #endif
    }
}
