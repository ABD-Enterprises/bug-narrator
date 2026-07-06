import Foundation

enum SessionDeletionStatusPresenter {
    static func status(deletedCount: Int) -> AppStatus? {
        guard deletedCount > 0 else {
            return nil
        }

        return .success(deletedCount == 1 ? "Deleted 1 session." : "Deleted \(deletedCount) sessions.")
    }
}
