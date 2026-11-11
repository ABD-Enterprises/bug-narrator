# Security scanner snapshot

The rules are from the redistributable community source and immutable commit recorded in lock.json. The snapshot includes Python, JavaScript/TypeScript, C#, Swift, YAML, generic, shell, Dockerfile, Terraform and JSON rules. Test fixtures are excluded. Rule IDs are prefixed with their source paths to avoid collisions; patterns and metadata are unchanged except for the reviewed local adjustment recorded in lock.json. The previous dynamic auto configuration included rules that prohibit redistribution, so it cannot be copied into this public repository.

The upstream license and full LGPL text are included. This source snapshot is used for repository checks; it is not bundled in the app.

For an update, retrieve the recorded source, select the same directories, prefix IDs from source paths and serialize the rules. Review rule changes, source commit, source paths, scanner version, immutable image digest and checksum together. The lock checker rejects mismatched content. Docker and host scans use this local configuration without registry access or metrics; the host must use the locked scanner version.

The rules snapshot is scanner configuration, not application code. It is excluded from scanning itself, which would mistake detection patterns for embedded credentials; its content is checked against the lock checksum before every validation. Scanner scripts remain scan targets.

A scan that cannot run is a validation failure when changed code needs scanning. Only the explicit missing-mount probe result permits host fallback; unrelated container failures are errors.

A literal webhook example was removed from a negative exclusion because GitHub treats that upstream example as a credential. This broadens detection rather than suppressing findings. The adjustment is recorded without copying the blocked value.
