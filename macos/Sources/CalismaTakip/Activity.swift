import AppKit
import ApplicationServices
import TakipCore

enum Activity {
    static var permission: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private static func text(_ element: AXUIElement, _ name: String) -> String {
        if let url = attribute(element, name) as? URL { return url.absoluteString }
        return attribute(element, name) as? String ?? ""
    }
    private static func host(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.contains(" "), clean.count < 4096 else { return "" }
        let candidate = clean.contains("://") ? clean : "https://" + clean
        guard let url = URLComponents(string: candidate), ["http", "https"].contains(url.scheme ?? ""), let host = url.host, host.contains(".") || host == "localhost" else { return "" }
        return host.lowercased()
    }
    static func sample() -> Sample? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var title = "", domain = ""
        if permission {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.25)
            if let raw = attribute(element, "AXFocusedWindow"), CFGetTypeID(raw) == AXUIElementGetTypeID() {
                let window = unsafeBitCast(raw, to: AXUIElement.self)
                title = String(text(window, "AXTitle").prefix(500))
                let browsers = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox", "com.operasoftware.Opera"]
                if browsers.contains(app.bundleIdentifier ?? "") {
                    domain = host(text(window, "AXDocument"))
                    if domain.isEmpty { domain = host(text(window, "AXURL")) }
                    if domain.isEmpty {
                        var queue: [AXUIElement] = [window]; var index = 0
                        let deadline = Date().addingTimeInterval(0.5)
                        while index < queue.count && index < 250 && Date() < deadline {
                            let node = queue[index]; index += 1
                            if text(node, "AXRole") == "AXTextField" {
                                let label = (text(node, "AXIdentifier") + " " + text(node, "AXDescription")).lowercased()
                                if ["address", "adres", "url", "omnibox", "location"].contains(where: { label.contains($0) }) {
                                    domain = host(text(node, "AXValue")); if !domain.isEmpty { break }
                                }
                            }
                            if queue.count < 250, let children = attribute(node, "AXChildren") as? [AXUIElement] { queue += children.prefix(250 - queue.count) }
                        }
                    }
                }
            }
        }
        return Sample(app: app.localizedName ?? "Bilinmeyen", bundle: app.bundleIdentifier ?? "", title: title, domain: domain, idleSeconds: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0) ?? .null))
    }
}
