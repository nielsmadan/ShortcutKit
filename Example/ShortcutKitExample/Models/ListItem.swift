import Foundation

struct ListItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}
