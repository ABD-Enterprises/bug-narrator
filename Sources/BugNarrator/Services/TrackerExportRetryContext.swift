import Foundation

/// The provider-specific naming the shared retry runner needs. Everything else
/// in the retry state machine is identical across providers, so only the display
/// name, destination, and the provider-prefixed log-event keys vary here.
struct TrackerExportRetryContext: Sendable {
    /// Human-facing provider name, e.g. "GitHub" / "Jira".
    let displayName: String
    let destination: ExportDestination
    /// Log event emitted on a successful create, e.g. "github_issue_exported".
    let exportedLogEvent: String
    /// Log event emitted on a failed create attempt, e.g. "github_export_failed".
    let failedLogEvent: String
    /// Log event emitted when reconciliation itself fails, e.g.
    /// "github_export_reconciliation_failed".
    let reconciliationFailedLogEvent: String
}
