import SwiftUI

/// Runs a command; a failure lands in `message`, which `errorAlert` shows.
@MainActor public func attempt(_ message: Binding<String?>, _ command: () throws -> Void) {
    do { try command() } catch { message.wrappedValue = error.localizedDescription }
}

public extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Can't do that", isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

