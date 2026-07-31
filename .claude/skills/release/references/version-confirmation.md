# Structured version confirmation

Use the runtime's structured user-input tool:

- Claude Code: `AskUserQuestion`;
- Codex: `request_user_input`.

Discover the live tool schema before constructing the question. Present the recommended version in both forms the repository uses — the displayed `X.Y` and the canonical `X.Y.Z` — together with the strongest changes that determine the bump, and a way to confirm it, name another version, or cancel the release.

Wait for an affirmative structured answer before touching either version field in `Sources/Rusifikator/Resources/Rusifikator-Info.plist` or moving anything out of `Unreleased`.

When the owner names another version, validate it against the complete candidate. If it understates the required semantic bump, does not strictly increase the canonical version, or already has a public tag or release, explain the conflict and ask again through the structured tool. Never accept such a version silently and never fall back to a plain chat question.

If the structured question tool is unavailable or the call fails, mark the release `BLOCKED`, report the missing gate, and leave every version field unchanged.
