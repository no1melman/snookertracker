import SwiftUI

/// Shared player plate (spec 022): a colour plate plus the name. Archived players are greyed.
public struct PlayerPlate: View {
    let name: String
    let colour: Color
    let archived: Bool

    public init(name: String, colour: Color, archived: Bool = false) {
        self.name = name
        self.colour = colour
        self.archived = archived
    }

    public var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(archived ? Color.secondary : colour)
                .frame(width: 6)
                .frame(minHeight: 18)
                .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
                .foregroundStyle(archived ? .secondary : .primary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    VStack(alignment: .leading) {
        PlayerPlate(name: "Asher", colour: .blue)
        PlayerPlate(name: "Me", colour: .orange)
        PlayerPlate(name: "Old Pal", colour: .green, archived: true)
    }
    .padding()
}
