import SwiftUI

extension Binding where Value == Bool {
    /// Drives an alert or confirmation dialog from an optional payload.
    ///
    /// Dismissing the presentation (the system sets the binding to `false`) clears the payload,
    /// so the same alert can fire again with a new message.
    static func isPresented<Wrapped>(_ source: Binding<Wrapped?>) -> Binding<Bool> {
        Binding(
            get: { source.wrappedValue != nil },
            set: { presented in
                if !presented {
                    source.wrappedValue = nil
                }
            }
        )
    }
}
