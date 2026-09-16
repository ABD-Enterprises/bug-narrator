# Changelog

## Unreleased

- Windows: an issue whose primary field is null but carries an alias (e.g. `"title": null, "issueTitle": …`) or whose primary field is the wrong kind (`"confidence": "high"` beside `"score"`) is now read like macOS reads it, instead of failing the whole extraction or losing the field.
- Windows session summaries no longer cut the lead sentence at a decimal point or a dot inside a word ("Version 1.2 crashed" summarised as "Version 1.").
- Windows: a model reply carrying a non-finite timestamp or confidence ("NaN", "1e999") no longer crashes the session library; such values are treated as absent, and time labels render 0:00 for any non-finite value already saved.
- Windows screenshot geometry can map a selection piecewise into each monitor's native pixels (groundwork for per-monitor DPI capture; behaviour unchanged until the PerMonitorV2 switch in #1192).
