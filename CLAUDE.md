# Tandem — context for the agent

Read this before touching anything. This file exists so that a fresh session can
pick the work back up without re-paying for discoveries that were expensive the
first time.

## What it is

A `.deb` package that makes `.exe`, `.msi`, `.apk`, `.xapk`, `.AppImage` and
`.jar` open with a **double click** on Linux. It is not a prefix manager and not
a Bottles replacement: it is a **thin layer of decision, translation and
diagnosis** on top of `wine`, `winetricks -q`, `waydroid`, the AppImage runtime
and `java`.

The target user is not a programmer. The quality bar is: *no error path may end
in silence.* "I double-clicked and nothing happened" is treated as a bug, not as
a limitation.

## Inviolable rules

1. **Never write into a Wine prefix Tandem did not create.** Our prefixes carry
   the `.tandem-prefixo` marker. Any other one is read-only to the automation:
   Tandem runs the program inside it, reports what is missing, and **stops**.
   This exists because the origin machine also runs a point-of-sale system in
   its own prefix — installing a dependency inside a working production
   environment is worse than not automating at all.
2. **User-facing messages in Portuguese, no jargon.** `NO_MATCHING_ABIS` becomes
   "este app é feito só para celular e não roda aqui".
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

Four deliberate exceptions, all of them for the same reason — the product's user
is a Brazilian shop owner who is not a programmer:

1. **Every string shown to the user stays in Portuguese.** That is rule №2 above
   and it is a product requirement, not a preference. It covers whatever goes to
   `t_erro`, `t_aviso`, `t_ok`, `t_pergunta`, `t_texto`, `zenity`, and the help
   text in `uso()`.
2. **The command names the user types stay in Portuguese** — `preparar`,
   `programas`, `desinstalar`, `dados`, `alternativas`, `receita`, `memoria`,
   `esquecer`, `socorro`, `contribuir`, `lista`. Most carry an English alias for
   people who expect one.
3. **Anything shipped inside the package stays in Portuguese**, because it is
   product, not repository: `man/tandem.1` (the user reads it with `man
   tandem`), the `Name`/`Comment` fields of the `.desktop` files, and the
   `xml:lang="pt_BR"` comments in `src/mime/tandem.xml`.
4. **`LEIAME.md` and `CONTRIBUINDO.md` stay in Portuguese.** They are the front
   door for the audience that actually runs this software, and a test keeps
   their command lists in sync with the English pair.

The short form: **the repository is English, the product is Portuguese.**

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
                          native formats (arch, java, fuse, menu entries)
src/lib/winedeps.sh       DLL -> winetricks verb; DLLs with no translation
src/lib/apkinfo.py        binary AndroidManifest reader, pure Python
src/lib/peinfo.py         PE import-table reader, without executing anything
src/lib/appimageinfo.py   AppImage ELF header: generation, arch, payload offset,
                          and whether the download finished
src/lib/jarinfo.py        jar manifest + bytecode major: is it a program, and
                          which Java does it need
src/lib/verbos.tsv        GENERATED DLL->verb index; do not edit by hand
src/lib/limites.tsv       signatures of what will never work (dongle, driver)
src/lib/alternativas.tsv  Linux programs that do the same job
tools/indice-winetricks.py  generates verbos.tsv by reading the installed winetricks
proofgate.json            evidence gate: stack, coupled files
.github/workflows/ci.yml  suite + lintian + a real install cycle
.github/workflows/release.yml  tag -> build, verify, publish the .deb
src/bin/tandem            CLI + zenity panel; 20 commands
src/bin/tandem-exe        the run->detect->install->retry loop
src/bin/tandem-apk        pre-flight + install; xapk/apks via adb install-multiple
src/bin/tandem-appimage   exec bit, arch, truncation, FUSE workaround, menu entry
src/bin/tandem-jar        program-or-library, Java version, Class-Path, JavaFX
src/bin/tandem-repair     the MIME association dispute
src/polkit/               narrow rule: only start/restart of waydroid-container
tests/run.sh              the suite; tests/mkapk.py generates the synthetic packages
tests/real-programs.sh    REAL software, weekly: PuTTY/Notepad++/7-Zip/WinMerge
                          pinned by sha256, window checked with xdotool; builds a
                          real AppImage with appimagetool and compiles a real jar
docs/IDEAS.md             idea ledger with verdicts; the rejected ones with the reason
docs/LIST-FORMAT.md       the community list record, field by field
lista/lista.tsv           the published list; empty until real people report
```

Commands (`tandem --help` is the source of truth):

```
install    programas   desinstalar   preparar     android
doctor     autoteste   repair        backup       restore      dados
protect    alternativas  receita     memoria      esquecer     logs
lista      contribuir  socorro
```

Build and verify:

```bash
python3 build.py --check
bash tests/run.sh          # 364 tests, no Wine, no Waydroid, no install
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

- **No project does automatic dependency detection for `.exe`.** Not Bottles,
  not Lutris, not PlayOnLinux — all of them require a human picking from a list.
  Tandem's loop is new work; calibrate your expectations of its hit rate.
- **Bottles cannot install dependencies from the command line** (GUI only),
  which rules it out as an engine.
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
- **Waydroid is not in the Ubuntu/Zorin repositories.** `apt-cache policy
  waydroid` answers `Candidate: (none)`. It comes from `repo.waydro.id`, with a
  signing key.

## State

Verified **on real Linux** (Ubuntu 24.04 noble, the same base as Zorin 18, with
root), no longer only by reading:

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
- 364 automated tests in `tests/run.sh`; CI on GitHub Actions.
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

## Next steps

The full idea ledger — the 52 ideas from both panels, each with a verdict, and
the rejected ones with the reason written down — lives in `docs/IDEAS.md`. Read
it before proposing anything new; half the obvious ideas were already turned down
for a reason.

The queue, in order:

1. **Fill the community list.** The mechanism exists and is empty. Inventing a
   line would be exactly the mistake the `confidence` field exists to prevent, so
   it only fills with reports from real people. `tandem contribuir` builds the
   line; the issue template receives it.
2. **A real shop program.** `tests/real-programs.sh` now runs real Windows
   software weekly and checks the window on screen, which closes the "no real
   binary has ever run on it" gap. What it does NOT close is commercial software
   on a counter: a Brazilian POS system, an accounting package, a fiscal printer
   driver. That remains the project's largest uncertainty and no amount of CI
   fixes it.
3. Field-test what has not run on the owner's machine yet: `preparar`,
   `desinstalar`, `dados`, `socorro`, a double click on a real `.xapk`, and a
   double click on a real `.AppImage` and `.jar`.
4. `.apkm` support is declared but only `.xapk`/`.apks` were tested.
5. Clone a prefix with .NET already in it instead of running `dotnet48` from
   scratch (30 min, high failure rate) — delivery proof was the prerequisite and
   now exists; what is missing is the care never to read from a protected prefix
   in use.
6. The next native formats, in the order `docs/IDEAS.md` argues for: `.deb` and
   `.rpm` (a `.deb` double-clicked is a dependency problem with a bad error
   message; an `.rpm` on Debian is a "this is for another distribution" verdict
   that nothing gives today), then `.flatpakref`. `.msix` was rejected and the
   reason is written down — do not reopen it without reading that first.

**Done, do not redo:** `.AppImage` and `.jar` are implemented, tested and
verified end to end on real files — see the State section for exactly what was
measured. The orphan-shortcut question is settled: it was never a defect. The
real-program harness exists and is green. v3.6 is published — tag, `.deb` and `.sha256` attached,
and the published artifact verified byte-for-byte identical to a local build.
The next release goes out the same way; see the section below for why the
browser path exists.

## What an agent session cannot do here

Verified, not assumed — the credential is not the limit, the proxy is. It
authenticates as the repository owner, and these still fail:

- `git push origin <tag>` and `git push origin --delete <branch>`: HTTP 403
  from the git proxy. It allows updating an existing branch, not creating or
  deleting a ref.
- `POST`/`DELETE` on `/git/refs` via the API: HTTP 403, "Write access to this
  GitHub API path is not permitted through this proxy."

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
