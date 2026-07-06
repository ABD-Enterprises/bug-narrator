import Foundation

struct SessionLibrarySnapshot<Item: SessionLibraryItem> {
    let filteredItems: [Item]
    let counts: [SessionLibraryDateFilter: Int]
    let emptyState: SessionLibraryEmptyState?
}
