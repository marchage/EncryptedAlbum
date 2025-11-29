import SwiftUI

/// Small helper to provide a compatibility wrapper for the newer two-parameter
/// `onChange` API introduced in newer SDKs. Where the two-parameter form is
/// not available this uses a small view modifier that keeps the previous value
/// in state and calls the same callback.
@available(iOS, introduced: 13.0)
@available(macOS, introduced: 10.15)
public extension View {
    /// Call `perform` with (previous, new) when the environment supports it,
    /// otherwise emulate previous value tracking and call perform on value change.
    ///
    /// - Parameters:
    ///   - value: an Equatable value to observe
    ///   - perform: callback invoked with (oldValue, newValue)
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(of value: Value, perform: @escaping (Value, Value) -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            // Newer SDKs expose the two-parameter onChange
            self.onChange(of: value) { previous, newValue in
                perform(previous, newValue)
            }
        } else {
            // Older SDKs: emulate previous value tracking via a modifier using
            // the single-parameter onChange which is widely available.
            self.modifier(OnChangeCompatModifier(value: value, callback: perform))
        }
    }
}

private struct OnChangeCompatModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let callback: (Value, Value) -> Void

    @State private var previousValue: Value?

    func body(content: Content) -> some View {
        content
            .onAppear { previousValue = value }
            .onChange(of: value) { newValue in
                if let prev = previousValue {
                    callback(prev, newValue)
                }
                previousValue = newValue
            }
    }
}
