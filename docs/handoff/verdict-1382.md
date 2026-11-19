## Independent review verdict

Reviewed with MiniMax M3 in a fresh context, on the exact head, across five rounds — each round re-derived the answer rather than inheriting the previous one's conclusions. The findings that shaped the final head:

- **The gate's assertion that the validation invokes the check could not be a grep.** A grep over `scripts/validate.sh` matches `|| true` forms and comment text, and misses `if ! "..."` and `bash "..."`. The gate now proves it by running: it clones the repository, breaks the clone's version sources, and requires the validation to fail because of the version contract.
- **The proof must use a genuinely broken tree, not a simulated failure.** A simulation shows that a simulated signal reaches a failed validation; it does not show that a real drift does. The proof now validates a clone whose `VERSION` disagrees with `project.yml`.
- **The check must still be shown to compare every source.** The gate exercises the check against a throwaway workspace with deliberately wrong sources, so a check that has rotted into one that always agrees cannot pass it.
- **The real-tree check is unconditional.** No environment variable can stand in for the real check, so a drifted tree cannot be hidden.

**Verdict: MERGEABLE.** No P0 and no P1 against the merged head.

### What the merged head does not cover, and what is being done about it

The review also found two gaps that were fixed on the branch **after** this pull request merged, so they are not in `main` yet:

1. **The nesting was bounded by the version check's behaviour rather than by the plumbing.** A check that had rotted into tolerating the clone's specific drift would have made the clone's validation pass, and the gate would have cloned again — recursively, without limit, growing the temporary directory each time. The fix restores an explicit self-check flag that the gate reads, so the nesting is one level deep however the check behaves, and a rotted check produces a clean red instead of a hang.
2. **The released changelog heading was not pinned.** The gate's probes covered a `VERSION` that disagrees with `project.yml` and a build number that is not a number, but not a check that had stopped comparing `CHANGELOG-archive.md` at all. The fix adds that probe.

Both are in a follow-up pull request, together with the wording and documentation corrections this review turned up (`scripts/bump_version.sh` and `scripts/check_version_consistency.sh` disagreeing about the build-number rule, and `docs/development/setup.md` not mentioning it).

The limits that remain are the ones every self-contained check shares, and the changelog entry says so: a gate cannot survive its own replacement, and a validator edited to swallow its failure is not something the gate can detect. The property that is claimed, and established by running, is that **a version drift fails the declared validation**.
