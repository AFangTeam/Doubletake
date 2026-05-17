import SwiftUI

struct CompareCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            EmptyView()
        }
    }
}
