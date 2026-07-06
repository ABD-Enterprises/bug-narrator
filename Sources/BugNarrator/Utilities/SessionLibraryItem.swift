import Foundation

protocol SessionLibraryItem: Identifiable {
    var id: UUID { get }
    var createdAt: Date { get }
    var searchIndexText: String { get }
    var isPendingTranscription: Bool { get }
}

struct SessionLibrarySnapshot<Item: SessionLibraryItem> {
    let filteredItems: [Item]
    let counts: [SessionLibraryDateFilter: Int]
    let emptyState: SessionLibraryEmptyState?
}
