# Fresh-account runbook — prove the npm install needs no compiler

The one thing that cannot be verified from the developer's own account: that a Mac
which has **never had Xcode Command Line Tools** can install AgentFocus and get a
working, clickable banner. Everything else in this repo is machine-checked; this is
the last mile, and it needs a human at the keyboard for the permission prompts.

Budget ~15 minutes, including one logout/login.

## What is already verified without this (so you know what is left)

Run on the dev machine, all passing:

- `libexec/AgentFocus.app` is universal (`x86_64 arm64`) with `minos 13.0` on **both**
  slices — so it launches on Ventura and later, not just the OS that built it.
- `npm pack` ships `libexec/`, ships no `helper/` source, and preserves the executable
  bit and `_CodeSignature/CodeResources`.
- After `npm install -g <tgz>`, `codesign --verify --deep --strict` passes and the
  **cdhash is byte-identical** to the source build — which is what keeps the Automation
  grant stable across reinstalls of the same version.
- No `com.apple.quarantine` xattr anywhere in the installed bundle.
- `agentfocus init` from the installed package takes the copy path, not the compile
  path (no `Built …` line), and the copied bundle keeps its signature.

What is left is behavioural: prompts, banners, clicks, and login persistence on an
account that has never seen this tool.

## Runbook

**1. Stage the artifacts** (as your normal user). A second account cannot read
`~/Desktop`, so put everything in `/Users/Shared`:

```sh
cd ~/Desktop/moonshot/agentfocus
npm pack                                   # prepack builds libexec/ automatically
cp agentfocus-*.tgz /Users/Shared/
cp -R selftest /Users/Shared/agentfocus-selftest
sudo sysadminctl -addUser aftest -fullName "AF Test" -password '<choose-one>'
```

Keep `aftest` **non-admin** — that is the realistic case, and it proves nothing needs
sudo.

**2. Switch accounts.** Apple menu → Log Out, then log in as `aftest`.
(The old `CGSession -switchToUserID` fast-switch binary is gone on macOS 26, and the
run needs a real logout/login for the login-item gate anyway.)

**3. Put node on the login PATH.** Homebrew's node lives in `/opt/homebrew`, which is
machine-wide but not on a fresh user's PATH. Both the CLI shebang and the helper's
`zsh -lc` need it:

```sh
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"; export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.zprofile
exec zsh -l
npm config set prefix ~/.npm-global        # a global prefix this user can write to
```

**4. Run the gates.**

```sh
AF_INSTALL=npm AF_TGZ=/Users/Shared/agentfocus-0.1.0.tgz \
  /Users/Shared/agentfocus-selftest/fresh-user.sh
```

Answer y/n honestly about what you actually saw. It stops and tells you to log out.

**5. Log out, log back in as `aftest`, resume:**

```sh
AF_INSTALL=npm AF_TGZ=/Users/Shared/agentfocus-0.1.0.tgz \
  /Users/Shared/agentfocus-selftest/fresh-user.sh --resume
```

**6. Clean up** (back on your own account):

```sh
sudo sysadminctl -deleteUser aftest
rm /Users/Shared/agentfocus-*.tgz; rm -rf /Users/Shared/agentfocus-selftest
```

## What a PASS means

- **G1** — installed with no compiler (`no compiler` gate), universal, macOS 13 floor,
  unquarantined.
- **G4** — exactly one Notifications prompt, and **zero** Accessibility / Screen
  Recording / Input Monitoring prompts. Any of those three is a hard product failure,
  not a bug.
- **G5/G6** — a banner appeared and clicking it selected the exact Terminal tab, after
  one Automation prompt.
- **G8b** — after logout/login the helper came back on its own with no prompts.
- **G9** — reinstalling the **same** tarball does **not** re-ask for Automation. This is
  the one that is new for the prebuilt path: it proves every user of a release runs the
  same bytes.

A FAIL on G9 means the shipped binary is not reproducible between packs — check that
`prepack` is not embedding a timestamp or a path.

## Known gap

Nobody has yet launched this on **macOS 13–15**. `minos 13.0` is the mechanism that
makes it possible and it is verified in the binary, but the behaviour is untested. If
you get one tester on an older Mac, that is the highest-value report you can collect.
