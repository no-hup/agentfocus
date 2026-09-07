# MUST-DO

Deliberately not done yet, in priority order. Each entry says why it matters and what it
unlocks, so the next person doesn't have to re-derive the reasoning.

## 1. Developer ID signing + notarization ($99/yr Apple Developer Program)

**Mostly defused without paying.** The helper now ships PREBUILT in the npm tarball
(`prepack` → `libexec/AgentFocus.app`, universal, macOS 13 floor), because an ad-hoc
signature is valid anywhere — Gatekeeper only assesses bundles carrying
`com.apple.quarantine`, and npm/curl never set it. Verified end to end on this machine:
`npm pack` → `npm install -g` → `init` copies the bundle, `codesign --verify --strict`
passes, and the cdhash is byte-identical to the source build. So:

- ~~every user must install the Xcode Command Line Tools (1–2 GB)~~ **gone** — no compiler
- ~~the Automation grant re-prompts after every rebuild~~ **now once per RELEASE**, because
  every user of a version runs the same bytes (a source build still re-prompts each rebuild)
- the Homebrew formula could now ship a bottle (`pour_bottle? false` is no longer forced)

What $99 still buys, and only this:

- a plain "download the .app" path (a browser download IS quarantined, so it needs
  notarization — the npm/curl path does not)
- no Automation re-prompt across version upgrades
- no scary first-launch dialog for anyone who does download it in a browser

## 2. Release automation

Today: `npm version <x>` then `npm publish` by hand. There is no tag, no CI, no checksum.

Target: tag → GitHub Actions builds → `npm publish` → GitHub Release with checksums. Once
signing exists (#1), add notarize + `brew bump-formula-pr` to the same pipeline. Nobody
should ever hand-edit a `sha256`.

## 3. Homebrew tap

`Formula/agentfocus.rb` is written but not installable: the tap `no-hup/homebrew-agentfocus`
does not exist and the formula still has a commented-out `url` and `sha256 "PLACEHOLDER"`.

Not merely a nice-to-have alongside npm: brew's `depends_on "node"` is the only channel that
**installs Node for the user**. Anyone who installed Claude Code with its native installer
has no Node, and `npx` does not exist for them.

## 4. Demo GIF in the README

The product is entirely visual — "you click a banner and the right window comes forward" —
and the README has no picture of it. Highest-leverage marketing change per minute spent.

## 5. Publish the VS Code extension

`vscode-ext/` gives tab-exact focus inside the VS Code family; today it must be built and
installed by hand (`vsce publish`). Carried over from BUILD-NOTES.md.

## 6. Verify the iTerm adapter on a machine with iTerm2

BUGS.md #4 (the `identity_handle` suffix comparison) is implemented but has never been run
against a real iTerm2 — this machine doesn't have it installed. Everything else in that
list was verified empirically; this is the one gap.

## 7. ~~Single source of truth for the version~~ — DONE

`helper/build.sh` now reads the version from `package.json` (it hardcoded `1.0.0` while
`package.json` said `0.1.0`).

## 8. Rewrite the CLAUDE.md setup constraint as a goal, not a mechanism

It currently reads *"`brew install` + one command must be the whole setup."* That is a
mechanism, and stating it as a constraint is what kept the distribution channel closed —
npm was never considered until it was questioned directly, despite every user of this tool
being a Claude Code user. Reword to the actual goal: *"a Claude Code user must be able to
install with one command."*
