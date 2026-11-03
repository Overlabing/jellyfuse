import SwiftUI

/// Navigation-bar treatment per screen kind. Touch platforms only: tvOS has no navigation bar, so these are no-ops there.
extension View {
    /// A tab's root screen draws its own header (billboard, title): the system bar would be an empty strip.
    func hidesNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// A pushed screen whose content starts under the bar (hero): transparent bar, back button only.
    func transparentNavigationBar() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Keyboard dismissal while scrolling results (touch).
    func dismissesKeyboardOnScroll() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.immediately)
        #else
        self
        #endif
    }
}
