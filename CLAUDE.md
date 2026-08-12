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
src/lib/debinfo.py        .deb control by hand (ar + tar, zstd via libzstd):
                          name, arch, dependencies, and truncation
src/lib/rpminfo.py        .rpm header: name, version, arch, distribution
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
```

Commands (`tandem --help` is the source of truth):

```
install    programas   desinstalar   preparar     android
doctor     autoteste   repair        backup       restore      dados
protect    alternativas  receita     memoria      esquecer     logs
idioma     portas      identidade
lista      contribuir  socorro
```

Build and verify:

```bash
python3 build.py --check
bash tests/run.sh          # 499 tests, no Wine, no Waydroid, no install
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
  account. Since 3.9 sending is automated, and **since 4.1 it is ON BY DEFAULT**.
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
- **`grep -c` on an EMPTY file prints 0 and then exits 1**, so `grep -c ... ||
  echo 0` prints "0" twice. It reached the owner as a queue length of "0\n0".
  Use `awk 'END { print NR + 0 }'`.
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
- **`E: Unsupported file X given on commandline` from apt means the file is
  NOT THERE**, not that the package is broken. Measured against a real apt:
  a valid `.deb` installs, a truncated one and an HTML error page both give
  `Could not read meta data`, and only a missing path (or an unrecognised
  extension) gives `Unsupported file`. Cost a field session to a package that
  was intact all along.
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
- 499 automated tests in `tests/run.sh`; CI on GitHub Actions.
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

## The language system (4.1)

Seven languages: `pt_BR` (the original), `en`, `es`, `fr`, `zh_CN`, `hi`, `ar`.
Read this before touching a message anywhere in the tree.

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
  **Why NOT the gettext runtime**, which is the other half of the decision:
  `msgfmt` at build time breaks rule 5 (the packager depends on nothing and
  runs on Windows), and a `.po` parser is sixty lines of Python. `%1$s` would
  also undo the `{1}` decision below. `msgmerge` is not used either, for the
  same reason: the development machine is Windows.
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

### The migration is finished

`tools/conta-literais.py` reports **TOTAL 0** across `src/bin` and `src/lib`,
and the suite asserts that number, so the next literal added anywhere fails a
test. 404 keys in each of the seven catalogues.

**The counter is the interesting part of this, not the translation.** It was
wrong EIGHT times, each time narrower than reality, and it never once failed
safe - every version reported zero for something that was there:

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

**The lesson, which is the reason this is written down:** a completeness check
built from what happened to be in front of me will always pass. The measure only
became trustworthy at the moment it caught something. If you add a message in a
shape not listed above, the counter will happily report zero.

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

The queue, in order:

0. **Field-test 4.1 on the counter.** The translation is done; this half needs
   the owner's machine and nothing else: `tandem portas` (32 phantom sockets
   collapsed into one line), `tandem intalar` (must say "I do not know that
   command", not "unrecognised file type"), `tandem idioma`, and a double click
   on a real `.xapk`, `.AppImage` and `.jar`.

0b. **Five catalogues carry `X-Reviewed-By-Speaker: no`.** That is the whole of what is left
   of the translation, and it is not engineering: it needs somebody who speaks
   es, fr, zh_CN, hi or ar to read what is there. The files are plain text, the
   format cannot execute anything, and a wrong line breaks nothing - it is the
   easiest contribution this project can ask for. The data tables are complete
   in all six.

1. **Fill the community list.** Half-solved in 3.9: the client side of automatic
   sending is built, tested against a real socket, and ON by default. What is
   missing is not code - it is an ADDRESS. `TANDEM_LISTA_ENVIO` is empty because
   an endpoint means somebody hosts it, moderates it and answers for the data.
   That is the architect's call. Until then the queue keeps what it learns, and
   `tandem enviar` says so out loud rather than pretending.
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
5. Clone a prefix with .NET already in it instead of running `dotnet48` from
   scratch (30 min, high failure rate) — delivery proof was the prerequisite and
   now exists; what is missing is the care never to read from a protected prefix
   in use.
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
real-program harness exists and is green. **v4.0 is published** — tag, `.deb`
and `.sha256` attached, and the published artifact verified byte-for-byte
identical to a local build (sha256 `82544a90…`). 3.7 through 3.9 were never
released, so 4.0 is the first package the public gets with all nine formats in
it. The next release goes out the same way; see the section below for why the
browser path exists.

**Two guards were added because the release itself found the defects**, and
both are in the suite now rather than in a failed workflow: the newest
changelog entry must be dated after the one below it (lintian refuses
otherwise, and it has caught this project twice — both times because an
*earlier* entry carried a timestamp in the future), and the test-count badge
must be within 15 of what the suite actually runs. The first version of that
badge guard was itself one-sided and blocked a good release, because CI runs
two more checks than a bare container: **a guard that stops a good release is
worse than the drift it was written for.**

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
