# Unmaintained

## `jda1-mac.jda`

A macOS port of the compiler that **nothing builds, tests, or references.**
`tools/jda-macos.sh` does not use it; it generates assembly through a separate
path. Kept for intent, moved here so it is not mistaken for part of the
bootstrap chain, which is `bootstrap/bin/jda1-bootstrap` → `bootstrap/stage0/jda1`
→ `bootstrap/stage1/jda1.jda`.

**It has diverged and will keep diverging.** It still carries defects fixed in
`jda1.jda` — the token accessors that clamp an out-of-range index to token 0
rather than reporting a miss — and it has none of the Tier 1 fixes recorded in
`docs/known-breakage.md`:

| Fix | In `jda1.jda` | In `jda1-mac.jda` |
|---|---|---|
| Bracket-first local arrays | yes | no |
| Tuple destructuring rejected (`JDA-F008`) | yes | no |
| Unknown methods rejected (`JDA-C005`) | yes | no |
| `const` expression folding | yes | no |
| Negative integers print correctly | yes | no |
| Constants resolve in interpolation | yes | no |
| Checked-accessor sentinels | yes | no |

Every change to `jda1.jda` widens the gap, and nothing reports it, because
nothing builds this file.

To revive it, port those fixes and wire it into CI in the same commit — a
macOS port that is not built is a port that is already broken, it just has not
been told yet. Reviving it without CI coverage recreates exactly this state.
