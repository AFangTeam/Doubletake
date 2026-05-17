import SwiftUI

@main
struct TimelineApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: CompareDocument()) { config in
            CompareDocumentView(document: config.$document)
        }
        .commands {
            CompareCommands()
        }
    }
}
