# Changelog

## Unreleased

- Windows session summaries no longer cut the lead sentence at a decimal point or a dot inside a word ("Version 1.2 crashed" summarised as "Version 1.").
- Windows screenshot geometry can map a selection piecewise into each monitor's native pixels (groundwork for per-monitor DPI capture; behaviour unchanged until the PerMonitorV2 switch in #1192).
