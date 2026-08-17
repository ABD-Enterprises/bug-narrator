# Contract fixtures

Artifacts that **both** the macOS and Windows implementations must produce
identically. Committed so parity is machine-checked instead of asserted twice
against two hand-typed literals.

## Why this exists

Before these fixtures, each platform asserted parity against its own retyped
string. Both suites were green while the implementations disagreed — the
mechanism behind the drift catalogued in #965.

A concrete example, found while building this (#1000). Windows'
`CompletedSessionMarkdownBuilder_MatchesMacTranscriptContract` pinned:

```
- Recorded: Mar 17, 2026 at 3:00:00 PM
```

for `2026-03-17T15:00:00Z`. macOS rendered the same instant as
`Mar 17, 2026 at 11:00:00 AM` on a developer machine in `America/New_York`,
because its formatter used the running machine's locale and timezone. The
Windows test was green against an output macOS produced nowhere outside UTC.

## Files

| File | What it is |
|---|---|
| `transcript.golden.md` | The exact `transcript.md` the canonical session must export |

## The canonical session

Fixed values so both platforms can build the same input:

| field | value |
|---|---|
| `id` | `00000000-0000-4000-8000-000000000001` |
| `createdAt` | `2026-03-17T15:00:00Z` (epoch `1773759600`) |
| `transcript` | `The checkout button is clipped on the right at 1280 wide.` |
| `duration` | `120` seconds |
| `model` | `whisper-1` |
| `languageHint` | `en` |
| `prompt` | none |
| marker | id `11111111-1111-4111-8111-111111111111`, index `1`, elapsed `30`, title `Checkout button clipped`, note `Right edge is cut off at 1280 wide.`, no screenshot |

## Timestamp rendering — read this before debugging a mismatch

The contract renders timestamps with **`en_US_POSIX` locale, `UTC` timezone,
and ASCII spaces**.

The ASCII part is not cosmetic. Apple's `Date.FormatStyle` separates the time
from `AM`/`PM` with **U+202F** (narrow no-break space); .NET's invariant
`ToString` uses ASCII `0x20`. The two render identically on screen and differ
in bytes, so a fixture that kept U+202F could never be matched by Windows and
the failure would look inexplicable. macOS normalizes U+202F and U+00A0 to
ASCII in this pinned rendering only — the user-facing export is unchanged.

If a comparison fails on a line that looks correct, check the bytes:

```bash
python3 -c "print([hex(b) for b in open('transcript.golden.md','rb').read()[:80]])"
```

## Regenerating

Only when the contract is intended to change:

```bash
TEST_RUNNER_BUGNARRATOR_UPDATE_CONTRACT_FIXTURES=1 \
  xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator \
  -destination 'platform=macOS' \
  -only-testing:BugNarratorTests/TranscriptContractFixtureTests test
```

A regenerated fixture means the Windows suite should fail until it is updated
to match. That failure is the feature.

## Consuming from Windows

Wired up in #1003. `windows/tests/BugNarrator.Core.Tests/TranscriptContractFixtureTests.cs` builds
the canonical session from the table above, renders it with
`SessionTimeFormatter.InvariantTimestampOptions`, and byte-compares against this golden. It locates
the file from the test's `[CallerFilePath]`, mirroring how the macOS test uses `#filePath`, and it
fails loudly if the fixture is missing rather than skipping.

Both platforms now compare against this one file, so a renderer change on either side that the
fixture does not expect fails a build.

### Line endings

`contract-fixtures/**` is pinned to `text eol=lf` in `.gitattributes`. Without it, `core.autocrlf=true`
checks the golden out as CRLF on Windows while the committed bytes are LF, and the byte comparison
fails on one machine while passing on another. The Windows test also asserts the loaded fixture
contains no `\r` and says so explicitly, because that failure otherwise looks impossible — the text
is identical on screen.

### What wiring this up found

Two real divergences in the Windows renderer, both fixed in the renderer rather than by editing the
fixture:

- marker notes were not rendered at all — `SessionTimelineMoment` had no note field, so the
  `— Right edge is cut off at 1280 wide.` in the golden could not be produced
- Windows appended a trailing newline that macOS does not emit
