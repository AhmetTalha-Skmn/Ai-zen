import SwiftUI
import AppKit

private final class WarningPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class Warnings {
    private var windows: [NSWindow] = []
    private var started: Date?
    private var shown: [Date] = []
    private var fullScreen = true
    // Küçük pencere başlık çubuğundan kapatılabilir; kapanan pencere görünür sayılmaz.
    var visible: Bool { windows.contains { $0.isVisible } }
    /// Ekranı kaplayan uyarı açıkken süre ölçülmez; ekran kilidi kapalıyken çıkan küçük pencere ölçümü durdurmaz.
    var blocksSampling: Bool { fullScreen && visible }
    func dismiss() { for window in windows { window.orderOut(nil) }; windows.removeAll(); started = nil }
    func expire(now: Date) { if let started, now.timeIntervalSince(started) >= 180 { dismiss() } }
    /// fullScreen: ekran kilidi açık (bütün ekranları kaplar). Kapalıyken tek, normal düzeyde, kapatılabilir pencere.
    func show(message: String, total: Int, target: Int, fullScreen: Bool, onPause: @escaping () -> Void, onStop: @escaping () -> Void) {
        let now = Date(); shown.removeAll { now.timeIntervalSince($0) >= 3600 }
        guard !visible, shown.count < 6 else { return }
        dismiss()
        shown.append(now); started = now; self.fullScreen = fullScreen
        if fullScreen {
            for screen in NSScreen.screens {
                let panel = WarningPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.isReleasedWhenClosed = false
                panel.contentView = NSHostingView(rootView: WarningScreen(message: message, total: total, target: target, fullScreen: true,
                    close: { [weak self] in self?.dismiss() }, pause: { [weak self] in self?.dismiss(); onPause() }, stop: { [weak self] in self?.dismiss(); onStop() }))
                panel.setFrame(screen.frame, display: true); panel.makeKeyAndOrderFront(nil); windows.append(panel)
            }
        } else {
            let panel = WarningPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 300), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Aizen · hatırlatma"
            panel.level = .normal; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: WarningScreen(message: message, total: total, target: target, fullScreen: false,
                close: { [weak self] in self?.dismiss() }, pause: { [weak self] in self?.dismiss(); onPause() }, stop: { [weak self] in self?.dismiss(); onStop() }))
            panel.center(); panel.orderFrontRegardless(); windows.append(panel)
        }
    }
}
private struct WarningScreen: View {
    let message: String
    let total: Int
    let target: Int
    let fullScreen: Bool
    var close: () -> Void
    var pause: () -> Void
    var stop: () -> Void
    var body: some View {
        if fullScreen {
            ZStack {
                Color(red: 0.04, green: 0.08, blue: 0.13).opacity(0.97)
                VStack(spacing: 24) {
                    Image(systemName: "timer").font(.system(size: 52)).foregroundStyle(.orange)
                    Text(message).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text("Bugün \(total) / \(target) dk").font(.title2)
                    HStack { Button("Çalışmaya dön", action: close).keyboardShortcut(.defaultAction); Button("5 dk mola", action: pause); Button("Acil durdur", action: stop) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    Text("Bu uyarı en geç 3 dakika içinde kapanır. Acil durdurma her zaman kullanılabilir.").font(.callout).foregroundStyle(.secondary)
                    Button("Kapat", action: close).keyboardShortcut(.cancelAction)
                }.padding(48).frame(maxWidth: 800).foregroundStyle(.white)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Label(message, systemImage: "timer").font(.title2.bold()).foregroundStyle(.orange)
                Text("Bugün \(total) / \(target) dk").font(.title3)
                ProgressView(value: Double(min(total, target)), total: Double(max(target, 1)))
                Text("Pencereyi kapatabilirsin; ölçüm sürüyor. Bir sonraki hatırlatma 45 dakika sonra gelir.").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack {
                    Button("Çalışmaya dön", action: close).keyboardShortcut(.defaultAction)
                    Button("5 dk mola", action: pause)
                    Spacer()
                    Button("Kapat", action: close).keyboardShortcut(.cancelAction)
                }
            }.padding(24).frame(width: 560, height: 300)
        }
    }
}
