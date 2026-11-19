## Summary

A follow-up to #1382, which carried the version-contract gate. The review of that pull request found two gaps that were fixed on its branch **after** it merged, so they are not in `main` yet. This pull request carries them, together with the wording and documentation corrections the same review turned up.

## The two behavioural fixes

**1. The gate's nesting was bounded by the version check's behaviour, not by its own plumbing.**

The gate proves that a version drift fails the validation by cloning the repository, breaking the clone's version sources, and validating the clone. The clone's own gate was expected to stop at its real-tree check, because the clone's `VERSION` disagrees with its `project.yml`.

That expectation is a property of the version check, not of the gate. A check that had rotted into tolerating *that specific* drift would have let the clone's validation pass, and the gate would have cloned again — recursively, without limit, with each level's temporary directory accumulating. The failure mode the pull request set out to prevent, a check that quietly stops enforcing the contract, turned into a hang and unbounded disk use instead of a clean red.

The gate now sets `VALIDATE_SKIP_VERSION_CHECK_SELF_CHECK` for the clone and skips its own proof when that flag is set, so the nesting is one level deep however the check behaves, and a rotted check fails the gate with a message instead of cloning without bound. This is the pattern the repository's own `scripts/check-changed-files.sh` already uses.

**2. The released changelog heading was not pinned.**

The gate's probes covered a `VERSION` that disagrees with `project.yml`, and a build number that is not a number. They did not cover a check that had stopped comparing `CHANGELOG-archive.md` at all — the released heading is one of the three sources the contract names, and a check that quietly dropped it would have passed the gate. The gate now probes that too: a workspace whose `VERSION` agrees with `project.yml` and whose released heading does not.

## The corrections the same review turned up

- `scripts/bump_version.sh` and `scripts/check_version_consistency.sh` described the build-number rule differently — "positive integer" against a rule that accepts zero — and now say the same thing.
- `AGENTS.md` names the version contract and the gate that enforces it, in the order the checks actually run.
- `docs/development/setup.md` lists the build-number half of the contract.

## Validation

`VALIDATE_SKIP_BOARD_AUDIT=1 ./scripts/validate.sh origin/main` → exit 0.

The gate was exercised against each way it could be wrong:

| | result |
|---|---|
| healthy tree | passes |
| the real tree drifts | fails: the version sources are inconsistent |
| the check is missing or not executable | fails |
| the check has rotted into one that always passes | fails |
| the check no longer compares the released heading | fails: the version check accepted a released heading that does not match VERSION |
| the check tolerates the proof's specific drift | fails cleanly, in one level — no unbounded nesting |
| `validate.sh` no longer runs the gate | fails: the validation passed although the version contract was broken |
| the validation fails for another reason | fails: the validation failed for another reason than the version contract |

Follow-up to #1382.
