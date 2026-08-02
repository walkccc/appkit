# Contributing

Thanks for looking. This repo is small on purpose, and most of the work of keeping it useful is deciding what does **not** go in it.

## The bar

**Is this true of every app on appkit?** Not "does it help the app in front of me" — that app can have it in its own repo.

Three homes, in order of preference:

| It is true of… | It goes in…                                             |
| -------------- | ------------------------------------------------------- |
| every app      | `lib/`, `commands/`, `render/`, `store/`                |
| one platform   | `platform/<name>.sh`                                    |
| one app        | that app's repo — `scripts/scenes.sh`, `appkit.json`, … |

The failure this repo exists to prevent is a shared file that compiles everywhere and is silently wrong in one place. There are three of those written up in `README.md`; they are worth reading before proposing a fourth.

## The platform contract

Every capability a command needs from a device is a `platform_*` function, and each of `platform/{ios,macos,android}.sh` defines all of them.

macOS is the adapter worth reading first if you are adding a fourth: it is the one where the "device" is the machine appkit is itself running on, so half the contract (boot, create, install onto) collapses into nothing — and the shape of what a no-op has to explain is clearer there than anywhere else.

**No command may contain `case $PLATFORM`.** If you find yourself writing one, the contract is missing a function — add it to both adapters, as a no-op with a line of explanation where a platform genuinely cannot do it.

Adding a platform should be exactly: write `platform/<name>.sh`, add `"platform": "<name>"` to a manifest, change nothing else. If something else has to change, the contract was wrong and that is the bug worth fixing.

## Checks

There is no test suite. There is this, and it is fast:

```sh
for f in bin/appkit commands/*.sh lib/*.sh platform/*.sh store/*.sh; do
  bash -n "$f" || echo "FAIL $f"
done
sh -n githooks/pre-commit
for f in render/*.swift; do swiftc -O -o "/tmp/$(basename "$f" .swift)" "$f" || echo "FAIL $f"; done
prettier --check "**/*.{md,json,yml}"

# Every adapter answers the whole contract. Silence is a pass.
for p in macos android; do
  diff <(grep -o '^platform_[a-z_]*' platform/ios.sh | sort) \
       <(grep -o '^platform_[a-z_]*' platform/$p.sh | sort)
done

# And no command decides anything by asking which platform it is on.
grep -rn 'case .*\$PLATFORM\|\$PLATFORM.*==' commands/ bin/appkit lib/
```

The last two are cheap and catch the only two failures this layout has ever had. A `platform_*` in one adapter and not the other is invisible until somebody runs the one command that needs the missing half — `platform_use_device` was iOS-only, and `appkit run --device` on Android died with "command not found". A `case $PLATFORM` in a command is the same bug one step earlier: the capability belongs in the contract, and the branch is what you write instead of putting it there.

Then run `appkit sync && appkit doctor` in a real repo before pushing something every app will pull. A change to the composer is worth rendering one locale into a scratch directory and **looking at**, because that is the only review it gets:

```sh
appkit render --locale en
```

If you touched the composer, prove it still reproduces:

```sh
appkit render --locale en && shasum -a 256 store/screenshots/*/*.png > /tmp/a
appkit render --locale en && shasum -a 256 store/screenshots/*/*.png | diff /tmp/a -
```

## Style

Bash with `set -euo pipefail`; functions in `lib/` and `platform/`, flow in `commands/`. Swift 6 under strict concurrency. Prettier does not reflow prose — markdown keeps the line breaks you wrote, in English and in 繁中 alike.

Comments earn their place by saying what the code cannot: why `position` and not `.offset`, why serial and not parallel, which store rejected what. A comment restating the line above it is noise; a comment recording a trap somebody already fell into is the most valuable thing in the file.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/), and few of them. A subject line, and a body only when it says something the diff cannot. `!` marks a change that makes app repos re-run `appkit sync`.

Group commits by what changed for the repos on appkit, not by the order the work happened in.

## Rolling a change out

appkit is installed, so merging here changes nothing until each machine upgrades and each repo takes the shared files:

```sh
brew upgrade appkit
appkit sync && appkit doctor && git commit -am "chore: sync appkit"
```

Only the copies need that second step — a fix inside a command reaches every repo the moment brew upgrades, and the skills follow the install rather than the repo. A repo that never syncs keeps yesterday's `AGENTS.core.md`, which is exactly what `appkit doctor` is for.

## Scope

Things this project is happy to grow: another platform adapter, another store publisher, more of the storyboard schema, better determinism.

Things it will decline: anything that builds an app on CI, anything that needs a browser or a package manager at render time, and any shared file that encodes one app's taste.
