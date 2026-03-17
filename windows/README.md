# BugNarrator Windows Workspace

This directory contains the Windows implementation workspace for BugNarrator.

Source-of-truth documents for Windows work:

- [Windows Implementation Roadmap](/Users/deffenda/Code/FeedbackMic/windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md)
- [Windows Validation Checklist](/Users/deffenda/Code/FeedbackMic/windows/docs/WINDOWS_VALIDATION_CHECKLIST.md)
- [Cross-Platform Guidelines](/Users/deffenda/Code/FeedbackMic/docs/CROSS_PLATFORM_GUIDELINES.md)

## Milestone 1 Scope
- establish the Windows solution structure
- create the core, Windows shell, and Windows services projects
- keep platform-neutral logic out of the WPF project
- avoid speculative feature implementation

## Build Notes
This workspace targets:

- C#
- .NET 8
- WPF for the Windows UI shell

WPF restore, build, and launch validation must happen on Windows. This macOS workspace can prepare the project structure and non-Windows-specific files, but it cannot honestly validate the Windows UI project.

## Intended Windows Commands
Run these on a Windows machine with the .NET 8 SDK installed:

```powershell
dotnet restore windows/BugNarrator.Windows.sln
dotnet build windows/BugNarrator.Windows.sln -c Debug
dotnet test windows/tests/BugNarrator.Core.Tests/BugNarrator.Core.Tests.csproj -c Debug
```
