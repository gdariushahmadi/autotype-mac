import AppKit
import InputMethodKit

/// A stand-in for the text field an application provides.
///
/// It keeps a document and a marked (composing) range the way a real text
/// field does, so the self test can drive the controller through a whole
/// sentence and check what comes out.
final class MockTextInput: NSObject, IMKTextInput {

    /// Everything that has been committed to the field.
    private(set) var text = ""
    /// The text that is currently marked (being composed).
    private(set) var markedText = ""
    /// The range of the composing text inside `text`.
    private var marked = NSRange(location: NSNotFound, length: 0)
    /// The caret, as an index into `text`.
    private(set) var caret = 0

    // MARK: - IMKTextInput

    func insertText(_ string: Any!, replacementRange: NSRange) {
        let insertion = (string as? String) ?? ""
        let nsText = text as NSString

        var range = replacementRange
        if range.location == NSNotFound || range.location > nsText.length {
            if marked.location != NSNotFound {
                range = marked
            } else {
                range = NSRange(location: min(caret, nsText.length), length: 0)
            }
        }
        range.length = min(range.length, max(0, nsText.length - range.location))

        text = nsText.replacingCharacters(in: range, with: insertion)
        caret = range.location + insertion.utf16.count
        marked = NSRange(location: NSNotFound, length: 0)
        markedText = ""
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
        let composing = (string as? String) ?? ""
        let nsText = text as NSString

        var range = replacementRange
        if range.location == NSNotFound || range.location > nsText.length {
            if marked.location != NSNotFound {
                range = marked
            } else {
                range = NSRange(location: min(caret, nsText.length), length: 0)
            }
        }
        range.length = min(range.length, max(0, nsText.length - range.location))

        text = nsText.replacingCharacters(in: range, with: composing)
        if composing.isEmpty {
            marked = NSRange(location: NSNotFound, length: 0)
            markedText = ""
            caret = range.location
        } else {
            marked = NSRange(location: range.location, length: composing.utf16.count)
            markedText = composing
            caret = marked.location + selectionRange.location
        }
    }

    func selectedRange() -> NSRange {
        NSRange(location: caret, length: 0)
    }

    /// Deletes the character before the caret, the way a text field does when
    /// the input method passes the backspace key on.
    func deleteBackward() {
        let nsText = text as NSString
        guard caret > 0 else { return }
        text = nsText.replacingCharacters(in: NSRange(location: caret - 1, length: 1), with: "")
        caret -= 1
    }

    func markedRange() -> NSRange {
        marked
    }

    func attributedSubstring(from range: NSRange) -> NSAttributedString {
        NSAttributedString(string: (text as NSString).substring(with: range))
    }

    func length() -> Int {
        (text as NSString).length
    }

    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>?) -> Int {
        caret
    }

    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        [:]
    }

    func validAttributesForMarkedText() -> [Any]! {
        [NSAttributedString.Key.font]
    }

    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String) {}

    func selectMode(_ modeIdentifier: String) {}

    func supportsUnicode() -> Bool { true }

    func bundleIdentifier() -> String { "digital.autotype.selftest" }

    func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }

    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }

    func uniqueClientIdentifierString() -> String { "autotype-selftest" }

    func string(from range: NSRange, actualRange: NSRangePointer) -> String {
        (text as NSString).substring(with: range)
    }

    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer) -> NSRect {
        NSRect(x: 0, y: 0, width: 10, height: 20)
    }
}
