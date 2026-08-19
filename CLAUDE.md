# Tandem — context for the agent

Read this before touching anything. This file exists so that a fresh session can
pick the work back up without re-paying for discoveries that were expensive the
first time.

## What it is

A `.deb` package that makes **nine install formats** open with a **double
click** on Linux: `.exe`, `.msi`, `.apk`, `.xapk`, `.AppImage`, `.jar`, `.deb`,
`.rpm`, `.flatpakref`, `.snap`, plus shell installers. It is not a prefix manager
and not a Bottles replacement: it is a **thin layer of decision, translation and
diagnosis** on top of `wine`, `winetricks -q`, `waydroid`, the AppImage runtime,
`java`, `apt` and `flatpak`.

The target user is not a programmer. The quality bar is: *no error path may end
in silence.* "I double-clicked and nothing happened" is treated as a bug, not as
a limitation.

## How the owner wants this worked on

A standing directive, in his words: *"nunca fique ocioso e sempre faça o q
precisa ser feito, sem exceção"*, and *"eu te proíbo me perguntar coisa
obvia"*.

So: **do not ask what is obvious, and do not stop to be told to continue.** When
the work is finished, publishing it is part of finishing it — build, verify the
artifact against a local build, and say what came out. When one thing is done,
the next item on the queue below starts without being asked for. Idling to
confirm something the owner has already decided wastes the only resource he
cannot buy back.

What still deserves a question is narrow and worth keeping narrow: a decision
only he can make (hosting an endpoint, holding a credential, spending money), or
an action that destroys something. Everything else — which defect to fix first,
how to shape a message, whether to open a version, whether to release one — is
the agent's call, made and reported rather than asked about.

**Standing directive, 2026-08-18 — the extrapolation drive.** After the
web-service work shipped (4.26), the owner asked for an autonomous *round of
extrapolation*: "pense o q pode tornar o tandem impressionante e excepcional e
implemente" — the agent's own picks for what makes Tandem exceptional, built and
shipped, not proposed. And then a SECOND, deeper round after it: "depois dessa
rodada eu quero mais outra rodada mais profunda ainda e aí vc implementa tudo de
agora e a seguinte." So the mandate is two rounds, both implemented, one
well-tested shipped version at a time, until told to stop. **Round one is
CLOSED** — and the way it closed is a lesson worth keeping. It is the "explain,
don't execute" white space, the silent failures that happen AROUND the software:
4.27 the clock (`tandem relogio`), 4.28 proactive post-install breakage
detection (Wine changed under a working program), 4.29 the provenance / "is this
.exe known to the community" note (`t_procedencia`). The fourth listed item,
**passive self-update awareness, was already DONE — shipped in 4.13** (the
`t_versao_*` family, `acao_versao` on/off, the daily throttled background check
wired at `tandem:1906`, `versao_nova_aviso` in all seven catalogues). A session
scoped it as 4.30, opened the version, and wrote a changelog entry for it before
discovering — by reading the tree, not the ledger — that it existed. This is the
exact stale-ledger trap this file documents: a directory that lists as "next"
something three versions old sends the next session to rebuild it. Verify
against the code before building, every time. **Round
two** is deeper and more architectural — real recovery (verifiable backups,
restore to a replacement PC after a disk dies), local Wine version pinning /
rollback so a distro upgrade cannot break a working POS, second-counter
replication, and a single machine-"health" model. Round two is designed once
round one closes. Read `docs/IDEAS.md` before each pick — half the obvious ideas
are already decided there, with reasons.

**Use the insights ACTIVELY, and the proof gate ACTIVELY.** Both are standing
instructions from the owner, in his words: *"identifique e aplique melhorias q
vc venha a identificar ser bom"* and *"coloca nas diretrizes q é para usar os
insights ATIVAMENTE... assim como é para usar o proof gate ativamente"*.

**Reaffirmed as a PERMANENT directive, 2026-08-19**, in his words: *"uma coisa q
quero q vire diretriz permanente é que vc use sempre q possível os teus insight
(isso chega a ser skill)"*. So this is not advice, it is a rule with the same
weight as the inviolable ones: on every task, before and during and after, bring
the insight — the pattern behind the instance, the instrument for the class, the
honest report that costs you, the move that turns a fix into a guard. Treat it
as the skill it is; a session that merely completes the ticket without applying
what it noticed has not done the job the owner asked for.

What that means in practice, because "be insightful" is not an instruction
anybody can follow:

- **When the same shape of defect appears twice, stop fixing instances and
  build the instrument that finds the class.** This file records four guards
  that were scoped to the file where their defect was noticed rather than to
  every file where it lived - the log-slicing guard, the future-date guard, the
  silent-refusal audit, the default-language flip. A fifth was then found *by
  an instrument written for that shape*: an assertion naming ONE handler when
  nine siblings exist. That is the move. Two of a kind is a pattern; three is
  negligence.
- **Say the insight even when it costs you.** "The returns on this line of work
  are falling" and "the defect I just reported was in my own test, not in the
  product" are the reports that let the owner steer. A session that only ever
  reports finds is a session nobody can correct.
- **Run the proof gate on the work, not after it.** `proofgate.json` carries
  the stack and the coupled-file pairs precisely so the check is mechanical -
  do not hand-wave it because the change "looks small". The version lives in
  four places and lintian has caught this project three times on dates alone.

The one thing that is never optional: **report what actually happened.** A guard
that caught your own mistake, a test that was written after the code it guards,
a check whose summary line was unconditional — those go in the message. This
file is full of measurements that were wrong for a while, and every one of them
was found by somebody writing down what they actually saw.

## Inviolable rules

1. **Never write into a Wine prefix Tandem did not create.** Our prefixes carry
   the `.tandem-prefixo` marker. Any other one is read-only to the automation:
   Tandem runs the program inside it, reports what is missing, and **stops**.
   This exists because the origin machine also runs a point-of-sale system in
   its own prefix — installing a dependency inside a working production
   environment is worse than not automating at all.
2. **No jargon in anything the user reads, in any language.** `NO_MATCHING_ABIS`
   becomes "this app is made for phones only and does not run here". Every such
   sentence belongs in `po/`, never in the code. `tools/conta-literais.py`
   measures how far that is from true and the suite holds the number as a
   ratchet: it may fall, never rise. **It has now read 0 four times and three
   of those zeros were false** — read the section on the counter before you
   trust any number it prints. What is different is not the number: the
   fifteenth miss was a whole file type this tool cannot see, so a second
   instrument now covers it.
3. **`set -e` only in the packager, never in the executables.** The wait loops
   depend on commands that fail on purpose (`grep -q ... && break`).
4. **Never repeat an install already paid for.** `dotnet48` takes ~30 min; the
   receipt lives in `$WINEPREFIX/.tandem-verbos`.
5. **The packager must not depend on `dpkg-deb`.** `build.py` writes the `ar`
   archive by hand and runs on any OS, Windows included.

## Language of the repository

**Everything written in this repository is in English** — comments, test names,
documentation, the changelog, and commit messages. That is a standing directive:
the repository is where people from outside come to read and contribute, and a
codebase they cannot read is a wall.

**The product is written seven times over, and English is the default.** That is
a reversal, decided by the owner: *"o padrão eh inglês. tudo tem q ser
traduzido, óbvio."* So there is no longer a Portuguese half of this project and
an English half — there is a repository, in English, and a product that exists
in `en`, `pt_BR`, `es`, `fr`, `zh_CN`, `hi` and `ar`. Every format is translated
through its own native mechanism: the messages through `po/`, the `.desktop`
files through `Name[xx]=`, the manual through `/usr/share/man/<locale>/man1/`,
the data tables through `alternativas.<lang>.tsv` and `limites.<lang>.tsv`.

Three things stay Portuguese, and each for a reason that is not sentiment:

1. **The command names the user types** — `preparar`, `programas`,
   `desinstalar`, `dados`, `alternativas`, `receita`, `memoria`, `esquecer`,
   `socorro`, `contribuir`, `lista`. A command copied off a forum has to work
   on any machine, so these cannot move with the language. Most carry an English
   alias for people who expect one.
2. **`LEIAME.md` and `CONTRIBUINDO.md`.** They are the front door for the
   audience that actually runs this software, and a test keeps their command
   lists in sync with the English pair.
3. **The literal values written into state files** — see the paragraph below.
   Those are on-disk format, not prose.

The short form: **the repository is English, the product is every language, and
what is on disk is neither.**

And one thing that only looks like language: **the literal values written into
state files** — `abriu`, `confirmado`, `so-abriu`, `reprovado`, `RESOLVERAM`,
`NAO_RESOLVERAM`, `CONFIANCA`, `alta`, `baixa`, `override`, `titulo`, `ambos`,
`nativo`, `parecido`. Those are on-disk format, not prose. Translating one
silently breaks compatibility with memory files and recipes already written on
someone's machine.

## Map

```
build.py                  packager (hand-written ar + tar.gz)
debian/control            the package version lives here
debian/changelog          a new entry per version; lintian demands a fresh date
debian/copyright          DEP-5; lintian demands it
debian/postinst           shortcut only: the per-user work happens on first run
man/tandem.1              the manual; the other four are ".so" stubs
src/mime/tandem.xml       registers .xapk/.apks/.apkm as a zip subclass
src/lib/common.sh         log, messages, locale, progress, prefixes, PE, waydroid,
                          memory, recipes, alternatives, data, list, pre-flight,
                          native formats (arch, java, fuse, menu entries),
                          t_erro_do_leitor (reader token -> sentence)
src/lib/winedeps.sh       DLL -> winetricks verb; DLLs with no translation
src/lib/apkinfo.py        binary AndroidManifest reader, pure Python
src/lib/peinfo.py         PE import-table reader, without executing anything
src/lib/appimageinfo.py   AppImage ELF header: generation, arch, payload offset,
                          and whether the download finished
src/lib/jarinfo.py        jar manifest + bytecode major: is it a program, and
                          which Java does it need
src/lib/debinfo.py        .deb control by hand (ar + tar, zstd via libzstd):
                          name, arch, dependencies, and truncation
src/lib/rpminfo.py        .rpm header: name, version, arch, distribution
                          (all six readers answer ERRO=<token>, NEVER a
                          sentence; t_erro_do_leitor translates it)
src/lib/verbos.tsv        GENERATED DLL->verb index; do not edit by hand
src/lib/limites.tsv       signatures of what will never work (dongle, driver)
src/lib/alternativas.tsv  Linux programs that do the same job
po/*.po                   THE SOURCE of every message: ordinary gettext .po
po/tandem.pot             the template, for msginit and msgmerge
tools/atualiza-po.py      THE workflow: edit po/en.po, run this, then the compiler
tools/po-para-catalogo.py compiles po/ -> src/lib/idiomas/ in pure Python
po/LINGUAS                the languages that ship (gettext convention)
src/lib/idiomas/*.txt     GENERATED runtime catalogues; do not edit by hand
tools/indice-winetricks.py  generates verbos.tsv by reading the installed winetricks
tools/prosa-fora-do-catalogo.py  THE SECOND INSTRUMENT: runs the program and reads
                          the OUTPUT. conta-literais.py reads the source and has
                          under-reported sixteen times; this one renders in Chinese
                          and flags Latin word-runs, and renders in all seven and
                          flags any line that comes out byte-identical
proofgate.json            evidence gate: stack, coupled files
.github/workflows/ci.yml  suite + lintian + a real install cycle
.github/workflows/release.yml  tag -> build, verify, publish the .deb
src/bin/tandem            CLI + zenity panel; 20 commands
src/bin/tandem-exe        the run->detect->install->retry loop
src/bin/tandem-apk        pre-flight + install; xapk/apks via adb install-multiple
src/bin/tandem-appimage   exec bit, arch, truncation, FUSE workaround, menu entry
src/bin/tandem-jar        program-or-library, Java version, Class-Path, JavaFX
src/bin/tandem-deb        apt simulation BEFORE the password; release-mismatch
                          verdict; removals and downgrades asked about
src/bin/tandem-rpm        explains, never converts; finds the apt equivalent
src/bin/tandem-flatpak    .flatpakref installs per-user; .flatpakrepo is a SOURCE
src/bin/tandem-snap       local snap needs --dangerous, and says so
src/bin/tandem-script     the one handler whose default answer is NOT to run
src/bin/tandem-repair     the MIME association dispute
src/polkit/               narrow rule: only start/restart of waydroid-container
tests/run.sh              the suite; tests/mkapk.py and tests/mkdeb.py generate
                          the synthetic packages, in the real binary formats
tests/real-programs.sh    REAL software, weekly: PuTTY/Notepad++/7-Zip/WinMerge
                          pinned by sha256, window checked with xdotool; builds a
                          real AppImage with appimagetool and compiles a real jar
docs/IDEAS.md             idea ledger with verdicts; the rejected ones with the reason
docs/LIST-FORMAT.md       the community list record, field by field
lista/lista.tsv           the published list; empty until real people report
api/lista.js              THE INTAKE: validates a posted record and stores it.
                          Deployed to the owner's Vercel project, which is
                          git-linked to this repository - so a push deploys it
api/acumulado.js          what the intake accepted, so the rebuild below needs
                          no credential to read it
tools/monta-lista.py      accepted records -> lista/lista.tsv, with an explicit
                          exclusion list AND a verb-safety gate: a row naming a
                          winetricks settings verb never reaches the file
.github/workflows/lista.yml  weekly rebuild that opens a PULL REQUEST; nothing
                          publishes itself
package.json, vercel.json only for the two functions above. build.py ships an
                          explicit LAYOUT and none of these reach the .deb
```

Commands (`tandem --help` is the source of truth):

```
install    programas   desinstalar   preparar     android
doctor     autoteste   repair        backup       restore      dados
protect    alternativas  receita     memoria      esquecer     logs
idioma     portas      identidade   versao
lista      contribuir  socorro
```

Build and verify:

```bash
python3 build.py --check
bash tests/run.sh          # 1500 tests, no Wine, no Waydroid, no install
bash tests/real-programs.sh --list   # what the weekly job downloads, and why
```

The suite sources the libraries straight from `src/lib` and generates synthetic
Android packages with a real binary `AndroidManifest.xml` (`tests/mkapk.py`), so
the manifest reader is exercised on the same code path a real APK takes. An
absent optional tool is skipped, not failed. **Run it before committing.**

## How the dependency detector works

Wine writes `err:module:import_dll Library MSVCP140.dll not found` when a library
is missing. `t_verbos_do_log` reads those lines, ignores DLLs Wine implements
itself (`kernel32`, `user32`…) and translates the rest into winetricks verbs. A
DLL with no known translation is **not** a system dependency — it is a file the
program itself should have shipped, and the message says so.

Test it without needing Wine:

```bash
. src/lib/winedeps.sh
printf '0:err:module:import_dll Library MSVCP140.dll (needed by X) not found\n' > /tmp/w.log
t_verbos_do_log /tmp/w.log     # expects: vcrun2022
```

## Ecosystem facts already established (do not re-research)

- **CORRECTED, 2026-08-08.** This file used to say "no project does automatic
  dependency detection for `.exe`; not Bottles, not Lutris, not PlayOnLinux — all
  of them require a human picking from a list." **That is now wrong about
  Bottles.** Bottles shipped an analysis engine called *Eagle* in release 61
  (January 2026), and tag 65.4 — dated two days before this correction — carries
  `bottles/backend/managers/eagle.py`, 1145 lines of PE analysis using `pefile`
  and YARA, 67 rules, and a 6.3 MB `data/eagle-intel.sqlite`. It reads an unknown
  `.exe`'s import table (delay imports included), its Rich header, its COM
  descriptor and the files beside it, and it **names the runtimes needed** —
  "Visual C++ (VC++ 2015-22)", ".NET Framework", "Wine Mono" — with nobody
  picking from a list. It also deep-scans INSTALLERS, extracting an MSI or Inno
  setup to a sandbox to analyse the binaries that will be installed, which is
  more than `peinfo.py` does.
  **What survives, and it is the part that matters.** Eagle proposes and stops:
  in `bottles/frontend/views/eagle.py` the dependency suggestions are a
  non-interactive `Adw.ActionRow`, the view imports no dependency manager, and
  the human still installs by hand. So the defensible claim is no longer "nobody
  detects" but **nobody closes the loop**: run → read the actual failure → map
  DLL to verb → install → verify delivery → retry → record. Established by search
  rather than assumed: GitHub code search for `"winetricks" "import_dll"
  language:python` returns exactly **two** files on all of GitHub — Vineyard
  (abandoned 2018) and Deepin Wine Runner — and neither installs from what it
  detected. `import_dll` scoped to bottlesdevs/Bottles, lutris/lutris,
  HeroicGamesLauncher, PortWINE, faugus-launcher, umu-launcher and ProtonUp-Qt
  returns zero hits in all of them.
- **The four things nobody was found to do**, each with the search behind it, and
  each one load-bearing for this project:
  1. **Close the loop for an UNKNOWN program.** Deepin Wine Runner parses
     `err:module:import_dll` and has a repair button — with a fix table of
     exactly three entries (`mfc100`, `mfc42`, `msvbvm60`) and a human clicking
     through a log window. PortProtonQt fires a compatibility report on a crash
     within 5 s but re-reads the FILE, not Wine's output, and only prints
     "Install X through Winetricks". PortProton and umu-protonfixes DO install
     with no human choice — because a human already chose, per game, in 204
     `.ppdb` files and 477 hand-written scripts keyed by Steam AppID. Unknown
     program, no fix.
  2. **Verify the requested DLL arrived** after the installer exited 0.
     `winetricks` itself has 568 verbs and 19 `verify_*` functions, all `dotnet*`,
     all driven by AutoHotkey, and all behind an opt-in `--verify` flag. Bottles'
     `dependency.py` has no post-install existence check.
  3. **Compare the delivered DLL's architecture with the caller's.** winetricks
     knowingly sets `W_SYSTEM32_DLLS=$W_WINDIR_UNIX/syswow64` in a win64 prefix
     and never compares that against the program's bitness. Bottles and
     PortProtonQt both read the PE Machine field and only PRINT it.
  4. **Key a memory of lessons to the FILE**, so it survives a move and transfers
     to another machine. Every scheme found is store- or name-based: Steam AppID,
     a `#name.exe` comment grepped out of a database file, or a sha256 read from a
     shipped read-only DB with no local write-back.
- **Bottles cannot install dependencies from the command line** (GUI only),
  which rules it out as an engine. Still true in 65.4, and Eagle does not change
  it: Eagle only reports.
- **CORRECTED, 2026-08-13 — the moat is narrower than the four points above
  suggest, and this file should not oversell it.** A live-web sweep across eight
  ecosystems (7 agents, sources in the artifact from that day) found the honest
  claim has shrunk. Three specifics, each measured against the current release,
  not memory: (1) **Bottles' dependency manager DOES auto-install** the deps it
  detects — GUI-driven, the user picks from a list, but "it only reports" is now
  wrong as stated; Eagle at ~v64 also gained a **scan-on-crash** offer, a
  reactive trigger. (2) **Zorin 18.1 — the reference machine — now publicly
  markets Tandem's own "rather than failing in silence" philosophy** for
  `.exe`/`.msi`, naming 240+ known apps and suggesting alternatives. The
  philosophy is no longer unique; the depth is. (3) umu/protonfixes and
  CrossOver's CrossTie auto-install too, but only from a per-title recipe keyed
  to a store ID — unknown program, still nothing. **What survives, exactly:**
  nobody closes the loop *from the double click, for a non-technical user, with
  bitness verification and a plain-language sentence, for a program nobody wrote
  a recipe for*. That is still true everywhere the sweep looked — and it is a
  thinner, more specific claim than "nobody detects or installs." State it that
  way. The verify-arrival, verify-bitness, retry, and file-keyed-memory steps
  remain unoccupied; the detection and the install, alone, no longer are.
- **Tandem enters an association dispute, not a vacuum.** Zorin 18 ships
  "Windows App Support" and Waydroid installs `waydroid.app.install.desktop`. If
  a double click opens an "Open with…" dialog, that is why — run `tandem repair`,
  which shows who held the type before and after.
- **`~/.config/gnome-mimeapps.list` and `zorin-mimeapps.list` outrank**
  `mimeapps.list` and override it silently. `tandem-repair` clears the
  competitors, with a backup.
- **`waydroid app install` returns 0 even when it fails.** Always parse the
  output.
- **`Session: RUNNING` does not mean Android is ready.** Wait for
  `sys.boot_completed`; with GAPPS that is another 20–60 s.
- **`winemenubuilder` does two things.** It creates menu shortcuts (we want
  that) and hijacks `.txt`/`.jpg`/`.pdf` associations (we do not). Disabling the
  binary kills both; the right key is
  `HKCU\Software\Wine\FileOpenAssociations\Enable = N`.
- **`WINEARCH` only at prefix creation.** Setting it on an existing prefix makes
  Wine refuse to start.
- **`.msi` is not a PE.** `wine file.msi` always fails; it has to be
  `wine msiexec /i`.
- **zenity refuses accented text when the locale does not exist.** Setting a
  locale the system never generated (`LC_ALL=pt_BR.UTF-8` on a Zorin installed in
  English) makes glib fall back to `ANSI_X3.4-1968`; from then on any non-ASCII
  argument returns `This option is not available`, exit 255, and **no window
  appears at all**. Since every message here has accents, that erased the entire
  interface in silence. Reliable detector: `locale charmap` must say `UTF-8`. Use
  `t_locale_utf8`, never hard-code a locale.
- **`zenity --error` blocks until the click** and returns 0. A non-zero return
  means the window was never shown — that is the signal `t_erro` uses to decide
  whether it needs to repeat the message on the terminal.
- **A progress pipe opened write-only kills the process.** When zenity went
  away, the next progress message took SIGPIPE and brought the whole of Tandem
  down: exit 141, nothing in the log. Inside the `winetricks` loop that cut an
  install in half. Opening the descriptor with `exec 8<> fifo` fixes it — with
  both ends open the pipe never runs out of readers.
- **An `exec N> file` that fails does not abort bash.** The script stays alive,
  `flock` answers "Bad file descriptor", and mistaking that for "lock taken" made
  the double click die in silence. An impossible lock and a busy lock are
  different cases: in the first, carry on without a lock.
- **`wine uninstaller --list` lies.** A 32-bit installer writes its key under
  `Wow6432Node\...\Uninstall`, and `uninstaller.exe` — which becomes a 32-bit
  process when `wine32` is present — enumerates the other view. Confirmed with
  real Wine: 7-Zip installed, list empty. Read `system.reg` and `user.reg`
  directly; both views show up, and you do not even need Wine to list them.
- **GNOME under Wayland does not re-read the application list.** A new
  `.desktop` in a freshly created subfolder (`applications/wine/Programs/X/`)
  only appears in the menu after logging out and back in.
  `update-desktop-database` does **not** fix it — tested on the real machine.
  That is why `tandem programas` exists: Tandem cannot depend on the system menu
  for you to find what you installed.
- **You cannot install dependencies from `postinst`.** `dpkg` holds a lock while
  it runs; an `apt-get` in there waits forever. Hence `tandem preparar` being a
  separate command.
- **`[ -t 1 ]` alone does not distinguish a double click from a redirect.** A
  pipe and a file are not terminals either, and sending the diagnosis to a window
  made `tandem doctor > report.txt` write zero bytes. Test all three:
  `[ -t 1 ] || [ -p /dev/fd/1 ] || [ -f /dev/fd/1 ]`.
- **`exec` WITHOUT A COMMAND applies its redirections to the whole shell, and
  permanently.** Written as `exec 7> file 2>/dev/null`, that `2>/dev/null` does
  not silence the `exec`: it silences stderr for **all the rest of the program**.
  Measured on an Ubuntu 24.04 with no graphical session: the loop detected the
  right DLL, translated it correctly, assembled the correct message with the
  correct command — and returned exit 53 with **zero bytes** of output. It was
  hiding inside the code written to fix a silent failure. The correct form is
  `{ exec 7> file; } 2>/dev/null`: the descriptor persists, the redirect dies at
  the end of the group.
- **Arriving is not arriving in the right bitness.** In a `win64` prefix,
  `system32` holds the 64-bit DLLs and `syswow64` the 32-bit ones. The `mfc42`
  verb exits 0 and delivers into `syswow64`; a 64-bit program still cannot find
  it. The v3.3 delivery proof looked in both folders and approved — a dead end
  with a receipt on top. Check **per architecture**. Half the winetricks verbs
  ship 32-bit payloads only, and it says so in English in the middle of the log.
- **Arriving is not arriving at all if Wine put it there.** Wine installs ~560
  DLLs of its own into every prefix and marks each one **`Wine builtin DLL` at
  offset 64** of the file, in place of the DOS stub message — measured 560 of
  560 on a virgin `win64` prefix, so the marker is a reliable discriminator and
  costs sixteen bytes to read (`t_dll_builtin_wine`). This is not a detail:
  `verbos.tsv` maps `dotnet48` → `mscoree.dll`, and **`mscoree.dll` is present
  in both `system32` and `syswow64` of a prefix with no .NET anywhere** (no
  `Microsoft.NET` folder, zero `NET Framework Setup` keys). So the delivery
  proof for the most expensive verb in the project *could not fail*: a
  `dotnet48` that installed nothing was approved, the receipt was written, and
  under rule №4 the receipt is permanent — half an hour spent, and "I already
  installed what this program was asking for" ever after. Reachable through the
  `memoria`/`lista` shortcut, which asks the table which DLL to look for; a DLL
  that came out of `err:module:import_dll` can never be a builtin, because Wine
  said it could not find it.
- **`wineboot` writes a random `MachineGuid` at prefix creation**, into the
  64-bit view, before Tandem gets a turn — measured on a virgin prefix, Wine
  9.0. That is why `t_identidade_fixa`'s GUID half **had never once run**: its
  guard was "the registry value is absent", which was never true, while the
  mark file recorded `MACHINEGUID=<seed value>` — a mark describing something
  the prefix did not contain. The discriminator has to be the mark file, not
  the registry value. Remaking the environment otherwise hands a licensed
  program a different machine, which is the exact loss that function exists to
  prevent.
- **`wine reg` writes the view it is not read from.** On Ubuntu with `wine32`
  present, `/usr/bin/wine` runs `reg.exe` as a **32-bit** process — same reason
  `wine uninstaller --list` enumerates the other view — so `wine reg add
  HKLM\Software\...` with **no `/reg:` flag lands in `Software\Wow6432Node\…`**,
  while `t_reg_valor` reads `Software\…`. Measured both ways: no flag →
  `Wow6432Node`, `/reg:64` → the 64-bit key, and `/reg:32` is a no-op here
  because that is already the default. Name the view every time, and write
  **both**: a 32-bit program and a 64-bit one must see the same machine, and 2
  of 2 real installers surveyed here are 32-bit.
- **`#arch=win32` / `#arch=win64` is on line 4 of `system.reg`**, `user.reg` and
  `userdef.reg`, and until 4.2 nothing in the tree read it (`grep -rn '#arch'
  src/ tests/` → zero). A 64-bit program in a 32-bit environment is the one
  failure decidable *before* running anything, and it was the one only ever
  diagnosed afterwards, by grepping English (`32-bit installation`) out of
  Wine's log. `t_prefixo_arquitetura` returns **0 when Wine declared it and 2
  when it was deduced from the folder layout** — and a refusal may rest on 0
  only. Refusing to open a working program on a guess would be worse than the
  defect being fixed, which is the same rule `t_dll_no_prefixo` follows.
- **`winetricks` SOURCES an argument matching `*.verb` as a shell script**, from
  the current directory — read it in the shipped file, at the command-line loop:
  `case ${verb} in */*) . "${verb}" ;; *) . ./"${verb}" ;; esac`. And
  `executar()` in `tandem-exe` does `cd -- "$(dirname -- "$PROG")"` **outside a
  subshell**, so by the time winetricks runs, the current directory is the
  folder that was double-clicked. Until 4.2 `t_verbo_valido` allowed a dot and a
  leading dash, so a zip carrying `setup.exe`, `evil.verb` and a recipe naming
  that verb was arbitrary code as the user — through `tandem receita
  --importar`, the feature whose own header says to accept the file from other
  people. **Zero of winetricks' 538 verb names contain a dot**, so refusing it
  costs nothing; a leading dash is how `--self-update` got in. Do not loosen
  that character set, and do not assume the charset is the whole check: the two
  holes were in the *shape* of the name.
- **A verb from outside may install a dependency and never change a setting.**
  winetricks labels its own verbs and **112 of them are `settings`** — `sandbox`
  and `isolate_home` remove the prefix's links to `$HOME`, `remove_mono` takes
  .NET out, `winxp`/`win95` move the Windows version under an installed
  program's feet. All of them are valid names, install cleanly, and earn a
  permanent receipt under rule №4. `t_verbo_de_fora_ok` asks the installed
  winetricks (`^w_metadata <verb> settings`) rather than carrying a list, so it
  keeps working as winetricks changes; the hard-coded names are only the
  fallback for when winetricks cannot be read. `alldlls` is declared
  `alldlls=default` / `alldlls=builtin`, so the bare name is not a verb and the
  `=` is already outside the character set.
- **`systemd-inhibit` exists and does not work without D-Bus.** It exits 1 and
  takes the wrapped command down with it; `winetricks` never even ran. Exercise
  it before using it (`t_inibidor`), do not ask whether the binary exists.
- **`t_texto` reads its content from STANDARD INPUT**; the argument is only the
  window title. Passing the text as the argument makes the command run, exit 0
  and print nothing — it happened to five commands at once, and no test caught it
  because every test exercised libraries, never a whole command. There is a test
  now that runs each command and demands output.
- **`winetricks -q` exiting 0 does not mean the file arrived.** It reports that
  *it* finished. With a wrong entry in the table, the verb installed something
  else, exited 0, and the receipt was written exactly as for a correct install —
  and a receipt is permanent under rule №4. On the next attempt Tandem said "I
  already installed what this program was asking for" and gave up, with the real
  cause untouched. Since 3.3 there is delivery proof: the requested DLL is
  checked in `system32`/`syswow64` before the receipt is written. **Absence of
  proof does not condemn** — only a proven contradiction holds the receipt back,
  because not every verb delivers a same-named DLL.
- **That proof computed three outcomes and recorded NONE of them until 4.11**,
  and the shape of the miss is worth more than the fix. The check was correct,
  it ran on every install, and its answer went nowhere: the memory recorded only
  whether the OWNER answered. So "I verified the missing file arrived, in the
  right width, and he closed the window without clicking" and "there was nothing
  I could check and he closed the window without clicking" both came out
  `so-abriu` — and both travelled to another machine, in a recipe and in a list
  record, as the same word. **A measurement that is never written down is not a
  measurement**; look for this shape wherever a function returns a rich verdict
  and its caller keeps a boolean.
  `PROVA=` now carries four levels, and only one of them becomes a confidence:
  `entregue` (proven to arrive, correctly) is a level of its own, while
  `bitola-errada`, `nao-chegou` and `sem-alvo` stay in the memory file because
  they say nothing another machine can use. **`sem-alvo` is deliberately not
  `entregue`** — half the winetricks verbs have no same-named DLL in the table,
  and "I could not check" is not "nothing was wrong".
  **The list weighs `entregue` at HALF a report**, and the arithmetic is the
  argument: it is evidence about the FILE, and the question the list answers is
  about the PROGRAM. Sixty people who looked at a screen outweigh a hundred
  proven deliveries; two hundred proven deliveries outweigh sixty people. Both
  directions are tests, so the constant cannot be quietly rounded to 1.
- **The ordering of those four levels is `t_prova_do_run`, in the library, and
  it was inline for exactly one revision.** Inline it was a plain assignment, so
  the LAST DLL of the LAST verb spoke for the whole run and a wrong-width found
  after a missing file reported the milder of the two — the same shape as the
  `MARCA_WT` defect 4.8 fixed one screen higher. The rule this keeps producing:
  **when a loop accumulates a verdict, the resolution belongs in a function that
  can be called with the cases in either order.**
- **The executables honour `TANDEM_LIB`** when locating the libraries
  (`. "${TANDEM_LIB:-/usr/lib/tandem}/common.sh"`). With the path hard-coded
  there was no way to exercise the run→detect→install loop without installing the
  package, and the whole suite stopped at the library level.
- **`shared-mime-info` already knows the two native types.** `application/vnd.appimage`
  (glob priority 60) and `application/x-iso9660-appimage` (50) for AppImage,
  `application/java-archive` for `.jar`. No new MIME XML was needed - only
  `.desktop` files claiming them and `tandem-repair` winning the dispute. A
  `.jar` is disputed by the system's own Java launcher; an AppImage usually has
  **no owner at all**, which is why the click does nothing.
- **An AppImage's payload offset is computable from the ELF header**:
  `e_shoff + e_shentsize * e_shnum`. Verified against the runtime's own
  `--appimage-offset` on a real file: 944632 both ways, with nothing executed.
  The squashfs superblock sits at that offset (magic `hsqs`) and its `bytes_used`
  at superblock offset 40 - so `offset + bytes_used > filesize` proves an
  interrupted download without running anything.
- **`--appimage-extract` does NOT need FUSE.** Measured with `/dev/fuse` moved
  away: the plain run exits **127** printing `Cannot mount AppImage, please check
  your FUSE setup`, while `--appimage-extract` and `--appimage-extract-and-run`
  both still work. That is why the menu-entry extraction works on exactly the
  machines that have no FUSE, and why the workaround needs nothing installed.
- **`libfuse2` was renamed `libfuse2t64`** in the 64-bit `time_t` transition, so
  the install has to try both names. Ask the loader (`ldconfig -p`) about
  `libfuse.so.2`, never `dpkg` about a package name.
- **Class file major minus 44 is the Java version.** 52 = Java 8, 65 = Java 21.
  Checked against a real JVM: a class bumped to 66 is refused with `class file
  version 66.0, this version of the Java Runtime only recognizes class file
  versions up to 65.0`. **Classes under `META-INF/versions/` must be excluded**
  from the maximum - they are the multi-release mechanism, present so a NEWER
  Java picks them up, and counting one marked 74 announced "needs Java 30" for a
  jar that runs fine on 21.
- **`java -version` writes two different shapes**, and the split matters:
  `1.8.0_412` is Java 8, `21.0.10` is Java 21. Reading only the first number
  turns Java 8 into Java 1 - and then Tandem refuses a program on a machine that
  runs it perfectly. It also prints to **stderr**, and with `JAVA_TOOL_OPTIONS`
  set in the environment it prints a paragraph of proxy settings FIRST, so
  `head -1` puts that paragraph in the middle of `tandem doctor`. Grep for
  `version "`.
- **A `.jar` manifest folds at 72 bytes** and continues on a line starting with a
  single space, splitting file names down the middle. A `Class-Path` read line by
  line yields paths that do not exist. Values are also CRLF-terminated.
- **A truncated `.jar` is always detectable**, because a zip's index lives at the
  END of the file. `zipfile.BadZipFile` is therefore the signature of an
  interrupted download, not of a corrupt program.
- **`zipfile.writestr` MUTATES the `ZipInfo` you hand it** (`header_offset`,
  `CRC`, sizes). Passing the source archive's own objects while copying entries
  corrupts the source mid-loop - "Bad magic number for file header" on the next
  read. It silently made a multi-release test build the wrong file, so the case
  it existed for was never exercised. Copy the bytes, write by name.
- **The first-run mark has to record the VERSION, not just existence.** It was an
  empty file, so "already run once" meant "never again" - and a machine upgraded
  from a version that did not know a format never claimed it. Reproduced by
  installing 3.7 over 3.6: `.jar` still answered `openjdk-21-java.desktop`. Fixed
  by writing `$TANDEM_VERSAO` into the mark and running `tandem-repair
  --somente-novos`, which claims only types absent from
  `~/.config/tandem/tipos-aplicados.txt`. Whoever adds a sixth format must add
  its types; the upgrade path is what makes them reach an existing user.
- **`case " $LIST " in *" $x "*)` does not work on a NEWLINE-separated list.** The
  MIME type lists in `tandem-repair` are newline-separated, so the pattern
  matched nothing and every type was written as `type=` with an empty handler -
  which reads to the system as "no default". Loop over the unquoted variable
  instead; word splitting handles both separators.
- **`openjdk-<n>-java.desktop` owns `application/java-archive`** on any machine
  with a JRE installed. It is a real rival, unlike the AppImage case where the
  type usually has no owner at all.
- **`apt-get install -s` RUNS UNPRIVILEGED** and returns apt's own authoritative
  verdict, unmet dependency names included. Measured as a non-root user. This is
  the single most important fact behind `tandem-deb`: the entire diagnosis happens
  before the password is asked, so nobody types a password to be told no.
- **NOBODY owns `.deb`, `.rpm`, `.flatpakref` or `.snap`** on the reference
  machine - `xdg-mime query default` answers nothing for all four. The double
  click does nothing at all, the AppImage situation exactly. On a full desktop a
  store claims `.deb`; what the store handles badly is the third-party package
  built for another release, which is the case that brings somebody here.
- **Every current Ubuntu `.deb` uses `control.tar.zst`**, and neither the `zstd`
  command nor `python3-zstandard` is installed by default - only `libzstd1`,
  because **dpkg pre-depends on it**. So a pure-Python reader handles almost no
  real package, and the way through is `ctypes` on `libzstd.so.1`
  (`ZSTD_getFrameContentSize` + `ZSTD_decompress`); dpkg writes the content size
  into the frame header, so the one-shot path is enough. Cap the declared size:
  a decompressor told to allocate a hostile number takes the machine down.
- **The real apt messages, copied off a terminal** (do not paraphrase these):
  release mismatch is `Depends: libssl1.1 but it is not installable` +
  `E: Unable to correct problems, you have held broken packages`; wrong
  architecture is `package architecture (arm64) does not match system (amd64)`;
  the lock is `E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by
  process N` and dpkg's own wording is `dpkg frontend lock was locked by another
  process with pid N`. **The lock has to be tested FIRST**: it appears together
  with the broken-packages line, and it is the cause while the other is the
  consequence.
- **The lock is held with a POSIX lock, not flock.** `flock(1)` on
  `/var/lib/dpkg/lock-frontend` does NOT stop apt; `fcntl.lockf` does. Getting
  that wrong makes a lock test pass while proving nothing - it happened here.
- **A `.deb` truncated exactly on a member boundary parses cleanly.** The ar walk
  ends without error and the control it already read looks perfect. Requiring a
  `data.tar*` member is what makes the truncation verdict a verdict rather than
  luck about where the cut landed.
- **Declaring a MimeType in a `.desktop` CLAIMS the type.** With no explicit
  default recorded, the desktop database picks a handler from the declarations.
  Measured: `application/x-shellscript` belonged to a text editor, and merely
  naming it in `tandem-script.desktop` moved it to Tandem. That is why the file
  has no `MimeType=` line and a comment saying why - the decision lives in the
  absence of one line, which is exactly what somebody tidies up later. There is
  a test.
- **`t_pergunta` cannot tell "the owner said no" from "there was nobody to ask".**
  Only the first may be silent. Three refusal paths in the new handlers exited 0
  with zero bytes; the `.flatpakrepo` one was found by running every handler
  against every fixture with no window and no terminal and demanding a sentence.
  Guard every refusal with `t_tem_gui ||`.
- **Some `.apkm` files are ENCRYPTED by the site that distributes them**, and
  only that site's own installer opens one. Detected from bit 0 of the zip
  general-purpose flag (`ZipInfo.flag_bits & 0x1`), and the check has to come
  BEFORE any `z.read()`: reading an encrypted entry raises a Python exception in
  English about a missing password, which is exactly the shape of failure this
  project treats as a defect. `zipfile` cannot write one, so the fixture sets the
  flag by hand in both the local headers and the central directory.
- **The list only ever pulled, and the measurable consequence is that
  `lista/lista.tsv` is EMPTY.** Contributing meant five steps ending in a GitHub
  account. Since 3.9 sending is automated, and **since 4.2 it is ON BY DEFAULT**.
  That reversal is the architect's call and its justification is the measurement
  above: born off, the list stayed empty, and a default nobody changes is a
  decision made by the default. What makes it defensible is not the default, it
  is the two things around it: `t_lista_vaza` refuses to emit a record carrying
  a filename, a path, a username, a machine name or an IP - so there is nothing
  to anonymise at send time - and the owner is TOLD twice, by `postinst` at
  install and again on the first real send, with the line displayed in full.
  The sieve runs AGAIN before the POST, because the queue is a plain-text file
  and those get edited by hand.
  **The remaining exposure is honest and worth writing down:** an HTTP POST
  carries an IP at the receiving end whatever the payload says, and the
  fingerprint identifies WHICH software a shop runs. Neither is in the record;
  both are inherent to sending anything at all.
- **The DOWN path had never been asked what it does with more than one row about
  the same file**, and that is the normal shape of a merged list rather than a
  corner. `t_lista_consulta` printed the first `confirmado` row and exited, so
  the earliest report owned a program for ever — measured: 3 machines beat 400.
  It also never added two rows with the same verbs up, which is the entire job
  of the machine count; it never read the `reprovado` rows at all, so 2
  confirmations beat 300 rejections; and `t_lista_maquinas` did not filter by
  confidence, so a rejected row above a confirmed one supplied the number the
  owner is shown to decide with — verbs from 40 machines, presented as 7. Since
  4.4 one resolver (`t_lista_linha`) answers both questions, so the verbs and
  the count cannot come from different rows, and `docs/LIST-FORMAT.md` states
  the four rules. The whole class of bug is one thing: **a query written for a
  file with one row per program, against a format whose point is merging.**
- **`grep -c` on an EMPTY file prints 0 and then exits 1**, so `grep -c ... ||
  echo 0` prints "0" twice. It reached the owner as a queue length of "0\n0".
  Use `awk 'END { print NR + 0 }'`.
- **`curl` WITHOUT `-L` RETURNS 0 ON A 301**, and that made a redirect count as
  a delivery. `t_envio_envia` rewrites the queue from what did *not* go, so the
  line was deleted from the only place it existed — and an endpoint that has
  moved is exactly the shape of thing that answers 301. Read the code
  (`-o /dev/null -w '%{http_code}'`) and require `2??`. `wget` loses the same
  line by the opposite mechanism: it FOLLOWS redirects by default and turns the
  POST into a GET on the way, exiting 0 having posted nothing — hence
  `--max-redirect=0`. Neither one follows a redirect on purpose: the target is
  chosen by whatever answered, not by anybody here, and a record exists
  precisely because it carries nothing personal.
- **A cap on successes is not a cap.** `TANDEM_ENVIO_POR_DIA` only ever counted
  the lines that WENT, so a failure cost nothing: a machine with no route to
  the address retried every queued line on every run, for ever, at 20 s of
  timeout each. A hundred queued lessons is over half an hour of a background
  process that was never going to succeed, restarted every time somebody opens
  a program. Count the refusals too, and make the queue wait.
- **Two sends could run over the same queue at once**, and this was the ordinary
  case rather than a corner: one is spawned detached every time a program is
  confirmed, and `tandem enviar agora` starts another. Both truncate the same
  `.resto` file and both then move it over the queue, so the truncation lands in
  the middle of the other pass's appends and the lines already written are gone.
  The queue is the only copy of a lesson that has not left yet.
- **Nine handlers, and only one of them still took `exit 0` as proof.** An audit
  worth repeating whenever a tenth format arrives: `tandem-deb` asks dpkg's
  database, `tandem-snap` asks `snap list`, `tandem-apk` parses waydroid's output
  and then asks Android's own `pm list packages`, `tandem-rpm` never installs,
  and the three that run a program ask the owner. `tandem-flatpak` had the right
  check and used it backwards — `exit 0 OR flatpak agrees` — so a 0 was proof on
  its own. And `tandem-script` had nothing to ask, which is why it was left: a
  shell installer has no database behind it. **The evidence it does have** is the
  same the silent-success guard uses: finishing almost at once having printed
  nothing at all. No case was found where `flatpak install` exits 0 without
  installing (a failed install exits 1, measured against flatpak 1.14.6), so
  that half is a consistency fix and not a caught lie — worth saying plainly.
- **`t_palavras_do_programa "$LOG"` shows TANDEM'S OWN LOG to the owner.** The
  success path of `tandem-script` printed "this is what it said" followed by
  `reconhecido como script comum` — an internal Portuguese line — because it
  passed the whole log instead of the slice after `MARCA`. The failure path a few
  lines below had always sliced it. Two consequences, and the second is the
  interesting one: a log carrying Tandem's own lines is never empty, so **any**
  guard conditioned on "the program said nothing" was dead code before it was
  written. Found by running a script that does nothing and reading the output.
- **The list has a receiver now, and the shape of it is the decision worth
  keeping.** Both ends live in this repository — `api/lista.js` receives,
  `lista/lista.tsv` is served — deployed to a Vercel project git-linked to the
  repo, so a push deploys the endpoint. **No secret is created by hand anywhere
  in the chain**: Vercel injects the Blob credential when the store is
  connected, and the rebuild reads a public URL. Every alternative design ended
  with somebody pasting a token somewhere, and that was the requirement.
  It was deliberately NOT put in the owner's existing Supabase project even
  though that was free: it is a live gym system holding real student health
  records, and an anonymous internet-facing write endpoint does not belong
  beside them — rule №1 applied off the Wine prefix.
- **`res.type()` does not exist in Vercel's Node runtime** (it is Express).
  Every response path in the intake went through one call to it, so the function
  answered 500 to everything, including the GET that refuses before touching
  anything. The runtime stack trace named it; guessing would not have.
- **A 4xx is not a failure of the route, and treating it as one poisons the
  queue.** The far end saying *this line is wrong* will say it for ever, so
  keeping the line meant retrying it on every pass — and three permanently
  refused lines would trip the hour-long wait that exists for a broken network,
  stopping the GOOD lines from leaving. A 4xx now parks the line in
  `.recusados`; 429 and 408 stay retryable, because too fast and too slow are
  about the moment rather than about the line.
- **Counting machines honestly is impossible without keeping something that
  identifies the sender**, so the list counts REPORTS. "We only store a hash"
  does not survive contact with a laptop: a hash of an IPv4 address is an IPv4
  address to anybody willing to try four billion of them. The field kept its
  position; the claim shrank, in `docs/LIST-FORMAT.md` and in the sentence the
  owner reads, which said *machines* in all seven languages until 4.6.
- **A reason cannot travel in a variable out of `$( )`.** `t_envio_envia` is read
  through a command substitution, which is a subshell, so the count goes on
  stdout and *why* goes in the exit status (3 refused, 4 waiting, 5 already
  running). Without that, the far end refusing everything reached the owner as
  `0 line(s) sent` — which reads as a defect on his own computer.
- **A `while read` loop drops the last line of `od` output**, which has no
  trailing newline - so the URL escaper cut the final character off everything.
  Loop with `for` over the unquoted substitution instead.
- **CORRECTED, 2026-08-09: Waydroid DOES have a route to USB, and the README was
  wrong about the mechanism.** Its LXC config carries no `lxc.cgroup.devices.deny`
  at all, so the container is not the barrier. The barrier is that AOSP only
  instantiates `UsbHostManager` when the platform declares
  `android.hardware.usb.host`, and Waydroid's image does not - so
  `getDeviceList()` is empty whatever exists under `/dev`. Waydroid also ships
  `persist.waydroid.uevent`, a maintainer feature for exactly this, and Waydroid
  bind-mounts `/var/lib/waydroid/host-permissions` over
  `vendor/etc/host-permissions`, where the declaration can be dropped without
  editing the image. Two people published working procedures.
  **It stays rejected anyway**, for durability and rule №1 rather than for
  nonexistence - see `docs/IDEAS.md`. And the empirical part survives: nobody in
  any language has reported a thermal printer, a pinpad or a scale working inside
  Waydroid.
- **A barcode scanner already works inside Waydroid and always did.** It is a USB
  HID keyboard and the compositor delivers its keystrokes. The real bug is that
  it can type each code TWICE when `persist.waydroid.uevent` is on (Waydroid
  issue #778). The README told those owners their scanner could not work.
- **`android.hardware.usb.gadget` is NOT `android.hardware.usb.host`.** The "Usb
  HAL not found" line in Waydroid issue #1512 is the gadget (peripheral-mode)
  HAL and is irrelevant to host mode; reading it as proof that host USB is
  impossible is the mistake behind the old claim.
- **Android Translation Layer is WORSE here, not better.** No container, so the
  premise dissolves - but its `UsbManager.getDeviceList()` is a hard stub
  returning an empty map. Source-proven, not inferred.
- **An AppImage can be read WITHOUT executing it**, and until 3.9 this was the
  one place the project broke its own rule. `unsquashfs -o <offset>` reads the
  payload straight out of the file at the offset already computed from the ELF
  header - verified by reading the author's `Name=` out of an AppImage whose
  execute bit had been removed, which is proof it was not run. Borrowed from Gear
  Lever, which refuses to execute the payload for the same reason. Falls back to
  the runtime's `--appimage-extract` when squashfs-tools is absent, and the log
  says which route it took, because "we did not execute it" has to be checkable.
- **There is a SECOND family of tools, and it is not a rival — it is the exit
  from our dead ends.** WinApps, WinBoat and Dockur/windows boot a **real
  Windows in QEMU/KVM** (in a Docker/Podman container, or under libvirt) and use
  **FreeRDP + the RemoteApp protocol** to composite one application's window
  onto the Linux desktop. Because the kernel is real, a `.sys` driver loads for
  real and a legacy dongle can be handed over with QEMU's
  `-device usb-host,vendorid=…,productid=…`. That is exactly what `limites.tsv`
  calls impossible. **The cost every article omits: the guest must be Windows
  Pro or Enterprise** — Home cannot host Remote Desktop at all, so the OEM
  licence on a counter machine does not serve — plus KVM enabled in the BIOS,
  ~4 GB RAM and ~32 GB disk. Since 4.0 Tandem NAMES this route at a dead end,
  after checking whether the machine could carry one (`t_vm_possivel`), and
  excludes anti-cheat, which refuses VMs by design. **Tandem will not install
  or manage one** — see `docs/IDEAS.md`. PlayOnLinux is in the *first* family
  (Wine plus hand-written per-program scripts) and its own README points at a
  successor that has been "under development" for years. Parallels is
  macOS-only; Parallels Workstation for Linux was discontinued in 2013.
- **`apkfile` DOES read minSdkVersion and the native ABIs** before installing
  (`david-lev/apkfile`, on PyPI: it calls `install_apks(check=True)`, reads
  `ro.build.version.sdk` and `ro.product.cpu.abilist` off the device and
  filters base and split APKs against both). So "nobody checks" is false. What
  it does when the check fails is `continue  # skip device if no compatible
  apks found` — it exits **silently, with no output at all**. The one project
  that had the data in hand commits the exact silence this project calls a
  bug. The defensible claim is **nobody turns the check into a sentence**.
- **The `.jar` rival on Ubuntu changed under us.** `openjdk-NN-java.desktop`
  runs `cautious-launcher %f /usr/bin/java -jar`, and `cautious-launcher` was
  **rewritten on 2026-07-08** (USN-8518-1 / CVE-2026-10037, CVSS 8.8). The
  rewrite **deletes the executable-bit test** the old 17-line version had. Any
  description of that handler written before July 2026 is stale — check the
  shipped file, not an article.
- **`xdg-mime` IS THE WRONG INSTRUMENT for "who owns this type".** Nautilus uses
  GIO, and GIO resolves the MIME **subclass chain** while `xdg-mime` does not.
  Proven on a type Tandem never touches: `gio mime text/sgml` answers
  `vim.desktop`, `xdg-mime query default text/sgml` answers nothing.
  `application/vnd.flatpak.ref` is declared `sub-class-of text/plain`, so with
  Tandem's association removed a double-clicked `.flatpakref` **opens in a text
  editor** — not "does nothing", which is a different and worse failure.
  `.deb`, `.rpm` and `.snap` are not subclasses of `text/plain` and really do
  answer nothing. **And Zorin is not a vacuum for `.deb`**: Zorin's own
  documentation tells the user to double-click it and get the Software store,
  so that is a dispute, exactly like `.exe`.
- **The closest competitor is already installed on the reference machine.**
  `zorin-exec-guard` ships two `NoDisplay=true` MIME handlers — one claiming
  `.exe/.msi/.msix`, one claiming `.deb/.AppImage` — backed by an `app_db.json`
  of 240+ apps, translated into 90 languages including pt_BR. It matches
  installer filenames with regexes and suggests a native alternative. It never
  runs anything, never diagnoses and never fixes. So on Zorin the association
  dispute has four sides, and the incumbent's Portuguese is already written.
- **A modern PC has THIRTY-TWO serial ports and none of them are real.**
  Measured on the reference counter, not deduced: `grep -h .
  /sys/class/tty/ttyS*/type | sort | uniq -c` answered `32 0`. The kernel's
  8250 driver registers 32 lines whether or not any UART sits behind them,
  udev makes a node for each, and `0` is `PORT_UNKNOWN` - the kernel probed
  and found nothing. `src/lib/common.sh` used to say "a PC already has three
  or four `/dev/ttyS*`", and that wrong number is why `tandem portas` listed
  32 sockets a shopkeeper could plug a pinpad into on a machine that has zero,
  and put the shop's one real device - a USB adapter - on **COM33**.
  The discriminator needs no privilege: `/sys/class/tty/ttySN/type` is mode
  444. **Wine counts the phantoms too**, so the report must keep the high
  number rather than renumbering to COM1 - verified against real Wine, whose
  `wineboot` created `com1 -> /dev/ttyS0` on a machine whose one `ttyS` is
  genuine. What moves the device is `tandem portas fixar COM2 /dev/ttyUSB0`.
- **`CreateFile("COMx")` in Wine resolves through `dosdevices/comN`, NOT through
  `HKLM\Software\Wine\Ports`** - and until 4.25 `tandem portas fixar` wrote only
  the registry key. Measured with real Wine and a real char device through a
  PTY: with only the `Ports` value set, opening `COM3` returned "File not
  found", byte for byte a port that was never mapped; adding the symlink
  `dosdevices/com3 -> /dev/ttyUSBx` made the same open succeed. The registry key
  is the OTHER half and worth keeping - it populates `SERIALCOMM`, which is what
  a program reads to LIST the ports in a dropdown. **The symlink makes it OPEN;
  the registry makes it APPEAR.** So the one command this file documents as the
  printer/pinpad remedy reported success and opened nothing - the silent failure
  the project exists to abolish, hidden in the fix for the previous one. This is
  the mechanism `wineboot` uses for auto-detected ports (`com1 -> /dev/ttyS0`
  above), so `fixar` now does by hand exactly what Wine does on its own.
- **`E: Unsupported file X given on commandline` from apt means the file is
  NOT THERE**, not that the package is broken. Measured against a real apt:
  a valid `.deb` installs, a truncated one and an HTML error page both give
  `Could not read meta data`, and only a missing path (or an unrecognised
  extension) gives `Unsupported file`. Cost a field session to a package that
  was intact all along.
- **Waydroid is not in the Ubuntu/Zorin repositories.** `apt-cache policy
  waydroid` answers `Candidate: (none)`. It comes from `repo.waydro.id`, with a
  signing key.
- **`: >> file` SUCCEEDS ON A FULL FILESYSTEM.** Opening for append allocates
  no blocks, so ENOSPC never fires — measured on a full 16k tmpfs: the empty
  append succeeds and one byte fails. `t_log_init` used that as its "can I
  write the log?" probe, so it answered "writable" and the very next line
  failed. Any writability check has to write a byte.
- **A REDIRECTION that fails is reported by BASH, before the redirection is in
  place.** `printf ... >> "$LOG" 2>/dev/null` silences *printf*; it does not
  silence `bash: line 49: ...: No space left on device`, because stderr is not
  yet /dev/null when the `>>` is attempted. Wrap the whole thing:
  `{ printf ... >> "$LOG"; } 2>/dev/null`. Same family as the `exec` trap two
  bullets up, and it reached the owner as the first line on his screen.
- **THE LOG IS SHARED, so a slice is not a capture.** One log file per handler,
  no PID in the name, so two `.sh` files double-clicked a second apart both
  write `script.log`. A marker fixes where a slice STARTS and cannot keep
  another process's lines out of the middle. Measured: the installer that
  printed *nothing at all* was reported to its owner as "this is what it said:"
  followed by the other program's progress lines, and the silent-success guard
  was defeated at the same moment, a slice with somebody else's lines in it
  never being empty. **The child's output must go to a file of that run's own**
  (`t_saida_abre`/`t_saida_fecha`), with the log getting a copy afterwards.
- **RULE №1 WAS BREAKABLE THROUGH A SYMLINK until 4.19**, and this is the only
  time the inviolable rule has actually been broken. `t_prefixo_protegido`
  compared paths as TEXT, so with `~/.local/share/tandem/wine` a symlink to
  `~/.wine-pdv` Tandem registered the production prefix as protected, wrote
  `protegido: .../.wine-pdv` in its own log, and then ran a winetricks verb
  **into it**, leaving its receipt and `.tandem-assoc` behind. Compare PLACES,
  both sides resolved, in both directions. Pointing a new tool at the Wine
  setup you already have is the first thing a person tries. The file-side paths
  were always safe, because `tandem-exe` does `readlink -f` on its argument
  before walking up the tree.
- **A COMMUNITY-LIST ROW DATED IN THE FUTURE won every tie-break, for ever** —
  the tie-break is "most recently seen wins", and ten reports from this month
  lost to ten dated 2099. It needs no attacker, only a shop with a wrong clock,
  which this project already detects from Wine's certificate errors.
  `api/lista.js` refuses such a record on the way IN and its comment states
  exactly this harm — **so the guard existed on the write side only**, and the
  file is downloaded. A reader that trusts the file because the writer checked
  is a reader with no check.
- **A GUARD SCOPED TO THE FILE WHERE THE DEFECT WAS FOUND cannot see the file
  where it also lives.** The test forbidding line-count log slicing read
  `tandem-exe` and nothing else, while six other handlers still used the
  technique it exists to forbid. Same shape as the literal counter's thirteen
  misses. When a guard names a file, ask why it is not a glob.

## State

Verified **on real Linux** (Ubuntu 24.04 noble, the same base as Zorin 18, with
root), no longer only by reading:

- **FIELD TEST, 2026-08-19 — the installed `.deb` run against real Wine 9.0 and
  a real CUPS printer, prompted by the owner (*"instala alguma impressora
  virtual com driver genérico e testa"*).** What passed, on the INSTALLED
  package: a real PuTTY `.msi` and a real WinDirStat `.msi` both installed
  through Tandem via real `msiexec` (the 4.39 routing, confirmed by the programs
  actually landing in `Program Files` — `wine file.msi` would have failed);
  PuTTY's full Configuration window rendered on screen under Xvfb;
  `peinfo.py` read the real WinDirStat binary's imports; `tandem portas`
  detected a real `/dev/usb/lp0` node and fired BOTH the dialout and the lp-group
  (4.33) warnings with the exact one-time fixes; `tandem portas fixar LPT1
  /dev/usb/lp0` and `fixar COM2 …` each wrote BOTH halves (the `dosdevices`
  symlink AND the registry value — the 4.25/4.38 fix); a generic CUPS virtual
  printer printed a test job to PDF; and **Wine 9.0 enumerated the CUPS printers
  into the prefix registry**, so a POS program under Wine would find the shop's
  printer. `doctor`, `saude`, `relogio`, `versao`, `memoria`, `autoteste`
  (17/0) all produced correct output. Three findings came out of it: (1) the
  4.40 defect — a successful fast installer branded a flash-and-vanish failure;
  (2) **Wine 9.0 ships `msvcp140`/`vcruntime140` as BUILTIN DLLs** (the offset-64
  marker confirms it), so a VC++ program does NOT trigger the dependency loop on
  modern Wine — the loop fires only for a DLL Wine genuinely lacks (MFC, older
  runtimes); this is the "arriving is not arriving at all if Wine put it there"
  insight, now measured on Wine 9.0 rather than inferred; (3) minor — `tandem
  doctor` prints a blank `service:` value on a host with no systemd (the
  `systemctl is-active waydroid-container` substitution comes back empty), which
  does not occur on the owner's systemd counter but is a silent-blank gap.
- The `.deb` written by hand by `build.py` is accepted by a real `dpkg`:
  `dpkg-deb --info/--contents`, `dpkg -i`, `dpkg --configure`. It installs,
  configures and uninstalls. Reproducible build (two builds, same cksum).
- `lintian` clean: zero errors, zero warnings.
- `postinst` on the per-user path: it protected, on its own, the three
  pre-existing Wine prefixes (`~/.wine`, `~/.wine-pdv`, `wineprefixes/*`).
  **Rule №1 confirmed end to end.**
- `tandem-repair` against a competing `gnome-mimeapps.list`: it removed the
  disputed entries, preserved someone else's `text/plain`, wrote to
  `mimeapps.list`, and left a backup.
- `tandem doctor`, `version`, `--help`, the panel with no GUI: all produce
  output.
- zenity windows really do open (verified under Xvfb), accents included.
- Real Wine installed in the container: a `win64` prefix created from scratch,
  7-Zip x64 installed from both `.exe` and `.msi`, registry inspected by hand.
- **The run→detect→install loop closed successfully with real tools.** A
  hand-forged 32-bit PE importing `mfc42.dll` (a DLL Wine does not implement,
  cross-checked against `objdump` before use): detected, installed, the DLL
  landed in `syswow64`, the bitness matched, the second attempt exited 0, memory
  recorded `RESOLVERAM=mfc42` and `CONFIRMADO=sim`, and the recipe came out
  marked `CONFIANCA=confirmado`. The same test with a 64-bit PE produced the
  bitness dead end and the message that explains it.
- `tandem dados` listing and copying real files out of a prefix; `tandem socorro`
  producing its report; the bitness warning appearing in the dialog *before* the
  download.
- **The 4.2 identity fix closed end to end on a real prefix.** `wineboot`
  created a `win64` prefix and minted `MachineGuid=1a2dea1e-…` on its own;
  `t_identidade_fixa` replaced it with the seed-derived `7e4fe22d-…` **in both
  registry views**, the mark file recorded the same value the prefix now holds,
  a second call left everything alone, and the same call against a prefix
  without `.tandem-prefixo` returned 1 and wrote nothing. Before the fix that
  half had never run at all.
- **The builtin discriminator closed on the real case.** On a real prefix with
  no .NET, `t_dll_do_verbo dotnet48` → `mscoree.dll`, both copies of which Wine
  had installed, and the delivery proof now answers "not delivered" for 64 and
  32 alike; swapping in a file without the marker flips it back to "delivered".
- 1500 automated tests in `tests/run.sh`; CI on GitHub Actions.
- **Seven defects were found in 4.19 by RUNNING the program in conditions it
  had never been run in**, and none of them by reading code: a full disk, an
  interrupted double click, two double clicks at once, a symlinked prefix, a
  broken state folder. Each fix is proven by putting the defect back and
  watching the assertion speak — including the two occasions where the
  assertion had to be rewritten because it passed on the defect (an unmarked
  prefix reaches "protected" through the fall-through anyway; `$$` in a regex
  is two end-of-line anchors and matches nothing).
- **Five sweeps held with nothing to fix, and they are worth as much as the
  seven** because they cost the same time and stop the next session repeating
  them: all nine handlers against eighteen hostile file names (command
  substitution, backticks, semicolons, pipes, globs, leading dashes, embedded
  newlines, five scripts) executed nothing and were silent nowhere; every CLI
  command with and without a usable state folder; rule №1 reached from the
  FILE side; two double clicks racing on one file; and a recipe filename
  cannot forge a key in the memory file — though **that last defence existed
  by accident**, written for a formatting reason, and is asserted as a security
  property now.
- **The list's read path was measured against the OLD code before being fixed**,
  which is why the four defects are stated as numbers rather than as risks: on a
  two-row list the old query answered `vcrun2010` with 3 machines where 400
  confirmed `vcrun2022`; two rows carrying the same verbs answered 200 instead
  of 400; a rejected row above a confirmed one supplied "7 machines" for verbs
  40 machines had confirmed; and 2 confirmations beat 300 rejections.
- **`curl -fsS -X POST` against a real 302 exits 0** — measured against a local
  server, which is what made a redirect count as a delivery and delete the
  queued line. And old `wget` against a *reachable* redirect target exits 0
  while the target receives `GET` with an **empty body**: the record was never
  posted, and the request went to a host the server chose rather than us. With
  an unreachable target wget exits 4, which looks like a safe failure — so the
  claim only holds when the target answers, and that is the case that matters.
- **The readers' messages closed on real malformed files**, in two languages: a
  text file named `.deb`, a text file named `.rpm`, a truncated `.jar` and an
  ELF named `.AppImage` each produced a translated sentence, and the log carries
  the `leitor: <token>` line beside it. The raw-exception path is covered by the
  helper test rather than end to end — as root there is no file the reader
  cannot open.
- **`tandem repair`'s report comes out in the machine's language** — checked in
  en, pt_BR, fr and zh_CN on a real run, `nobody` included.
- **The five remaining formats closed on real files**: a `.deb` built for an
  older release produced the release-mismatch verdict with `libssl1.1` and
  `libicu70` named and **no password asked**; an arm64 package produced the
  processor verdict; a truncated one the download verdict; a good one installed
  through apt and was confirmed against dpkg's own database. A real Fedora
  `hello-2.12.1-1.fc39.x86_64.rpm` produced "made by Fedora Project" plus
  `sudo apt install hello`, because that package really is in Ubuntu. A real
  Flathub `.flatpakref` and `.flatpakrepo` were read correctly and told apart.
- **The upgrade path works on a real machine**: installing 3.8 over 3.7 claimed
  the five new types and left `.exe`, `.apk`, `.AppImage` and `.jar` alone.
- `tandem autoteste` on the installed package: **17 passed, 0 failed**, including
  the association of all eight claimed types and "apt answers without a password".
- **Real Windows software, run through Tandem, with the window checked on
  screen** (`tests/real-programs.sh`, 26 checks green): PuTTY and Notepad++ x64
  both opened a window with the expected title, screenshots taken; `peinfo.py`
  agreed with `objdump` import for import on all four binaries; Brazilian CP1252
  text rendered correctly in the editor. It also established a fact the README
  had wrong: **2 of 2 real installers are 32-bit**, even the one that installs
  64-bit software, which makes `wine32` far more important than it looks.
- **`tandem desinstalar` cleans up its orphan shortcuts.** Confirmed on real
  Wine with 7-Zip really installed: both `.desktop` files removed, the empty
  folder pruned, the log line written (`2 atalho(s) orfao(s) removido(s)`), and
  the registry key gone. An earlier session reported this as a defect; the cause
  was a `timeout 200` in the test killing the command before cleanup ran.
- **The native formats closed end to end on a real AppImage built by the real
  `appimagetool`**: the execute bit went from `-rw-r--r--` to `-rwxr-xr-x`, the
  program ran, the menu entry was written from the AppImage's own desktop file
  (with its author's `Name` and `Categories`, and accepted by
  `desktop-file-validate`), the icon was extracted, and the silent-success guard
  fired on its own with "abriu e fechou sozinho".
- **The FUSE workaround closed end to end with `/dev/fuse` actually removed**:
  first attempt failed with the real message, Tandem recognised it, retried with
  `--appimage-extract-and-run`, opened the program, wrote the menu entry, told
  the owner the one-line fix, and recorded `MODO=extrair`. On the next run with
  FUSE present it noticed the reason no longer held and took the fast road again.
- **The Java pre-flight caught a version mismatch before running anything**: a
  jar needing Java 22 on a machine with 21 produced "ele pede o Java 22 e o
  instalado aqui é o 21", with **zero** `UnsupportedClassVersionError` in the log
  - the JVM was never asked.

Verified **on the user's Zorin 18.1** (Wayland, Wine 10.0, Waydroid active):

- `tandem doctor` complete, with the whole environment present.
- The two pre-existing prefixes (`~/.wine` and `~/.wine-pdv`, the POS one) were
  protected **on their own** on first run, without typing anything.
- Double click routing: `xdg-mime query default` answers `tandem-exe.desktop`
  and `tandem-apk.desktop`.
- 7-Zip x64 installed by Tandem: prefix created, installer executed, `.lnk` in
  the Start Menu, `winemenubuilder` generating the `.desktop`.
- **The user's file associations survived intact** — `zip`, `txt`, `jpeg` and
  `pdf` still belong to the Zorin apps, no `wine-extension` anywhere. That is the
  proof of the decision to disable only the hijack via the
  `FileOpenAssociations` key rather than `winemenubuilder` as a whole.
- The accented error window really appears, with the right text.

**Still unverified — needs the real machine:** `pkexec` and the polkit rule (the
Waydroid service was already active, so the rule was never exercised), XAPK
installation on a real Waydroid, the newer commands `preparar`, `programas`,
`desinstalar`, `dados` and `socorro` in the field, and a double click on a real
`.AppImage` / `.jar` from the file manager (the association is applied and the
executables are proven from the command line; what has not been seen is GNOME
routing the click).

Reference environment where the project was born: Zorin OS 18.1 (Ubuntu noble
base), kernel 7.0, x86_64, Wayland/GNOME, 15 GB RAM, Wine 10.0 from the distro
repository, Waydroid 1.6.2 MAINLINE with GAPPS and libhoudini, `binderfs` with
`anbox-*` nodes.

### Miss sixteen, and why the sixteenth widening was not attempted

**The counter read TOTAL 0 while seventy-three sentences were on screen**, and
this is the third false zero — the second one shipped. Nine were found by
reading `src/lib/winedeps.sh` by hand; a six-lens audit of the whole tree then
found **sixty-four more, in fourteen files**. The mechanism is the one this file
already predicted and it is worth stating exactly, because it is the reason no
seventeenth widening should be attempted either:

- **`t_verbo_amigavel` returns prose and its NAME matches no prose-body
  pattern**, and it lives in a library rather than in a handler — so the
  whole-file rule (which fixed miss thirteen) and the prose-body rule were both
  inapplicable. It returned "Editor de texto rico", "Depurador do Windows",
  "Desenho de texto (Uniscribe)" on the screen where the owner agrees to a
  half-hour download. The same shape hid `t_pecas_faltando`, which is the whole
  of `tandem preparar`.
- **`Detalhes tecnicos:` was assembled inside a `${LOG:+...}` expansion** in
  `t_erro`, so it was in every error window in every language, and it is neither
  a call, an assignment, a printf nor a bare argument.
- **`${2:-Sim}` / `${3:-Não}`** — a parameter DEFAULT is none of those four
  either, and those were the most-clicked words in the program. The same shape
  recurred in `tandem-jar`, which substituted `mais nova` into a Chinese
  sentence and produced `sudo apt install openjdk-mais nova-jre`.
- **Forty-four values in the memory file**, which the counter exempts *by
  destination*: an argument to `t_memoria_grava` is data by assumption. It is
  data — and `acao_memoria` prints it, `tandem socorro` puts it in the report
  the owner sends, and `t_receita_exporta` mails the whole file to a stranger.
  **The exemption was right about the disk and wrong about the screen.**

**The fix for the memory values is the one that breaks nobody, and it is the
pattern to copy:** the value stays on disk exactly as written, and
`t_resultado_amigavel` turns it into a sentence when it is SHOWN — the same
arrangement `t_erro_do_leitor` uses for the readers' tokens. Translating an
on-disk value would break every recipe already sitting on somebody's machine.

**One of these was a correctness defect, not a translation one.** Five handlers
printed `[y/N]` in English and `[o/N]` in French, from the catalogue, and then
ran `case "$r" in s|S|sim|SIM)`. An English owner did exactly what the screen
asked, typed `y`, and was told the install was cancelled — on the `.deb` and
`.sh` paths, the two where the alternative to installing is being told nothing
happened. `t_confirmou` now accepts the language's own letter plus `y` and `s`
always, because a shop owner who learned `s` from a Brazilian forum should not
be refused by a machine set to French.

### The second instrument, and how it failed first

`tools/prosa-fora-do-catalogo.py` asks a different question of a different
thing: it **runs the program and reads what comes out**. Two angles, because
the first has a floor of its own:

1. **Render in `zh_CN`** — Chinese shares no letters with Portuguese or
   English, so any run of Latin words is either a name on an explicit
   `VERBATIM` list or prose that never reached the catalogue.
2. **Render in all seven and compare** — a line that comes out byte-identical
   in all seven is what a literal necessarily is and a catalogue lookup almost
   never is. This is the angle that catches accent-free Portuguese, which is
   the hole the very FIRST version of the static counter had.

**Its own first version did not catch the bug it was written for**, and that is
the part worth keeping. It required three words of three letters each, so
"Editor de texto rico" was chopped at "de" into runs of one and two and scored
clean — the counter's entire history repeating itself inside its replacement, on
the first attempt. It was found only by putting the defect back and watching the
tool stay silent. **Do that every time**: a green instrument that has never
caught anything is a green instrument that agrees with itself. A later version
then INVENTED a finding — `sim` on the verbatim list deleted itself out of the
middle of `simplified` and left `plified` — so the stripping is word-bounded
now. A tool that invents findings is worse than one that misses them, because
somebody has to spend an afternoon proving each one is nothing.

**What it still cannot see, stated because a measure that hides its blind spot
is the whole problem:** anything needing a graphical session (the zenity button
labels are covered by a separate assertion instead), anything behind a tool the
machine lacks — skipped probes are REPORTED, never counted as clean — and a
one-word literal, which is below both thresholds.

### The check whose pass and whose wrong premise look the same — 4.15

The same disease outside the counters, and it cost twenty-four files. Reading
a CI log I saw `UNCOMMITTED changes present` and assumed `.proofgate/` was
untracked debris the CI step had just made. The check written to confirm that
was:

```bash
mkdir -p .proofgate && touch .proofgate/verify.sh .proofgate/lib.sh
git status --short | grep -i proofgate || echo "IGNORED"
rm -rf .proofgate
```

`git status` was empty and that was read as proof the path was ignored. It was
empty for the OPPOSITE reason: the files were already tracked and already
there, so touching two of them changed nothing. The `rm` then deleted all
twenty-four tracked files, `git add -A` staged the deletions, and it was
pushed. Restored byte-identical in the next commit.

**The rule, which generalises past git:** before believing a check, ask what it
prints when your premise is WRONG. If that is the same thing it prints when
your premise is right, it has measured nothing and you will read into it
whatever you already believed. This one could not tell *ignored* from *tracked
and unmodified* — and `.gitignore` never applies to a tracked file anyway, so
the fix could not have worked even had the diagnosis been right.

**Still open, and deliberately not guessed at:** why the CI working tree is
dirty at all. The hypothesis is that `install.sh` re-vendors `.proofgate/` over
the committed copy, so the tree goes dirty whenever upstream has moved. It is
NOT verified — running that installer is a curl-to-bash refused in the agent
environment — so nothing has been changed on the strength of it. The
`winedeps.sh ↔ tests/run.sh` pair warning in CI despite its
`direction: a-implies-b` is unexplained for the same reason: the guard lives in
another repository.

### Column 4 of `limites.tsv` — fixed in 4.8, and worth reading as a pattern

It was byte-identical Portuguese in ALL SEVEN tables, the English default
included — 15 rows, one md5. That column is the *way out*, the entire payload
of the 4.0 correction, so a dongle owner outside Brazil was told his case had a
way out and then handed the instructions in a language he cannot read. **The
check that was supposed to catch it greps for a phrase that lives in column
3**, so for two versions it only ever proved column 3 had moved. The suite now
checksums column 4 against the Portuguese source and fails if any table is
byte-identical to it — asserting that somebody translated the column, not what
they wrote in it.

**The tool that did the translation walked the tables by LINE NUMBER on its
first attempt.** They carry their own comment headers and are not the same
length, so it mismatched the rows — it would have handed a CodeMeter owner the
Sentinel instructions. Join on the signature in column 1, which the suite
already asserts is identical and in the same order across all seven.

### What 4.8 closed in the `.exe` loop, and the shape of each

Four defects, and in three of them the honest half of the fix was deciding
what NOT to report:

- **The failure was explained from the wrong verb.** `MARCA_WT` was reassigned
  on every iteration of the install loop, successes included, so after the loop
  it marked the last verb ATTEMPTED rather than the last one that FAILED — and
  the whole cause table ran over that slice. A program needing two components
  where the first fails was blamed on the internet, because a LATER component
  downloaded normally. Every test installs a single verb, which is why nothing
  could see it. The table is `t_causa_do_winetricks` in `common.sh` now so it
  can be exercised without making a real winetricks fail.
- **`No implementation for` is a verdict, and `No implementation for` is not.**
  Two Wine wordings, taken from the installed Wine's own format strings rather
  than from memory. `No implementation for X imported from Y, setting to Z` is
  Wine stubbing an export at LOAD time and carrying on — that line is in the
  log of software that works perfectly, so reporting it would be a false alarm
  on a working program. `Call from ... to unimplemented function X, aborting`
  is the program having called it and Wine having given up. Only the second is
  matched.
- **The `.exe` truncation check is ONE-SIDED on purpose.** Only "shorter than
  its own headers declare" is a verdict: NSIS and Inno append their payload
  after the last section, so every real installer is legitimately longer than
  its section table accounts for, and a two-sided check would refuse exactly
  the software this project exists for.
- **The loader contradicting a permanent receipt is now recorded.** A verb in
  the REPETIDOS branch means Wine just asked for its DLL again while the prefix
  carries a receipt saying that verb was installed. `traducao-suspeita.tsv` is
  the work list that already found six wrong table rows, and `t_anota_suspeita`
  was called only at install time. **The receipt is KEPT** — rule №4 is about
  not paying twice, and the verb may have delivered exactly what it promised
  while the program wants something else. The dedup on that list is OPT-IN: from
  the install path a repeat means "installed again, another day, and again
  failed to deliver", which is a count worth having, and an existing test was
  pinning that.

## What was built after 2.1

- **Pre-flight** (`peinfo.py`): reads the `.exe` import table without executing
  it. Validated against `objdump` on 37 real binaries — identical output on all
  37.
- **Impossibility verdict** (`limites.tsv`): recognises protection dongles,
  system drivers and direct USB BEFORE running. It does not block; it explains
  the failure.
- **The winetricks index** (`verbos.tsv`, 274 DLLs): generated from each verb's
  `w_override_dlls` and, since 3.4, from the DLL list in `title=` as well. It
  only answers with high confidence. Used above all as an AUDITOR of the
  hand-written table, and in that role it found **six mapping errors** that were
  installing the wrong thing and writing a receipt for it.
- **Memory and recipes**: what each program asked for, keyed by the FILE (size +
  first and last MiB), so the lesson survives moving folders and holds on another
  machine. A recipe is a text file the owner sends to someone. It only pulls,
  never pushes.
- **Delivery proof** (3.3): the receipt requires evidence that the DLL arrived,
  and since 3.4 that the bitness matches.
- **`tandem dados`** (3.4): environment separated from data, with a copy taken
  before every destructive path.
- **Silent success** (3.4): `exit 0` stopped meaning "it worked"; the owner is
  asked once, and the recipe carries where its confidence came from.
- **The community list** (3.4): the ad-blocker filter-list model. Down is
  automatic; up is the owner's decision.
- **`tandem autoteste`**: exercises instead of listing. Where it cannot
  exercise, it says it skipped.
- **`tandem preparar`**, **`programas`**, **`desinstalar`**, **`alternativas`**,
  **`socorro`**, **`contribuir`**.
- **Evidence gate, CI and a release pipeline.**

## The language system

Seven languages: `pt_BR` (the original), `en`, `es`, `fr`, `zh_CN`, `hi`, `ar`.
Read this before touching a message anywhere in the tree.

**And it is not only the shell.** The six Python readers used to raise
Portuguese and the handlers printed it verbatim — so the ERRO field of every
reader now carries a TOKEN, and `t_erro_do_leitor` turns the token into a
sentence. A reader must never raise prose; the suite reads the readers and
refuses a `raise` whose argument has a space in it, and demands a
`leitor_<token>` message for every token any reader can emit.

- **`po/*.po` IS THE SOURCE. `src/lib/idiomas/*.txt` is generated from it** by
  `tools/po-para-catalogo.py`, and `build.py` refuses to package a catalogue
  that has drifted from its `.po`. Same arrangement `verbos.tsv` already has:
  generated, committed, guarded by a test.
  **Why gettext, having first built a format by hand:** the hand-rolled one
  could not do the one thing that matters. When an English message CHANGES, the
  six translations keep the old text and nothing says so - key-existence tests
  pass, the program runs, and somebody reads a sentence describing behaviour
  Tandem no longer has. `msgmerge` marks that entry `#, fuzzy`, the compiler
  DROPS a fuzzy entry, and the reader gets English instead of a lie. It also
  buys plural forms (Arabic has six, Chinese has one; the old format said
  `1 linha(s)`) and, most importantly, **Poedit and Weblate** - the blocker on
  five unreviewed catalogues is getting humans to read them, and no human has
  tooling for a bespoke `@key` format.
  **CORRECTED, 4.15: one of those two reasons had never actually worked.**
  `msgstr[0] ` does not start with `msgstr `, so `le_po` matched none of the
  three lines a plural entry is made of, the whole entry fell through, and the
  compiler wrote a catalogue without it - no output, no warning, exit 0.
  Measured, not deduced: a probe entry appended to `po/en.po` came back absent
  from `en.txt` with the tool reporting the same count as before. So gettext
  was adopted partly FOR plurals and then silently discarded every one, for
  three versions, while nine messages went on saying `minuto(s)`. **The people
  that silence discards are the volunteers item 0b needs**, which is what makes
  it worse than a wrong sentence.
  **Why NOT the gettext runtime**, which is the other half of the decision:
  `msgfmt` at build time breaks rule 5 (the packager depends on nothing and
  runs on Windows), and a `.po` parser is sixty lines of Python. `%1$s` would
  also undo the `{1}` decision below. `msgmerge` is not used either, for the
  same reason: the development machine is Windows.
- **Plurals: THE RULE IS CODE, THE FORMS ARE DATA**, and that split is not
  style. gettext ships its rule as a C expression in the header
  (`plural=(n%100>=3 && n%100<=10 ? 3 : ...)`); evaluating one would put
  `$(( ))` around text that arrived from a stranger, and bash arithmetic on a
  hostile string executes. That undoes the property this format exists to have
  and which has its own test. So `t_plural_indice` is shell, `PLURAIS` in
  `tools/po-para-catalogo.py` is the same counts for the translator's tool, and
  a test pins the two together. **Duplication a test pins is cheaper than an
  evaluator.**
  The catalogue carries `@key#0`, `@key#1`… and `t_msg_n` falls back **form N →
  form 0 → the plain key → and only then English**, all three tried in the
  chosen language first. Reaching for English on the first missing form would
  have switched every Arabic and Hindi count to English the day this arrived.
  **Four rules, not one:** en/es/hi put zero with the plural, pt_BR/fr put it
  with the singular (`0 minuto`), zh_CN has one form, ar has six.
  **And the seeding branch written to protect that migration was deleted, not
  kept.** It read as a safety net and was unreachable: an entry that gains
  plural forms is an entry whose English changed, so the fuzzy mark drops it
  before the seeding can run. Chinese, Hindi and Arabic instead carry the
  sentence they were already shipping, in every form - which is not a new
  translation and must not be counted as one.
- **There is exactly ONE path for adding, changing or removing a message**, and
  it is the answer to "where do I edit this": `po/en.po`, then
  `tools/atualiza-po.py`, then `tools/po-para-catalogo.py`. Skipping the middle
  step leaves six translations describing behaviour that is gone, which is the
  whole failure this format was adopted to prevent.
- **`atualiza-po.py` keeps every header line it finds** - `Last-Translator`,
  `PO-Revision-Date`, `X-Generator`. The first version rewrote headers from a
  template, which would have deleted the name of everybody who ever worked on
  the file. There is a test, and the test was written after noticing that the
  first version of it passed VACUOUSLY: it checked the file content without
  checking that the tool had run at all.
- **The messages are DATA, not code, and the format is built so they cannot be
  anything else.** A catalogue is parsed by `read` and never evaluated, so a
  `$`, a backtick or a `$(...)` in a translation is text and stays text. There
  is a test that hands the loader a catalogue trying to touch a file and proves
  it cannot. These files will one day arrive from strangers, and a translator
  is not somebody who should have to know what a subshell is.
- **Substitution is `{1} {2}`, deliberately NOT printf's `%s`.** Paths and
  versions carry percent signs; there is a test with a folder called `50% off`.
- **A key missing from a translation falls back to Portuguese** - never to the
  key name, never to nothing. A test demands every key in every catalogue, so
  half-finished cannot become permanent by accident.
- **ENGLISH IS THE DEFAULT.** It used to be Portuguese, and that was wrong: a
  machine set to Portuguese resolves to Portuguese by locale anyway, so the only
  people the Portuguese default ever reached were those whose language Tandem
  has no catalogue for - and to them Portuguese is a wall, not a mercy. English
  is also what every catalogue falls back to for a missing key, so it is the one
  that has to be complete first.
- **Where the language comes from**, in order: `TANDEM_IDIOMA_FORCADO`, the
  owner's choice in `~/.config/tandem/idioma`, the system locale, English.
  `pt_PT` gets the Portuguese catalogue and `es_AR` the Spanish one, because
  the country is not the language.
- **The unsuffixed file is always the default, which now means English.**
  `alternativas.tsv` and `limites.tsv` are English and `*.pt_BR.tsv` is the
  translation; `man/tandem.1` is English and `man/pt_BR/tandem.1` installs to
  the per-locale path `man(1)` looks in; the `.desktop` files carry English in
  bare `Name=`/`Comment=` and all six others in `Name[xx]=`. Flipping the
  default without also flipping the tables left English reading the Portuguese
  rows - the tests caught it.
- **`TANDEM_LANG_SISTEMA` is read at the very top of `common.sh`, before the
  charmap fixup below it exports `LC_ALL`.** That fixup overwrote the only
  evidence of what language the machine was in: on any computer with no
  `pt_BR` locale generated - most of them outside Brazil - it fired first and
  every user looked like they had asked for `C`. Do not move that line down.
- **The question is asked on first run, not during the package install**, for
  the reason already at `t_primeira_vez`: dpkg holds a lock, the graphical
  installer has no terminal, and the per-user work cannot tell who the user is.
- **A language whose script has no font installed is refused with a sentence**
  (`t_idioma_tem_letras`, via `fc-list`) rather than accepted into a screen of
  empty boxes. Being unable to check means going ahead.
- **Five catalogues carry `REVISADO=nao`** and say so, on the list and again
  when you pick one. Shipping a translation no speaker has read is defensible;
  shipping it without saying so is not. Getting those reviewed is the easiest
  contribution to ask for.

### The migration, and the three times it was declared over

**This section has said "the migration is finished" twice and been wrong both
times**, and the second of those zeros was *published*. It reads 0 again now,
with 620 keys in each of the seven catalogues - so read the list of misses below
before you take that as an answer, and read the last paragraph of this section
before you widen this tool a sixteenth time.

The two false zeros, in one line each. **The first** cited TOTAL 0 while 145
sentences were in the code: the whole of `tandem doctor`, the whole zenity panel
including its eighteen menu rows, the `autoteste` report, and the longest message
in the program - the fifteen-line paragraph about running a real Windows in a
virtual machine. **The second** cited TOTAL 0 while the buttons of "did this
program work as you expected?" were Portuguese, the whole report of
`tandem repair` was Portuguese, and the six Python readers were *raising*
Portuguese that the handlers printed verbatim.

**How a released product came to show an English-speaking user a Portuguese
diagnostic:** it was found by installing the built `.deb` and reading the
output, not by any check in this repository. `tandem doctor` printed `SISTEMA`
and `programas de 64 bits: sim` while `tandem enviar`, two commands later,
printed English. Nothing in the tree could see it, because `acao_doctor`
assembles its report as `out+="SISTEMA\n"` and the counter's assignment pattern
was a **whitelist of variable names** that did not include `out`.

The suite asserts the measured number as a **ratchet**: it may fall, never rise.
A hard 0 that is wrong is worse than a true 145 that can only shrink, because
the 0 says the work is finished and the 145 says where it is not.

**The counter is the interesting part of this, not the translation.** It has now
been wrong FIFTEEN times, each time narrower than reality, and it has never once
failed safe - every version reported zero for something that was there:

1. "no accented character left in the file" - accent-free Portuguese walked
   straight through, and `tandem-snap` was declared done with
   `Instalar "$NOME" a partir deste arquivo?` still in it.
2. Only literals passed DIRECTLY to `t_erro` - assignments were invisible, and
   four survived in files already called finished.
3. Only UPPERCASE assignment names - `common.sh` reported ZERO while the
   `t_texto_*` builders assembled into a lowercase `saida`.
4. No `printf` at all - and `printf` is how those builders emit prose. ~150
   lines that three successive versions scored as zero.
5. `ALVOS` never opened `src/lib/winedeps.sh`, which holds the bitness dead end
   and the suspicious-DLL verdict.
6. A `printf` inside an `acao_*` command - 43 more sentences, including the
   whole of `tandem enviar`.
7. **No heredoc, ever.** `uso()` is `cat <<'AJUDA'` followed by forty lines of
   help text - the most-read screen in the program - and SIX versions of this
   counter scored it as zero, because a heredoc is neither a call nor an
   assignment nor a printf.
8. A lowercase assignment outside the known names: `faixa="$f_ini a $f_fim"`,
   where the ` a ` is Portuguese for "to".
9. **The assignment pattern was a whitelist of variable NAMES**, and
   `acao_doctor` appends into `out`. That hid the entire diagnostic - 68
   sentences, the second most-read screen in the program, and the text
   `tandem socorro` sends to whoever is helping. The whitelist is gone: inside
   a body that exists to produce prose (`t_texto_*`, `t_causa_*`, `acao_*`,
   `uso`), **every** assignment and append is examined, whatever it is called.
10. **`printf '%s' "prose"`** - the prose does not have to be in the format
   string. `t_texto_vm`'s fifteen-line paragraph sat behind a `'%s'` that
   contains no letters. Found while fixing number 9, which is the point: the
   ninth was found by reading a running program, and the tenth by then
   distrusting the fix.
11. **A BARE ARGUMENT to a command**, which is how the entire zenity panel is
   written - eighteen menu rows, the window's own question and the file
   chooser's filter, and not one of them an assignment, a printf or a call to
   `t_erro`. **That panel is the only screen a shop owner who never opens a
   terminal ever sees**, and twelve versions of this counter scored it as zero.
12. **Inside a command substitution that is itself the whole value of a
   string** - `esc="$(zenity --list ... "instalar" "Instalar ou abrir um
   arquivo")"`. Skipping substitutions (which is how you avoid debris) hides it;
   a regex over shell chops it into debris like `" | cut -d'|' -f2)"`, and the
   first version of that rule scored 271, most of it pipeline fragments. **A
   count that is mostly noise gets ignored, which is how a real one goes
   unread.** What works is a walk that descends INTO a substitution while
   refusing to glue its text into the sentence around it.

13. **The prose-body rule keys off function NAMES, and the eleven handler
   executables define no functions at all.** They are straight-line scripts, so
   in `tandem-repair`, `tandem-deb`, `tandem-jar` and eight others the
   whole-body rule and the printf rule were **dead code** — the widest scoping
   error this tool has had, and it was invisible because the number it produced
   was zero. What it hid: the entire report of `tandem repair`, the command an
   owner is told to run when a double click opens the wrong program. Fixed by a
   rule about which FILES rather than which syntax — a handler *is* the body.
14. **Only the FIRST argument of a message call was ever read.** `CHAMADA` is
   `t_erro|t_pergunta|… "…"` and stops at that one string, so
   `t_pergunta "$(t_msg funcionou_como_esperava)" "Sim, funcionou" "Não, algo
   saiu errado"` read as finished: the text was a clean lookup and **the two
   words the owner clicks were never looked at by anything**. Six call sites,
   and three of the six buttons already had catalogue keys nobody had wired up.
   Finding the rest of a call needs the same walk as everywhere else, because a
   regex cannot find where a shell command ends when its arguments contain
   quotes, `$( )` and escaped newlines.
15. **`ALVOS` globs `*.sh` and `src/bin`, so no version of this tool in fifteen
   revisions had ever opened a `.py` file** — and the six readers *raised
   Portuguese*: `nao comeca com ELF`, `zip invalido ou incompleto`,
   `o pacote nao traz um arquivo control`, about thirty of them, every one
   reaching the owner verbatim through
   `t_erro "$(t_msg nao_consegui_ler "$ERRO")"`. The catch-all was worse than
   untranslated: `print("ERRO=%s" % e)` hands over a raw Python exception
   (`[Errno 13] Permission denied`), English jargon whatever the owner reads.
   **Fixed by making the ERRO field a TOKEN**, never a sentence, with
   `t_erro_do_leitor` turning it into a sentence in the owner's language — 25
   tokens, 26 messages, seven languages, and the raw exception goes to the log
   while the screen gets words. An unknown token gets a generic sentence, not
   the key name (`t_msg` prints the key when a key is missing, which is right
   for a log and jargon on a counter), and a token with a character that is not
   a name is refused, because a program's output is input.
   **The lesson is the shape of the miss, not the strings.** Fifteen widenings
   of one instrument could never have found this: a measure that reads only
   shell will never see Portuguese in Python. So the guard is a *second*
   instrument — the suite reads the readers and demands a catalogue key for
   every token they can emit, and refuses a `raise` whose argument has a space
   in it. Its own first version found 21 of 25 tokens and said "missing: none",
   because it knew about `raise` and not about `print`; caught by printing the
   list and counting by hand rather than by reading the verdict.

**The rule stops chasing syntax, because syntax is what failed thirteen times.**
Inside a body that exists to produce prose (`t_texto_*`, `t_causa_*`, `acao_*`,
`uso`) — and inside the **whole** of a handler executable, which has no such
body to scope to — **every** double-quoted string is examined, whatever
surrounds it. What keeps that usable is two things, neither of them a guess
about shape: `EXCECOES`, an auditable list of exact strings somebody had to add
on purpose, and a rule about where an argument **goes** — a value handed to
`t_memoria_grava` lands in a state file, an argument to `t_como_root` is
executed, a `grep`/`sed` argument is a program for another tool. Same footing as
the `t_diz` exemption: not "this looks like code" but "nothing human is at the
other end of this argument".

**And the sixteenth widening will not help, which is the note to read before
attempting one.** Fifteen revisions of this tool all answered the same question -
"what shape of shell hides a sentence?" - and the fifteenth miss was not a shape
at all: it was a FILE TYPE the tool does not open. The instrument that caught it
is a different instrument, sitting beside this one, asking a question this one
cannot ask (does every token the Python readers emit have a message?). When a
measure has a shape, ask what shape it cannot see and build a second measure
rather than a wider one. And its own first version was incomplete too - it knew
`raise` and not `print`, found 21 of 25 tokens, and said "missing: none".

**And the guard on the suite's own comparisons had the same hole.** The checksum
that exists so a bulk rename cannot quietly rewrite an expected value is
line-based, and **206 of 415 `equal` calls are written across two lines** —
which is what you do as soon as an expected value is long, so precisely the
values most at risk were the ones nothing watched. It reads the file with
continuations joined now (419 call sites, 93 of 97 case patterns). Joining then
made the guard checksum **its own value**, because `grep -oE` cuts each match
off after the second argument so the filter that drops the guard's own two lines
never saw what identified them; the filter has to run **before** the extraction.
Two numbers chasing each other on every edit is a guard that can never be green.

**The lesson, which is the reason this is written down:** a completeness check
built from what happened to be in front of me will always pass. The measure only
became trustworthy at the moment it caught something - so there is now a test
that feeds it the panel's exact shape and fails if it goes blind again. The
number has gone `0 → 75 → 107 → 167 → 145 → 0 → 44 → 2 → 0`, and the two zeros in
that sequence were both **false** - the second one was published. **Treat any
number this prints as a floor** - fifteen versions of it have under-reported, and
the only method that has ever caught it is installing the package and reading
what comes out. And the last zero is only as good as the SECOND instrument beside it: fifteen
widenings of this one could not have found Portuguese in a `.py` file, because it
does not read `.py` files. When a measure has a shape, ask what shape it cannot
see, and build a different measure rather than a wider one.

There is now a small list of exact strings the counter is told to ignore
(`EXCECOES`), each with its reason: vendor product names the owner must search
for verbatim, systemd unit names, the Windows `COM` port labels, and one on-disk
value. It is a list of decisions, not a rule about shapes - a rule is what
failed nine times, whereas an exact string somebody had to add on purpose cannot
quietly grow to cover new prose.

### What stays Portuguese on purpose

- **The values written into state files**: `abriu`, `confirmado`, `so-abriu`,
  `reprovado`, `RESOLVERAM`, `CONFIANCA`, `alta`, `override`, `nativo`,
  `parecido`. On-disk format, not prose. `tandem memoria` translates the field
  LABELS and leaves the values alone. Translating one silently breaks memory
  files and recipes already written on somebody's machine.
- **The command names** (`preparar`, `programas`, `dados`...) and the sim/nao
  arguments, so a command copied from a forum works on any machine.
- `LEIAME.md` and `CONTRIBUINDO.md`, which are the Portuguese half of a pair
  with `README.md` and `CONTRIBUTING.md` - the translation, not an exception.

**Nothing else.** The manual and the `.desktop` fields used to be listed here
as deliberate exceptions and they were not defensible: both formats have a
localisation mechanism of their own, and using it was the whole answer.

### The data tables

`alternativas.tsv` and `limites.tsv` carry prose in their columns and it reaches
the owner - "what changes" for each Linux alternative, "why it will never work"
for each impossible signature. They work like the catalogues:
`alternativas.<lang>.tsv` beside the original, **and the original is the
fallback** - a language with no table of its own reads the Portuguese rows
rather than nothing.

**All six exist**: 43 alternative rows and 37 impossibility rows in each of en,
es, fr, zh_CN, hi and ar. Four things are asserted per table per language, and
the last two matter more than the wording:

- the same number of data rows as the original;
- the same FIRST column, in the same order - that column is the pattern that
  matches, and a translated table that reordered its rows would match the wrong
  one;
- the same SECOND column - the class (`nativo`, `parecido`, `dongle`, `driver`)
  chooses which message frames the row, so a translated `nativo` would silently
  pick the wrong frame;
- no row left holding the Portuguese sentence.

## Next steps

The full idea ledger — the 52 ideas from both panels, each with a verdict, and
the rejected ones with the reason written down — lives in `docs/IDEAS.md`. Read
it before proposing anything new; half the obvious ideas were already turned down
for a reason.

**The ledger was corrected on 2026-08-15 and the correction is itself worth
reading.** It listed 22 items as NEXT; verified one by one against the code,
eighteen of them had been done — some three versions earlier — and only the
verdict line was never changed. A ledger that overstates what is left is worse
than no ledger: it is the file this file tells you to read before proposing
anything, and it was sending the next session to build things that exist. When
you finish an item, change its verdict in the same commit, not later.

What genuinely remains there is small and mostly NOT code: a real shop program
(needs the owner's machine), the list's signing policy (needs his key), and two
items blocked on the list having a first published row.

The queue, in order:

0. ~~Migrate the literals `tandem doctor`, the panel, the buttons, `tandem
   repair` and the Python readers still hold.~~ **Done across 4.3 and 4.4**, and
   `tools/conta-literais.py` reports TOTAL 0 — but read the section on the
   counter before trusting that zero: it has read 0 twice before while
   Portuguese was on the screen, and one of those zeros shipped. The only method
   that has ever caught one is installing the package and reading what comes
   out. Treat a new screen as unmeasured until somebody has run it, and treat a
   new FILE TYPE as unmeasured until a second instrument looks at it — this one
   reads shell and nothing else.

0a. **Field-test the current release on the counter**, now that it can be
   installed from the release page. Needs the owner's machine and nothing else:
   `tandem portas` (32 phantom sockets collapsed into one line), `tandem
   intalar` (must say "I do not know that command", not "unrecognised file
   type"), `tandem idioma`, and a double click on a real `.xapk`, `.AppImage`
   and `.jar`.

0b. **Five catalogues carry `X-Reviewed-By-Speaker: no`.** That is the whole of
   what is left of the translation, and it is not engineering: it needs somebody
   who speaks es, fr, zh_CN, hi or ar to read what is there. The files are plain
   text, the format cannot execute anything, and a wrong line breaks nothing —
   it is the easiest contribution this project can ask for. The data tables are
   complete in all six. It is also the item that grows every time a message is
   added: 4.4 added 34 keys, so five languages are now five languages plus 34
   unreviewed lines each.

1. **Fill the community list.** ~~What is missing is an ADDRESS.~~ **The address
   exists.** The intake is `api/lista.js`, in this repository, deployed to the
   owner's Vercel project which is git-linked to it; `api/acumulado.js` is the
   read side; `tools/monta-lista.py` rebuilds `lista/lista.tsv`; and
   `.github/workflows/lista.yml` opens a PULL REQUEST rather than publishing,
   because anybody can POST and a poisoned row that publishes itself reaches
   every Tandem at once.
   **CORRECTED, 4.9: there is now exactly ONE hand-made secret**, and it is the
   list's signing key. Everything else in the chain still creates none — Vercel
   injects the Blob credential when the store is connected, and the rebuild
   reads a public URL — but the owner decided knowingly that a key in Actions
   secrets is worth it. State the trade-off with it: whoever controls the
   repository can sign, so this does not protect against a bad row being
   merged; it protects against a copy modified anywhere that is not GitHub. The
   private half is generated on the owner's machine and has never touched this
   repository or an agent session; only the public half ships. That was the requirement and it drove the design: every alternative
   ended with somebody pasting a token somewhere.
   **It was deliberately NOT put in the owner's existing Supabase project**,
   which was the free option: that project is a live gym management system with
   real student health records in it, and an anonymous internet-facing write
   endpoint does not belong beside them. Same rule this project applies to
   somebody's production Wine prefix.
   What is still missing is real reports, and that is not code: eight of the
   nine formats install native software where the lesson is derivable from the
   file, so the list is inherently about the `.exe` path, where the knowledge is
   genuinely non-derivable.
   **Three mechanical reasons an address alone would not fill it**, established
   by reading the tree rather than guessed, and each one is agent-only work that
   can be done before any address exists: only `tandem-exe` writes the
   `RESOLVERAM`/`CONFIRMADO` keys a record is built from, so **eight of the nine
   formats can never produce one**; the down path has a single caller
   (`tandem-exe`, and only when the local memory is empty); and no verb is needed
   by any program in the reference set, so the first honest record will come from
   commercial software nobody here has. The record format itself only describes
   Wine dependencies — what an `.AppImage`, a `.deb` or a `.jar` learns has
   nowhere to go in it.
2. **A real shop program.** `tests/real-programs.sh` now runs real Windows
   software weekly and checks the window on screen, which closes the "no real
   binary has ever run on it" gap. What it does NOT close is commercial software
   on a counter: a Brazilian POS system, an accounting package, a fiscal printer
   driver. That remains the project's largest uncertainty and no amount of CI
   fixes it.
3. Field-test what has not run on the owner's machine yet: `preparar`,
   `desinstalar`, `dados`, `socorro`, a double click on a real `.xapk`, and a
   double click on a real `.AppImage` and `.jar`.
4. ~~`.apkm` support is declared but only `.xapk`/`.apks` were tested.~~ **Done:**
   `tests/mkapk.py` now writes both a plain `.apkm` and an encrypted one, and the
   reader is exercised on each.
5. ~~Clone a prefix with .NET already in it instead of running `dotnet48` from
   scratch.~~ **REJECTED as designed in 4.2** — read the reasons in
   `docs/IDEAS.md` before reopening it. The short form: the only legal donor is
   the shop's production prefix; there is no read-only way to check "not in
   use", so the safety check is itself the rule-№1 violation; a prefix is not a
   folder of files (`dosdevices/z: -> /`, and `wineserver` names a private
   `/tmp` dir the copy cannot reach); and a mould store is a second
   `.tandem-prefixo`-marked tree that `t_prefixo_do_arquivo` resolves into.
   **The investigation is what found the three defects 4.2 fixes**, which is
   the argument for investigating a rejected idea properly. The surviving
   version — pay `dotnet48` once into a prefix Tandem creates *for that
   purpose*, with no cloning and no reading of anybody else's environment — is
   still open, and now has a delivery proof that can actually fail for it.
6. **No format is queued.** All nine are done. `.msix` was rejected and the
   reason is written down — do not reopen it without reading that first. The next
   valuable work is not another format; it is field evidence for the ones that
   exist.
7. **Import what the prior-art search found worth importing.** A search across
   eight ecosystems established that Tandem's dependency loop is genuinely
   unoccupied ground, and that the AppImage execute-bit problem is solved by
   three other projects in three different ways. See `docs/IDEAS.md` for what to
   take from them and what to leave.

**Done, do not redo:** all nine formats are implemented, tested and verified end
to end on real files. `.AppImage` and `.jar` came in 3.7; `.deb`, `.rpm`,
`.flatpakref`, `.snap` and shell installers in 3.8 — see the State section for exactly what was
measured. The orphan-shortcut question is settled: it was never a defect. The
real-program harness exists and is green. **v4.0 through v4.5 are published** —
tag, `.deb` and `.sha256` attached, and 4.0's, 4.2's, 4.3's, 4.4's and 4.5's
published artifacts each verified byte-for-byte identical to a local build
(sha256 `82544a90…`, `3d5ed79a…`, `d6f2d792…`, `dbb14fad…` and `fa8205c8…`). 3.7 through 3.9 were never
released, so 4.0 is the first package the public gets with all nine formats in
it. The next release goes out the same way; see the section below for why the
browser path exists.

**v4.3 IS PUBLISHED** — 2026-08-12, tag `v4.3` at `d61461d`, `.deb`
(335766 bytes) and `.sha256` attached, and the published artifact verified
byte-for-byte against a local build: sha256 `d6f2d792…` from all three of the
release's own checksum file, the downloaded bytes, and a build made here. The
installed package answers `Tandem 4.3` and `tandem doctor` line 3 reads `SYSTEM`
/ `SISTEMA` / `系统` / `النظام` — which is the point of the release: it carries
the last 145 literals into the catalogues, so the flagship diagnostic and the
zenity panel finally speak the machine's language. v4.2 before it carried the
gettext migration, English as the default, the six data tables, sending on by
default, the security fix on verb names and three Wine defects.

**v4.4 IS PUBLISHED** — 2026-08-13, tag `v4.4` at `d6ea091`, `.deb`
(351784 bytes) and `.sha256` attached, and the published artifact verified
byte-for-byte against a local build of that same commit: sha256 `dbb14fad…`
from all three of the release's own checksum file, the downloaded bytes, and
the build made here. The installed package answers `Tandem 4.4`, `tandem
repair` prints its report in Chinese when asked to, and a text file named
`.rpm` produces a French sentence — which is the point of the release: the
community list stopped answering with the first row it found, the send path
stopped deleting lessons it had not sent, and the last Portuguese left in the
product (the buttons, `tandem repair`, and thirty sentences inside the Python
readers) went into the catalogues.

**v4.5 IS PUBLISHED** — 2026-08-13, tag `v4.5` at `4ced498`, `.deb`
(354120 bytes) and `.sha256` attached, and the published artifact verified
byte-for-byte against a local build of that same commit: sha256 `fa8205c8…`
from all three of the release's own checksum file, the downloaded bytes, and
the build made here. Exercised from the INSTALLED package, both halves of the
change it exists for: a `.sh` that does nothing and exits 0 gets the warning
rather than "it worked", and one that prints a line gets "Terminou sem erro"
followed by its own words only — no Tandem log lines under "this is what it
said", which is the defect the guard uncovered.

**v4.15 IS PUBLISHED** — 2026-08-15, tag `v4.15` at `5e7d48d`, `.deb`
(442920 bytes) and `.sha256` attached, and the published artifact verified
byte-for-byte three ways: sha256 `fe74c0e8…` from the release's own checksum
file, from the downloaded bytes, and from a local build at that same commit.
Exercised from the INSTALLED package, which is the only method that has ever
caught anything here: `t_msg_n progresso_ha_minutos` renders "1 minute" /
"2 minutes" in English, "Ja vai 1 minuto" / "Ja vao 2 minutos" in Portuguese
(the verb agrees, which `(s)` could not express), one single form in Chinese
and two distinct Arabic forms at 1 and 2; `tandem memoria` shows `seconds:` /
`segundos:` where it used to say `took (s):`; **`grep -c '(s)'` is 0 in all
seven installed catalogues**; and `tandem autoteste` answers 17 passed,
0 failed.

**v4.19 IS PUBLISHED** — 2026-08-16, tag `v4.19` at `b6c3b34`, `.deb`
(456078 bytes) and `.sha256` attached, and the published artifact verified
byte-for-byte three ways: sha256 `45e28e1e…` from the release's own checksum
file, from the downloaded bytes, and from a local build at that same commit.
Exercised from the INSTALLED package on both headline fixes: a `.exe` reached
through a symlinked prefix leaves the production profile with **zero** Tandem
files in it and says why, and a broken notes folder produces "Não consegui
escrever minhas anotações em …" instead of a bare exit code. `tandem autoteste`
answers 17 passed, 0 failed.

It carries seven defects found by running the program in conditions it had
never been run in — read the State section for the list and the Ecosystem facts
for the five that generalise. The one that matters most is the rule №1 symlink
bypass: **that is the only time the inviolable rule has actually been broken**,
and it was reachable by a person doing something entirely reasonable.

**v4.26 IS PUBLISHED** — 2026-08-18, tag `v4.26` at `72d012e`, `.deb`
(492502 bytes) and `.sha256` attached, and the published artifact verified
byte-for-byte three ways: sha256 `6bd091cb…` from the release's own checksum
file, from the downloaded bytes, and from a local build at that same commit.
It is the release that adds the TENTH thing Tandem carries and the first that
is not a file: a web service. `tandem servico` detects what a folder is (Node,
Python, PHP, a Java `.jar`, a plain binary, a shell script, or a Windows server
`.exe` under Wine), writes a `systemd --user` unit, starts it, tries to make it
survive a reboot, and says in plain words — per service — whether it is running,
listening on its port, and answering; every failure path names its cause (crash
tail, who holds the port via `ss`/`lsof`, no-user-systemd) instead of going
mute. The logic that decides (runtime detection, the unit text, the port
parser, the verdict table) is pure and tested; the whole install flow is
exercised with `systemd`/`ss`/`curl` stubbed, and the headline guard — the
unit's `ExecStart` must be an absolute path, because `systemd` ignores the
caller's PATH — is proven by injection. It also carries the 4.25 fix that never
shipped on its own (a standalone v4.25 was impossible during a GitHub `apt`
outage): `tandem portas fixar` wrote only the registry key and not the
`dosdevices/comN` symlink, so the port it "fixed" still could not open; both
halves are written now. **All 784 messages are translated in all seven
languages, 0 untranslated, 0 fuzzy** — the 35 new `servico` messages included.
Suite 1473 passed / 0 / 1 skipped; both literal counters read 0.

**v4.27 IS PUBLISHED** — 2026-08-18, tag `v4.27` at `13913e8`, `.deb`
(499680 bytes) and `.sha256` attached, and the published artifact verified
byte-for-byte three ways: sha256 `1f980252…` from the release's own checksum
file, from the downloaded bytes, and from a local build at that same commit. It
is the first feature of the extrapolation round: `tandem relogio` (alias
`clock`), a PROACTIVE clock check, plus a one-line clock status in `tandem
doctor`. A wrong clock breaks TLS, licensing and Brazilian fiscal software
(NF-e/NFC-e) in silence, and a dead CMOS battery is the usual cause; Tandem
already inferred this reactively from a certificate error after a failure, and
now checks it before. The verdict never cries wolf on a correct clock — the one
firm signal is that the clock cannot predate the software running on it (the
release date read from the shipped changelog, so no new constant drifts); an
absurd future is flagged too, and a plausible date with automatic time off only
advises. Reading the clock needs no privilege; setting it does, so Tandem prints
`sudo timedatectl set-ntp true` rather than running sudo. Pure verdict function,
proof-by-injection test, live `timedatectl` read machine-only like Wine; 792
messages translated in all seven languages, 0 untranslated, 0 fuzzy. Suite 1489
passed / 0 / 1 skipped; both literal counters read 0.

**v4.28 IS PUBLISHED** — 2026-08-18, tag `v4.28` at `0a00b29`, `.deb`
(501538 bytes) and `.sha256` attached, verified byte-for-byte three ways: sha256
`727f9a1a…` from the release's own checksum file, the downloaded bytes, and a
local build at that commit. Second feature of the round: post-install breakage
detection. A Windows program that opened cleanly yesterday can break today
because a distro upgrade swapped Wine underneath it; the memory (already keyed
by file) now records the Wine a program last opened cleanly under (`VERSAO_WINE`,
on-disk data, never translated), and on a later failure under a DIFFERENT Wine
Tandem names the change — "this opened before under Wine X; the system now has
Wine Y" — instead of a bare exit code. It never blames the update on a guess:
`t_wine_mudou_desde` is true only when there is a recorded version, the current
one is real, and the two differ (proof-by-injection test). The recorded version
also shows on `tandem memoria`. Suite 1499 passed / 0 / 1 skipped; 794 messages
translated in all seven languages, 0 untranslated, 0 fuzzy; both literal
counters read 0.

**v4.29 IS PUBLISHED** — 2026-08-18, tag `v4.29` at `656cd23`, `.deb`
(505850 bytes) and `.sha256` attached, verified byte-for-byte more than three
ways: sha256 `8396d1ca…` from the release body, the release's own checksum
file, the `.deb` asset digest, the downloaded bytes, and a fresh local build at
that commit. Third feature of the round, and the round-one white space that
sits AROUND the double click: a `.exe` arrives off a pen drive or a chat
message and, until now, Tandem opened it in silence with no word on whether the
thing had ever been seen before. It says so now — a calm recognition note,
never an antivirus and never a refusal — built from the two things it already
keeps, keyed to the FILE by content: the owner's own memory of this exact file
(opened cleanly here? confirmed working, or marked broken?) and what the
community list knows (reports of a working lesson, or the honest negative
"nobody got this one going"). Local knowledge outranks a distant shop's report.
It never overclaims: the list is empty for essentially everyone, so the common
answer is a reassuring "new here, that is normal", and a count is shown only
when the list carries one — worded as "report(s)", never "machines". The note
speaks only when the recognition status CHANGES (new → opened here → confirmed),
so a POS opened dozens of times a day is not nagged; the throttle marker is
on-disk, language-neutral, kept off the `tandem memoria` screen and stripped
from an exported recipe — purely local, it must not travel. The decision is a
pure function (`t_procedencia`) with its ORDER asserted so local-beats-community
cannot regress; the sentence is a second pure function (`t_procedencia_frase`)
that says nothing on an unknown token rather than printing a key name. Suite
1518 passed / 0 / 1 skipped; 800 messages translated in all seven languages,
0 untranslated, 0 fuzzy; both literal counters read 0.

**v4.30 IS PUBLISHED** — 2026-08-19, tag `v4.30` at `46fab13`, `.deb`
(511848 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`da95838c…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. It is the FIRST feature of round two, and it came with a lesson: the
version it was SUPPOSED to be — "passive self-update awareness" — turned out to
be three versions old, shipped in 4.13 (the `t_versao_*` family, `acao_versao`
on/off, the daily throttled check, `versao_nova_aviso` in all seven catalogues);
it was found by reading the tree before building, which is the whole point. So
4.30 became round two's real first item: verifiable backups. `tandem backup`
now writes a `.sha256` checksum beside the archive — the same sidecar this
project proves its own releases with — and `tandem backup verificar <file>`
(alias `verify`) reads it back and says intact / corrupted / no-checksum plainly,
so a backup can be tested the day it is made, not the day the disk dies. `tandem
restore` no longer trusts that the archive merely OPENS: before it wipes the
working environment it verifies the archive against its checksum and refuses a
mismatch, rather than laying a broken copy over a good setup; no checksum beside
the file falls back honestly to the structural check. The integrity decision is
a pure function (`t_backup_verifica`: intact / corrupted / no-checksum / no-tool)
with its guarantee proven by injection — a valid archive with a wrong sidecar
makes restore refuse while the environment stays on disk; the checksum read
(`t_backup_soma`) is a second one. Suite 1528 passed / 0 / 1 skipped; 807
messages translated in all seven languages, 0 untranslated, 0 fuzzy; both
literal counters read 0.

**v4.31 IS PUBLISHED** — 2026-08-19, tag `v4.31` at `ef1891a`, `.deb`
(518780 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`2e75850e…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. Round two's second feature: a single machine-"health" reading. Tandem
already computes a dozen verdicts about the counter — is the clock right, is a
newer Tandem out, is the disk filling, is Wine there, is a web service serving,
is there a backup to fall back on — but each lived in its own command, unseen by
a shopkeeper who did not know to ask. `tandem saude` (alias `health`) gathers
them into ONE plain reading, worst-first: what to act on now, then what is worth
knowing, then the all-clear, each problem line naming the one command that fixes
it. It is TRIAGE, not the doctor's dump — doctor says what EXISTS, saude says
what to DO. It never invents a problem (every finding is a verdict already
computed, including the 4.30 tie-in: is there a recent, VERIFIED backup to
recover from) and a check it cannot run reports unknown, never healthy. The
pure parts are truth tables with proof-by-injection: `t_saude_disco_veredito`,
`t_saude_backup_veredito`, and `t_saude_ordena` (the ordering is a function so
worst-first is a property a test pins, not an accident of probe order — the
`t_prova_do_run` shape). **A real bug was found by RUNNING it**, not by reading:
`nl="$(printf '\n')"` strips the trailing newline in a command substitution, so
every finding ran into the next with the rank marker showing — fixed to `$'\n'`.
Suite 1540 passed / 0 / 1 skipped; 820 messages translated in all seven
languages, 0 untranslated, 0 fuzzy; both literal counters read 0.

**v4.32 IS PUBLISHED** — 2026-08-19, tag `v4.32` at `2cd69c5`, `.deb`
(521378 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`37a368a4…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. Round two, recovery deepened: it closes the half 4.30 left open. 4.30
made a backup provably intact; 4.32 proves it would actually COME BACK, and that
it did. `tandem restore --testar <file>` (alias `--ensaiar`) runs the whole
restore pre-flight — integrity against the checksum, structure, and that it is a
complete Tandem environment — and touches NOTHING, so a shop can prove the day
it makes a backup that the backup would restore on a replacement PC, instead of
finding out the day the disk dies. And a real restore no longer trusts tar's
exit code alone: after it unpacks, it confirms the environment actually LANDED
(the prefix is there and is a Tandem environment) via a post-untar `system.reg`
check, and warns "looks incomplete" rather than reporting a half-restore as
done — the finishing-is-not-working rule applied to recovery. The rehearsal
verdict is a pure function (`t_restauravel`: ok / corrompido / nao-e-backup /
danificado / sem-arquivo, structure before integrity, the order the restore
itself uses) with proof-by-injection tests. This is also the version that
recorded the owner's permanent insight directive. Suite 1549 passed / 0 / 1
skipped; 823 messages translated in all seven languages, 0 untranslated,
0 fuzzy; both literal counters read 0.

**v4.33 IS PUBLISHED** — 2026-08-19, tag `v4.33` at `1bcf76f`, `.deb`
(522342 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`672f5848…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. A small, high-value round-one-flavoured gap the ledger had documented
as not-done (`docs/IDEAS.md:586`): a USB or parallel printer plugged into the
counter needs its user in the "lp" group, and without it the printer is seen and
simply does not print — a thermal printer that stays silent is the shop's live
pain. `tandem portas` warned about the "dialout" group for a serial pinpad or
scale but said NOTHING about "lp" for a printer. It does now: when a printer node
is present (`/dev/usb/lp*`, kept in `$usblp`, or a parallel `/dev/lp*`) and the
owner is not in the lp group, `t_texto_portas` names the exact one-time fix —
`sudo usermod -aG lp <user>`, then log out and back in — in the same shape as the
dialout warning it already had. The decision reuses `t_no_grupo` (testable); it
never runs `usermod` and never writes a udev rule (weighed and rejected at
`IDEAS.md:649`) — it explains, the owner runs one command he can read. Suite
1552 passed / 0 / 1 skipped; 824 messages translated in all seven languages,
0 untranslated, 0 fuzzy; both literal counters read 0.

**v4.34 IS PUBLISHED** — 2026-08-19, tag `v4.34` at `2f95539`, `.deb`
(524392 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`a620c638…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. Round two: pin the Wine that works. 4.28 named the cause when a program
that opened cleanly yesterday breaks today because a distro upgrade changed Wine
underneath it; 4.34 offers the way to stop it happening again. When a program
opened before under one Wine, the system now carries a different one, and Wine
is not already held, the 4.28 breakage message gains one honest line: you CAN
pin Wine — `sudo apt-mark hold wine` — but that also holds back Wine's own
security updates, so it is your call, and `sudo apt-mark unhold wine` undoes it.
Tandem runs no `apt-mark`: it EXPLAINS, the rule that keeps it from installing a
`.deb` it detected. It never nags without cause — only where there is a working
Wine to protect, never as a blanket suggestion to hold a package. The decision
is a pure function (`t_wine_pin_veredito`: pode-fixar / ja-fixado / sem-referencia
/ sem-wine) with a proof-by-injection test; reading whether Wine is held is
machine-only (`apt-mark showhold`). It also adds `tools/preenche-traducao.py`,
the reusable multi-line catalogue-fill instrument — built because that fill was
re-derived by hand five times in one session, wrong the same way each time (a
string `re.sub` replacement processes `\n`; a callable one does not) — carrying
a self-test the suite runs. Suite 1561 passed / 0 / 1 skipped; 825 messages
translated in all seven languages, 0 untranslated, 0 fuzzy; both literal
counters read 0.

**v4.35 IS PUBLISHED** — 2026-08-19, tag `v4.35` at `87bdeb7`, `.deb`
(525846 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`fda874f9…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. Round two, made proactive: `tandem saude` now reads 4.28's per-program
`VERSAO_WINE` and warns, BEFORE a program is next opened, that the Wine under it
has changed — so a POS can be tested while the shop is closed rather than at 8am
with a customer waiting. 4.28 recorded the working Wine and named the change only
at the next failure; saude never read that record. The decision is a pure
function (`t_saude_wine_citar`: recorded working Wines on stdin, the current Wine
as its argument, the one worth citing out or nothing) reusing the 4.28 guard
`t_wine_mudou_desde`, so it never cries wolf; ranked "worth knowing", not "act
now". Message `saude_wine_mudou` translated in all seven languages. Suite 1568
passed / 0 / 1 skipped; both literal counters read 0.

**v4.37 IS PUBLISHED** — 2026-08-19, tag `v4.37` at `d87f1da`, `.deb`
(528212 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`0ad3ae7a…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. It is the vision audit's #1 finding built: `tandem saude` — the flagship
triage command — was committing the project's own cardinal sin, false
reassurance instead of silence, TWICE, and the audit found it by RUNNING the
command, not reading it. (a) Recovery readiness only checked the backup's
checksum (`t_backup_verifica`), so a 0-byte/truncated archive with no sidecar —
one `tar` cannot even open — passed as a healthy recovery net; it checks the
STRUCTURE now via `t_restauravel` (structure then checksum) and
`t_saude_backup_veredito` condemns danificado / nao-e-backup / corrompido.
(b) A web service up but serving nothing read healthy: the loop passed the
service NAME where `t_servico_escuta`/`t_servico_responde` expect a PORT and
captured their empty stdout instead of the exit code, so `escuta-mudo` was dead
code; it reads `t_servico_le NAME PORTA` now and maps exit codes to sim/nao (a
check it cannot run stays silent — never a false alarm). The backup message was
reworded "fails its checksum" → "is damaged" (re-read in all seven, the only
translation change). A nice proof the fix is real: 4 existing saude e2e tests
started failing because they used an EMPTY tar as a "backup" — exactly the
not-really-a-backup the old saude waved through — so they now build a
structurally valid one. Suite 1586 passed / 0 / 1 skipped; both literal counters
read 0.

**v4.36 IS PUBLISHED** — 2026-08-19, tag `v4.36` at `cb7fc28`, `.deb`
(527112 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`10399fd6…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. (The first release run stalled 57 min on a GitHub runner — pure infra,
the identical code passed CI on main in 15 min — so it was cancelled and
re-dispatched; the fresh run published in ~5 min. `cancel_workflow_run` +
re-`run_workflow` is the remedy for a stalled release.) It is the doctor/socorro
hang fix, and it is a good example of
the extrapolation drive done right: idle-time was spent on an adversarial
workflow (the owner asked "if there's more to do, why are you idle?"), 7 agents
scoping features and hunting defects by RUNNING the program in conditions CI
never tests. It found a CONFIRMED high-severity regression from 4.26: the
web-service feature defined a SECOND `t_porta_escutando` (a stdin parser), and
bash keeps the last definition, so the ss-runner the dongle check
`t_chave_estado` calls was shadowed — `tandem doctor` and `tandem socorro` HUNG
with zero output at an interactive terminal (CI feeds non-terminal stdin, hits
EOF, stays green), and the dongle port check was silently always "not listening".
Reproduced end to end. 4.36 renames the runner `t_porta_ouvindo_ss`, and ships
the INSTRUMENT for the class — a test that fails if any shell file defines a
function name twice — plus a no-stdin regression on `t_chave_estado`. It rides
two same-sweep guards: the 4.35 saude Wine check normalises `VERSAO_WINE` so a
CR/unterminated memory file cannot cry wolf, and the `tandem portas` dialout
warning is gated on a real serial device existing. Pure-logic, no new messages,
no translation step.

**v4.38 IS PUBLISHED** — 2026-08-19, tag `v4.38` at `68f235c`, `.deb`
(528690 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`eb3eccfb…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. It is the vision audit's #3 finding: a Rule-1 asymmetry. `tandem portas
fixar` guards its writes into a prefix with the `system.reg` environment check
AND `t_prefixo_protegido` (rule №1: only ever touch a prefix carrying our
marker), but its `soltar` sibling — which removes the `dosdevices/comN` symlink
and runs `wine reg delete` in the same prefix — had neither. So through a
symlinked default prefix pointing at the shop's production POS prefix (the exact
4.19 lesson, where the guard was scoped to `fixar` only), `soltar` would rm and
reg-delete inside it. `soltar` now carries the same two guards as `fixar` and
refuses a prefix that is not ours, leaving it untouched. Pure-logic, no new
message keys (both sentences already existed), no translation step; proof by
injection mirrors the existing soltar/fixar command-level tests. Suite 1587
passed / 0 / 1 skipped; both literal counters read 0.

**v4.39 IS PUBLISHED** — 2026-08-19, tag `v4.39` at `4f65c13`, `.deb`
(529184 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`5ea0db60…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. It closes the vision audit's last two buildable-now gaps, both test-only
guard hardenings with no product-behaviour change. (i) A `.msi` is not a PE, so
`wine file.msi` always fails; `executar()` routes `*.msi|*.msp` to `wine msiexec
/i`, and nothing guarded that a refactor keeps it there — a "simplification" to
`wine "$PROG"` would make every `.msi` fail and send the dependency loop hunting
DLLs that are not the problem, the exact silent-wrong-diagnosis class this
project exists to abolish (and the one format where it hides: `t_pe_arch` reads
MZ+PE, a `.msi` OLE compound file answers nothing, so the bitness gate is skipped
and the file reaches `executar` unrefused). A full-loop test runs a `.msi`
through a fake wine and asserts the `msiexec /i` call and that the file is never
handed straight to wine — proven both ways by injection. (ii) The 4.26
no-function-defined-twice guard knew only the `name()` spelling; a duplicate
written `name ()` or `function name` could walk around it. The extractor now
folds all three spellings to the bare name, stays column-0 anchored so awk's own
indented `function`s are excluded, and requires parens-or-keyword so an
assignment is never mistaken for a definition — with a vacuity probe per spelling
plus one asserting a same-named assignment is NOT flagged. Suite 1592 passed /
0 / 1 skipped; both literal counters read 0. **The release itself is the lesson
this time:** both CI and the release hit a GitHub-wide apt-mirror stall on the
`Tools` step — three of four runners hung 11–37 min installing
shellcheck/lintian/gettext/wine while healthy ones finished in ~90 s — infra,
not code, proven by the identical tree passing on a fresh runner. The remedy is
the one already recorded for a stalled release: a stuck apt does NOT self-recover
quickly, so cancel the hung run and re-dispatch (release) or empty-commit-
retrigger onto a fresh runner (CI) rather than waiting it out. The empty
retrigger commit squashes away at merge, so the released tree is byte-identical
to the reviewed one — which the five-way check confirms.

**v4.40 IS PUBLISHED** — 2026-08-19, tag `v4.40` at `01c3d93`, `.deb`
(530004 bytes) and `.sha256` attached, verified byte-for-byte five ways: sha256
`30e4a095…` from the release body, the release's own checksum file, the `.deb`
asset digest, the downloaded bytes, and a fresh reproducible local build at that
commit. It is the FIRST defect found by field-testing the installed package on
this container's real Wine 9.0 — the owner having pushed back on "needs your
counter" (*"e pq é q vc nao pode testar aí?"*). A real WinDirStat `.msi`
installed correctly through Tandem, but because `msiexec` exits in a second the
silent-success guard branded it "opened and closed on its own, with no time to
use it" — a successful install reported as a flash-and-vanish failure. An
installer is now exempt: a `.msi`/`.msp` (a `.msi` exiting 0 installed
something), or any run that registered a new Start Menu shortcut, is not that
failure. `t_anuncia_atalhos` reports whether it announced anything; `executar()`
computes the installer flag and passes it to `t_confirma_funcionou`, which skips
both the `fechou sozinho` memory and the warning — while the guard still fires
for a real program (installer = 0), proven both directions by a regression test.
Suite 1594 passed / 0 / 1 skipped; both literal counters read 0. See the
field-test entry in the State section for everything else that session validated
on real Wine + CUPS (real `.msi` installs, PuTTY's window on screen, `tandem
portas` printer + lp detection on a real node, `portas fixar` both halves, a CUPS
virtual printer, Wine enumerating the CUPS printers) and the two other findings
(Wine 9.0 ships msvcp140 builtin; a blank `service:` line on a non-systemd host).

**ROUND TWO IS COMPLETE, and the extrapolation drive is at a deliberate pause,
2026-08-19.** All the round-two work that a CI can verify is shipped: 4.30
verifiable backups, 4.31 machine health, 4.32 restore rehearsal, 4.34 Wine
pinning (round one closed earlier: 4.27 clock, 4.28 breakage, 4.29 provenance,
self-update already 4.13). The one named round-two item not built —
**second-counter replication** — was investigated against the code, not
assumed: it is **already achievable** via `tandem backup` + the fresh-machine
`tandem restore` (4.30 proves the backup intact, 4.32 verifies the restore
lands). Its only real gap is machine IDENTITY — `t_identidade_fixa` stamps a
per-machine `MachineGuid`/volume-serial into the prefix, so a restored backup
carries the SOURCE till's identity, and whether a second till should share it or
re-derive its own is a per-machine LICENSING decision. Automating that would
break rule №1's spirit and the "no fiscal or legal advice" rule
(`IDEAS.md:676`), so no marginal replication version was manufactured. **The
honest read, recorded because this file is where the next session looks:** the
mandated two rounds are delivered and verified; further *code* extrapolation is
into falling returns; the largest remaining uncertainty is unchanged and is not
code — a real POS / fiscal installer on the owner's actual counter (`preparar`,
`desinstalar`, `dados`, `socorro`, a real `.xapk`/`.AppImage`/`.jar` double
click). That is the field evidence the community list and the "one afternoon"
gap have always needed.

**The pause was LIFTED the same day by the owner, and 4.35 is what the resume
produced.** He asked to review everything, leave nothing undone, then
brainstorm ("faça"). The review confirmed the two rounds and found the driver
seam largely already landed (the "pinpad on a COM2 Wine never created" defect,
for one, was fixed in 4.9 — checked in the code, not the ledger). The one code
item worth building without his machine was the intersection of both rounds:
4.28 records the Wine each program last opened cleanly under and warns only at
the next FAILURE, and `tandem saude` never read that record. **4.35 makes it
proactive** — saude now says, before a program is next opened, that the Wine
under it has changed, so a POS can be tested while the shop is closed rather
than at 8am. It reuses the 4.28 guard (`t_saude_wine_citar` → `t_wine_mudou_desde`),
never cries wolf, and is ranked "worth knowing", not "act now". After 4.35 the
honest read is unchanged: the highest-value work left is field evidence on the
owner's counter, not code — so do not open 4.36 on reflex either.

**Whenever a version has shipped, the next one's changelog entry has to be
OPENED before anything is added** — bump `debian/control`, `debian/changelog`
and `TANDEM_VERSAO` together, because a released version's entry is history the
public already has. A doc-only commit after a release is fine and the guard
allows it; a bullet appended to a published entry is not. (At the time of
writing, **4.40 is published** — verified byte-for-byte five ways — and **no
version is in flight**, but the field testing that produced it is ONGOING per
the owner's directive *"isso, agora é momento de fazer testes extensivos"*, so
the next version is whatever that testing turns up, not a pause. The "wait for
the owner's steer" that closed the 4.39 note was LIFTED the same day, and the
way it was lifted is the lesson worth keeping: that note said the highest-value
work left "needs the owner's counter", and he pushed back — *"e pq é q vc nao
pode testar aí? instala alguma impressora virtual com driver genérico e testa"*.
He was right. This container is Ubuntu 24.04 (the Zorin 18 base) with **Wine 9.0,
winetricks, CUPS, Xvfb and xdotool already installed**, so most of what was filed
under "needs his machine" is testable HERE — and doing so found a real defect.
What genuinely still needs his counter is narrower than the 4.39 note claimed:
his specific licensed POS / fiscal-printer HARDWARE and his Zorin GNOME/Wayland
double-click routing — NOT "run a Windows installer" or "test a printer", both
of which were done here (see the field-test entry in the State section). **4.40
is that field defect:** a successful installer — a real WinDirStat `.msi` on real
Wine — was branded "opened and closed on its own, no time to use it" because
msiexec exits in a second, the silent-success guard firing on an installer doing
its job. An installer (a `.msi`/`.msp`, or any run that registered a new Start
Menu shortcut) is now exempt; the guard still fires for a real flash-and-vanish
program. All three version files agree on 4.40.)

That entry had to be *split out* of 4.1's, and the lesson is the reason this
paragraph exists: v4.1 was published on 2026-08-09 and three commits' worth of
work kept being appended to its changelog entry afterwards, so the entry
described a package the public never got. **Check the published tag before
adding to the top changelog entry.** There is a test for it now, and its first
version was wrong in the way this project keeps being wrong: it asked "does a
tag with this version exist", which is red on a freshly released tree where
nothing is wrong at all. It compares `debian/changelog` against the tag instead
— a released tree passes, a doc-only commit after a release passes, and
appending a bullet to a published entry fails. Checked against real history:
v4.0 and v4.1 pass at their tags, `293613f` and `92dbb49` fail.

**Two guards were added because the release itself found the defects**, and
both are in the suite now rather than in a failed workflow: the newest
changelog entry must be dated after the one below it (lintian refuses
otherwise, and it has caught this project twice — both times because an
*earlier* entry carried a timestamp in the future), and the test-count badge
must be within 15 of what the suite actually runs. The first version of that
badge guard was itself one-sided and blocked a good release, because CI runs
two more checks than a bare container: **a guard that stops a good release is
worse than the drift it was written for.**

**A third one joined them in 4.11, and it is the same lesson a third time.**
lintian also refuses `debian-changelog-has-wrong-day-of-week`, as a *warning* —
and the release step runs it with `--fail-on warning`, so a hand-written `Fri`
for 2026-08-15, which was a Saturday, turned CI red. **The date-ordering guard
beside it could not see this**: both dates parse and sort correctly, because
`date -d` simply ignores a weekday that disagrees with the rest of the field.
That is now the third changelog-date defect lintian has caught here and the
first one a test catches first. It checks EVERY entry, not the top one — an old
entry's wrong day is just as fatal, and finding it during a release is the
wrong order. Proven by putting the defect back and watching it speak, with an
assert on the injection.

**And the proofgate `coupled-files` guard gained `"direction": "a-implies-b"`,
for the reason above rather than for convenience.** The
`src/lib/winedeps.sh → tests/run.sh` pair is genuinely one-way: changing the
DLL→verb table without a test is walking without the auditor, but almost every
commit here touches `tests/run.sh`, so the symmetric form warned on nearly
every delivery about the harmless direction. **A warning that is almost always
noise is a warning nobody reads**, which is how the one that matters goes
unread. The `debian/control ↔ debian/changelog` and `src/bin/tandem ↔
man/tandem.1` pairs stay symmetric. Verified on real commits in all three
directions — and the first attempt at that proof was vacuous, because the guard
diffs COMMITS and the probe changed only the working tree.

## What an agent session cannot do here

Verified, not assumed — the credential is not the limit, the proxy is. It
authenticates as the repository owner, and these still fail:

- `git push origin <tag>` and `git push origin --delete <branch>`: HTTP 403
  from the git proxy. It allows updating an existing branch, not creating or
  deleting a ref.
- `POST`/`DELETE` on `/git/refs` via the API: HTTP 403, "Write access to this
  GitHub API path is not permitted through this proxy."

**On the Vercel side**, which is new since 4.6 and worth the same treatment:

- The project is **git-linked to this repository**, so a push deploys the
  endpoint. There is nothing to upload and no CLI to run — write the file,
  push, and the branch gets a preview deployment with its own URL. That is how
  the intake was exercised before it ever reached production.
- **Vercel Authentication was ON by default** (`ssoProtection`,
  `all_except_custom_domains`), which would have bounced every anonymous POST to
  a login page. Turned off for this project only, through
  `update_project_deployment_protection`. An intake that cannot be reached
  anonymously is not an intake.
- **The MCP has no tool for environment variables or for creating a Blob
  store.** Connecting the store is a dashboard action by the owner, and it is
  the ONLY manual step in the whole chain — Vercel then injects
  `BLOB_READ_WRITE_TOKEN` itself, so no secret is ever copied by hand.
- **Runtime logs are readable** (`get_runtime_logs`) and they are what named the
  `res.type()` defect. Read them before guessing at a 500.

What works is the surface the MCP GitHub tools cover — merging a pull request,
editing it, and `run_workflow`. Hence the release workflow accepting a
`workflow_dispatch` and creating its own tag: that is the only route to a
release from inside a session. Deleting a merged branch has no such route; it
stays a click on the pull request page.

## Development machine environment

Windows. Working copy at `C:\tandem`. `git push` works because the GitHub
credential is already in the credential helper — **do not try to read the
credentials file** (it is blocked, and rightly so): just run `git push` and Git
uses it. This account's GitHub MCP integration is **read-only**:
`create_repository` and `push_files` return 403. Use `git` directly.
