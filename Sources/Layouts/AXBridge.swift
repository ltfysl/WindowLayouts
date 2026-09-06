import AppKit
import ApplicationServices
import Foundation

/// Thin wrapper over the Accessibility API used for both capture and restore.
enum AXBridge {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system permission prompt (once per app-bundle lifetime).
    static func promptForTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static let accessibilityPane = URL(string: "x-apple.systemsettings:com.apple.preference.security?Privacy_Accessibility")!

    static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        windows(ofPID: app.processIdentifier)
    }

    static func windows(ofPID pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &raw)
        guard result == .success else { return [] }
        return (raw as? [AXUIElement]) ?? []
    }

    static func title(of element: AXUIElement) -> String {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &raw) == .success,
              let title = raw as? String else { return "" }
        return title
    }

    static func isMinimized(_ element: AXUIElement) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &raw) == .success else {
            return false
        }
        return (raw as? NSNumber)?.boolValue ?? false
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let originRaw = copyValue(element, kAXPositionAttribute),
              let sizeRaw = copyValue(element, kAXSizeAttribute),
              let origin = pointValue(originRaw),
              let size = sizeValue(sizeRaw) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setFrame(_ element: AXUIElement, _ frame: CGRect) -> Bool {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let positionOK = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position) == .success
        let sizeOK = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) == .success
        return positionOK && sizeOK
    }

    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw
    }

    private static func pointValue(_ raw: CFTypeRef) -> CGPoint? {
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint()
        AXValueGetValue(value, .cgPoint, &point)
        return point
    }

    private static func sizeValue(_ raw: CFTypeRef) -> CGSize? {
        let value = raw as! AXValue
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize()
        AXValueGetValue(value, .cgSize, &size)
        return size
    }
}
