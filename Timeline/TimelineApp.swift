import SwiftUI

@main
struct TimelineApp: App {
    @State private var prefs = PreferencesStore()

    var body: some Scene {
        DocumentGroup(newDocument: CompareDocument()) { config in
            CompareDocumentView(document: config.$document)
                .environment(prefs)
        }
        .commands {
            CompareCommands()
            // ⌘, → 打开 Preferences 窗
            CommandGroup(replacing: .appSettings) {
                SettingsMenuItem()
            }
        }

        Window("Timeline 设置", id: "preferences") {
            PreferencesView()
                .environment(prefs)
        }
        .windowResizability(.contentSize)
    }
}

/// 标准 macOS 设置菜单项：⌘, 打开 Preferences 窗。
private struct SettingsMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("设置…") {
            openWindow(id: "preferences")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
