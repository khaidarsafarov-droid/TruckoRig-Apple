import SwiftUI
import UIKit

/// Stable ids for fields that the keyboard can cover. Also used as accessibility identifiers
/// where a UI test has to find the field.
enum KeyboardField {
    static let relayPaste = "addLoad.relayText"
    static let stopNote = "addLoad.notes"
    static let paycheckNotes = "paycheck.notes"
    static let givenName = "onboard.givenName"
    static let familyName = "onboard.familyName"
    static let goalTarget = "goal.target"
    static let penaltySummary = "penalty.summary"
    static let penaltyAmount = "penalty.amount"
}

/// Decides whether a focused field sits behind the keyboard, and how a sheet should react.
///
/// The view wrappers below call `scroll` when `@FocusState` changes. These functions stay free of
/// any view so the decision can be tested without hosting a screen.
enum KeyboardAvoidance {
    /// Gap kept between the field and the top of the keyboard.
    static let clearance: CGFloat = 12

    static func isHidden(
        fieldMinY: CGFloat,
        fieldMaxY: CGFloat,
        visibleMinY: CGFloat,
        keyboardTop: CGFloat
    ) -> Bool {
        fieldMaxY > keyboardTop - clearance || fieldMinY < visibleMinY
    }

    /// `.bottom` lifts a field the keyboard is covering. `.top` brings back a field that scrolled
    /// off the top. `nil` means the field is already in the band above the keyboard.
    static func scrollAnchor(
        fieldMinY: CGFloat,
        fieldMaxY: CGFloat,
        visibleMinY: CGFloat,
        keyboardTop: CGFloat
    ) -> UnitPoint? {
        if fieldMaxY > keyboardTop - clearance { return .bottom }
        if fieldMinY < visibleMinY { return .top }
        return nil
    }

    /// A return key that inserts a newline, or a pad with no return key, cannot dismiss the keyboard.
    static func needsDoneButton(returnInsertsNewline: Bool, hasReturnKey: Bool) -> Bool {
        returnInsertsNewline || !hasReturnKey
    }

    static func scroll<ID: Hashable>(_ proxy: ScrollViewProxy, to id: ID?, anchor: UnitPoint) {
        guard let id else { return }
        let perform = {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
        DispatchQueue.main.async(execute: perform)
        // The keyboard inset and a growing sheet both land after the focus change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: perform)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: perform)
    }
}

/// A medium sheet is shorter than the keyboard, so a focused field has nowhere to scroll until
/// the sheet grows.
enum KeyboardSheetDetent {
    static func resolved(resting: PresentationDetent, fieldFocused: Bool) -> PresentationDetent {
        fieldFocused ? .large : resting
    }
}

enum KeyboardDismissal {
    static func resign() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Keyboard bar with Done. Dismisses whichever field is first responder.
    func keyboardDone(perform: @escaping () -> Void = { KeyboardDismissal.resign() }) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("action.done", action: perform)
            }
        }
    }
}

/// Scroll view that brings the focused id above the keyboard and offers Done.
struct KeyboardAvoidingScroll<ID: Hashable, Content: View>: View {
    @FocusState.Binding var focus: ID?
    var anchor: UnitPoint = .center
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focus) { _, id in
                KeyboardAvoidance.scroll(proxy, to: id, anchor: anchor)
            }
        }
        .keyboardDone {
            focus = nil
            KeyboardDismissal.resign()
        }
    }
}

/// Form that already scrolls, with an explicit `scrollTo` for the focused id and a Done bar.
///
/// Use this instead of nesting a `ScrollView` around a `Form`. Does not ignore the keyboard safe area.
struct FocusedForm<ID: Hashable, Content: View>: View {
    @FocusState.Binding var focus: ID?
    var anchor: UnitPoint = .center
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                content()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focus) { _, id in
                KeyboardAvoidance.scroll(proxy, to: id, anchor: anchor)
            }
        }
        .keyboardDone {
            focus = nil
            KeyboardDismissal.resign()
        }
    }
}
