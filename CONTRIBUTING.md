# Contributing to Tandem

[Português](CONTRIBUINDO.md)

Thanks for looking. This document is deliberately short: the most valuable
contribution here does not require writing a line of code.

## The most valuable contribution: tell us what happened

Tandem has an honest problem — **almost no real commercial program has ever run
on it.** The dependency-detection loop has been exercised with real Wine and
real `winetricks`, but against synthetic binaries, not against an actual shop's
point-of-sale system on an actual counter.

Every report about a real program is worth more than a new feature.

**Did it work?** Run this and paste the line into an
[issue](https://github.com/ChrnX0/Tandem/issues/new?template=list.yml):

```bash
tandem contribuir /path/to/program.exe
```

The line carries no filename, no path, no username, no machine name, no network
address and no log line — and Tandem refuses to generate it if any of those
appear. What it does carry is a fingerprint of the file, the architecture, and
which Windows components fixed it. The full format is in
[docs/LIST-FORMAT.md](docs/LIST-FORMAT.md).

**Did it fail?** Run this and attach the file:

```bash
tandem socorro
```

It bundles the diagnosis, the self-test, what Tandem learned and the technical
logs into a single file. **Look at it before attaching**: it shows file paths
from your machine.

## Translating: the easiest useful contribution

Five of the seven catalogues have never been read by somebody who speaks the
language. They are marked as such, and Tandem says so outright to whoever picks
one:

| | reviewed by a speaker |
|---|---|
| English, Portuguese | yes |
| Spanish, French, Simplified Chinese, Hindi, Arabic | **no** |

The risk is not a grammar mistake. It is the sentence that is grammatically
perfect and lands wrong — a warning about an unsigned package that reads as
bureaucratic instead of serious, so somebody clicks Install when they should
not. No test catches that. A speaker reading it for ten minutes does.

**The files are ordinary gettext `.po` files** in `po/`, so Poedit, Lokalize,
Weblate, `msgmerge` and every other translation tool works on them. Nothing to
learn, nothing to install if you already have one:

```bash
poedit po/es.po          # or just open it in a text editor
python3 tools/po-para-catalogo.py    # regenerate the shipped catalogues
bash tests/run.sh
```

When you have read a whole file, change its header:

```
"X-Reviewed-By-Speaker: yes\n"
```

and the asterisk disappears from `tandem idioma`. That header is the whole
mechanism — shipping a translation nobody has read is defensible, shipping it
without saying so is not.

Two things about the format that are not optional:

- **Substitution is `{1}` `{2}`, not `%s`.** Paths and versions carry percent
  signs; there is a test with a folder called `50% off`. Keep the numbers, and
  reorder them freely if your language wants a different order.
- **Never translate a value that goes into a file.** `abriu`, `confirmado`,
  `so-abriu`, `RESOLVERAM`, `CONFIANCA`, `nativo`, `parecido` are on-disk
  format, and the command names (`preparar`, `programas`, `dados`) are what
  people type. Translating one silently breaks memory files already written on
  somebody's machine, and breaks a command copied from a forum.

There is a second place with prose: `src/lib/alternativas.<lang>.tsv` and
`limites.<lang>.tsv`. Those are plain tab-separated tables. **Only ever change
the last columns** — the first column is the pattern that matches and the
second is the class that chooses the message frame. A test checks both, because
a reordered row would answer about the wrong program.

## If you are going to touch the code

### Read `CLAUDE.md` first

It is not an AI file — it is the project's notebook. It holds the inviolable
rules and a list of hard-won facts about Wine, Waydroid and the freedesktop
stack. Half the obvious problems already have an answer there.

### The five rules that do not bend

1. **Never write into a Wine prefix Tandem did not create.** The project was
   born on a machine that also runs a point-of-sale system in its own prefix.
   Automation that "helpfully" installs a runtime into a working production
   environment is worse than no automation.
2. **User-facing messages in Portuguese, no jargon.** `NO_MATCHING_ABIS` becomes
   "this app is built for phones only and will not run here."
3. **`set -e` only in the packager, never in the executables.** The wait loops
   depend on commands that fail on purpose.
4. **Never repeat an install already paid for.** `dotnet48` takes half an hour.
5. **The packager must not depend on `dpkg-deb`.** `build.py` writes the `ar`
   archive by hand and runs on any operating system, Windows included.

### The quality bar

> No error path may end in silence.

"I double-clicked and nothing happened" is treated as a bug, not a limitation.
If your code can fail, it has to say what happened, in Portuguese, somewhere the
person will actually see it.

### Build and test

```bash
python3 build.py --check     # packages; no Debian host, no dpkg-deb needed
bash tests/run.sh            # 309 tests, no Wine, no Waydroid, no install
```

The suite sources the shell libraries straight from `src/lib` and synthesises
Android packages including a real binary `AndroidManifest.xml`, so the manifest
parser runs on the same code path a real APK takes. Optional tools that are
absent are skipped, not failed.

**Run the suite before opening the PR.** CI runs it, plus `lintian` with zero
warnings, plus a real install–configure–purge cycle on Ubuntu 24.04.

### A test must be able to fail

Before calling a test done, **break the code on purpose and confirm the test
fails.** A test that passes against broken code proves nothing, and this project
has already shipped an evidence gate that went green without running a single
test.

### Evidence

The project uses an explicit hierarchy, and "done" requires at least E3:

| | |
|---|---|
| E0 | believed |
| E1 | static (I read the code) |
| E2 | tested (the suite covers it) |
| E3 | exercised (I ran it and looked at the result) |
| E4 | in production (it worked on someone's machine) |

The gap between E1 and E3 is not philosophy. Five field defects were invisible
to reading and visible to exercising — among them an error dialog that never
opened and a progress bar that killed the whole program.

## What has already been rejected

Before proposing, look at [docs/IDEAS.md](docs/IDEAS.md). It holds
52 ideas with a verdict each, and **the rejected ones carry the written reason.**
Half the obvious ideas were already turned down for a concrete reason —
scheduled automatic backups, syncing data to the cloud, a first-run wizard. If
you disagree with a rejection, good: bring the new argument. That is exactly why
the reason is written down.

## Quick map

```
build.py                  packager (hand-written ar + tar.gz)
src/bin/tandem            CLI + panel; 20 commands
src/bin/tandem-exe        the run→detect→install→retry loop
src/bin/tandem-apk        pre-flight + install; xapk/apks via adb
src/lib/common.sh         messages, locale, prefixes, data, memory, list
src/lib/winedeps.sh       DLL → winetricks verb
src/lib/peinfo.py         reads the PE import table without executing it
src/lib/apkinfo.py        reads binary AndroidManifest, pure Python
tests/run.sh              the suite
docs/IDEAS.md             the idea ledger, with verdicts
docs/LIST-FORMAT.md       the community list format
```

## Licence

MIT. By contributing you agree to licence your contribution under the same
terms.
