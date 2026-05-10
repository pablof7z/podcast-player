# Agent Guidelines

## Whats-new changelog

Every commit that ships a user-facing change to the iPhone MUST add an entry to `App/Resources/whats-new.json` with a one-liner the user will read. The entry's `id` is the short SHA of the commit. Multi-commit features get one entry per commit unless the changes are too small individually — in that case roll them into one entry under the most representative commit. Skip entries for purely-internal commits (encoder caches, log line tweaks, formatting). When in doubt: would the user notice? If yes, add a line.

## File Length Limits

- **Soft limit: 300 lines** — prefer splitting into smaller files when approaching this threshold.
- **Hard limit: 500 lines** — files must not exceed 500 lines. Refactor before adding more code.
