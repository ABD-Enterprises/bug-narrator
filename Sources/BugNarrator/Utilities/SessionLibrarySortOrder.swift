import Foundation

enum SessionLibrarySortOrder: String, CaseIterable, Identifiable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"

    var id: String { rawValue }
}
