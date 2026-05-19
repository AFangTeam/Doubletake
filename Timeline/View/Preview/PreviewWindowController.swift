import AppKit
import SwiftUI

/// 独立的预览窗口管理器。SwiftUI 的 `.sheet` / ZStack overlay 都会让"全屏"等
/// macOS 窗口行为受限，干脆走 AppKit：一个 NSWindow 装 NSHostingController，
/// 完全独立于主文档窗口，支持单独全屏 + 浮窗 (floating window level)。
/// 关闭后位置 / 大小持久化（UserDefaults），下次打开在同位置同大小。
@MainActor
final class PreviewWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?
    private var floating: Bool = false
    /// 用户关掉窗口时回调，CompareDocumentView 借此把 preview state 清空。
    var onClose: (() -> Void)?
    var isFloating: Bool { floating }

    private static let savedFrameKey = "previewWindow.frame"

    /// 显示 / 更新预览内容。若窗口已存在，**整个换掉 NSHostingController**，
    /// 而不是只替换 rootView —— 因为只换 rootView 会让 SwiftUI 的 keyboardShortcut
    /// 临时脱离 first-responder 链，结果就是翻图后按 F / ⌘⌫ 失灵。整换 hosting
    /// 干净地重建一遍 responder 树，再 makeFirstResponder 保证键盘热区在线。
    func present<Content: View>(_ content: Content, title: String) {
        let any = AnyView(content)
        if let w = window {
            // 替换 contentViewController 会让 AppKit 按新 view 的固有/最小尺寸重新算窗口大小，
            // SinglePreviewView 的 `.frame(minWidth: 900, minHeight: 600)` 会把窗口拽小到 900×600。
            // 翻图后窗口"突然变小"就是这个原因 —— 保存并还原 frame
            let savedFrame = w.frame
            let newHost = NSHostingController(rootView: any)
            newHost.sizingOptions = []
            w.contentViewController = newHost
            w.setFrame(savedFrame, display: false, animate: false)
            w.title = title
            if !w.isVisible { w.makeKeyAndOrderFront(nil) }
            w.orderFrontRegardless()
            self.hosting = newHost
            // 强制把 first responder 拉回新 content view，否则 SwiftUI 的
            // keyboardShortcut button 不在响应链里，F / ⌘⌫ / ← / → 都不触发
            DispatchQueue.main.async { [weak w, weak newHost] in
                guard let w, let newHost else { return }
                w.makeFirstResponder(newHost.view)
            }
            return
        }
        let host = NSHostingController(rootView: any)
        host.sizingOptions = []
        let w = NSWindow(contentViewController: host)
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .visible
        w.collectionBehavior = [.fullScreenPrimary]
        w.isReleasedWhenClosed = false
        w.delegate = self

        // 先放上次记录的位置 / 大小；没有记录则给个 1200x800 居中
        if let restored = Self.loadSavedFrame() {
            w.setFrame(restored, display: false)
        } else {
            w.setContentSize(NSSize(width: 1200, height: 800))
            w.center()
        }

        w.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak w, weak host] in
            guard let w, let host else { return }
            w.makeFirstResponder(host.view)
        }
        self.window = w
        self.hosting = host
    }

    func dismiss() {
        window?.close()
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func setFloating(_ value: Bool) {
        floating = value
        window?.level = value ? .floating : .normal
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowWillClose(_ notification: Notification) {
        saveFrame()
        onClose?()
        window = nil
        hosting = nil
        floating = false
    }

    // MARK: - Frame persistence

    private func saveFrame() {
        guard let w = window else { return }
        // 全屏 / 最小化时的 frame 不存，避免下次开窗诡异
        guard !w.styleMask.contains(.fullScreen), !w.isMiniaturized else { return }
        let s = NSStringFromRect(w.frame)
        UserDefaults.standard.set(s, forKey: Self.savedFrameKey)
    }

    private static func loadSavedFrame() -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: savedFrameKey) else { return nil }
        let rect = NSRectFromString(s)
        // 校验 rect 合法（屏幕可能被拔了）
        guard rect.width > 200, rect.height > 200 else { return nil }
        // 验证至少有屏幕能容纳它
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(rect) { return rect }
        }
        return nil
    }
}
