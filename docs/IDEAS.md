# The Tandem idea ledger

Two adversarial panels ran over this project (31 ideas in the first, 21 in the
second, with independent judges on each). Several turned into code before this
file existed, and the rest would have been lost with the session. This is the
synthesis.

Every entry carries a **verdict**. An idea without a verdict is conversation; a
rejected idea with the reason written down is worth as much as an accepted one,
because it stops the next contributor from re-proposing the same mistake.

Legend:

| | |
|---|---|
| **DONE** | in the code, with a test |
| **NEXT** | accepted, queued, design already settled |
| **LATER** | accepted, but blocked on something that does not exist yet |
| **REJECTED** | with the reason — do not re-propose without a new argument |

---

## The criterion that separates good from bad

The panel only became useful once there was a criterion to judge by. It is this:

> Tandem does not compete at "running Windows programs". Wine, Bottles, Lutris
> and PlayOnLinux do that better and have done it longer. What nobody does is
> **close the diagnostic loop for someone who cannot read a log.** Any idea that
> increases the number of things Tandem executes is worth less than any idea
> that increases the number of things Tandem **explains**.

The hard corollary, which killed nine ideas at once: *a feature the shop owner
cannot even notice exists is not a feature.*

---

## 1. Not losing what cannot be replaced

The blind spot the second panel's critic found, which alone justified running
the panel: of the 52 ideas across both rounds, **zero** were about what the
programs write. All of them were about opening the programs. The environment
rebuilds in twenty minutes; a seven-year customer database does not.

Worse: there were **three code paths deleting user data with no copy.**

| Idea | Verdict |
|---|---|
| **`tandem dados`** — separate, in the program's head and the owner's, *environment* (rebuildable) from *data* (irreplaceable). List what each installed program writes, where, and how big it is. | **DONE** — v3.4 |
| **A mandatory copy before every destructive path.** `rm -rf` of an incomplete prefix, `tandem desinstalar`, `tandem restore` overwriting. | **DONE** — v3.4; the copy never blocks the operation, it only precedes it |
| **`tandem backup` splitting the two volumes.** The 30-minute `.NET` and the customer database in the same `.tar.gz`, weighing the same. A backup that takes too long does not get taken. | **DONE** — v3.4: `tandem dados salvar` is the light volume, and `backup` now says how much of the total is your own files |
| **Finding data without guessing**: `Documents`, `AppData/Roaming`, and — the case that matters — `.mdb`, `.fdb`, `.dbf`, `.sqlite` inside the program's own folder, which is where Brazilian commercial software keeps its database. | **DONE** — v3.4 |
| Scheduled automatic backups | **REJECTED** — silent scheduling fills a shop machine's disk with nobody noticing, and a full disk is one of the failure causes Tandem itself diagnoses. Copy on command, with the size stated first. |
| Syncing data to the cloud | **REJECTED** — a shop's customer data leaving the machine because an automation decided to. Not our decision to make. |

## 2. Knowing whether it actually worked

Wine's characteristic failure with commercial software is not exiting with an
error — it is **opening and being subtly wrong**. A report that prints blank,
accented characters turning into boxes, a window that opens behind another.
`exit 0` used to mean "it opened", which became `RESULTADO=abriu` in memory, and
then a recipe exported to the neighbour's machine.

| Idea | Verdict |
|---|---|
| **Distinguish "the process exited 0" from "the program worked".** Exiting in a few seconds with nothing on screen is not success: it is an executable that died quietly. | **DONE** — v3.4, by lifetime. `xdotool`/`wmctrl` were rejected: they do not exist on a shop machine |
| **Ask, once, after it closes:** "did the program work the way you expected?" That answer is the only E4 signal that exists. | **DONE** — v3.4. Once per program; repeating would become a nuisance, and a nuisance is something people learn to dismiss unread |
| **Mark the recipe with where the confidence came from**: "the owner confirmed" weighs differently from "the process exited 0". | **DONE** — v3.4, `CONFIANCA` field |
| **Test printing explicitly.** For shop software, printing *is* the program. Wine + CUPS works; Wine + a USB thermal printer, almost never. | **LATER** — needs a real shop program first |
| Automatic screenshot of the opened window | **REJECTED** — a POS screen has customer data on it. You do not store that without asking. |

## 3. Learning and memory

Already implemented. The design that survived the panel:

| Idea | Verdict |
|---|---|
| **Memory keyed by file, not by name.** Identity = `sha256` of size + first and last MiB. Filenames lie (`setup.exe` is thousands of different programs); contents do not. | **DONE** |
| **Memory SUGGESTS, never decides.** It shortens the path only if the owner says so. Installing automatically based on a past lesson means repeating a mistake forever — and in a shop's prefix that is expensive. | **DONE** — and it is the rule that prevents the whole idea's worst failure mode |
| **A negative lesson is also a lesson**: `NAO_RESOLVERAM` records what was installed and did not help, so it is not promised again. | **DONE** |
| **A suspect negative lesson does not become a lesson.** If the requested DLL never even arrived, the error was my translation — recording it would teach the mistake to the next machine. | **DONE** — v3.3 |
| **`tandem esquecer`** — memory needs an exit door, or it becomes debt. | **DONE** |
| Usage profiling / telemetry of which programs the owner opens | **REJECTED** — nothing the owner cannot see and cannot delete. |

## 4. Collective knowledge

The original request was a bridge server between all Tandems. The idea is good;
it is the server implementation that is expensive and risky. The panel found the
middle ground, and the project owner later found a better one.

| Idea | Verdict |
|---|---|
| **A recipe: an exportable text file with what that program needed.** `tandem receita` exports, imports and validates. Collective knowledge over WhatsApp — no server, no account, no company, no privacy regime to comply with. | **DONE** |
| **Validate everything coming in.** A recipe is third-party content: a verb only passes if it has the shape of a winetricks verb name. Without that, a recipe becomes remote code execution. | **DONE** |
| **A recipe carries no path and no machine name.** Only the program/verbs pair. | **DONE** |
| **A real bridge server**, with aggregation: "on 340 machines this program needed these three components". | **DONE differently** — v3.4. The owner proposed the right model: instead of a server, **a static text file fetched over HTTPS**, like an ad blocker's filter lists. That is why EasyList survives on a volunteer's budget. Down is automatic; **up is not** — `tandem contribuir` builds the line and the owner sends it. Format in [LIST-FORMAT.md](LIST-FORMAT.md) |
| Automatic sync on install | **REJECTED** — a shop's machine does not talk to any server unless the owner says so. |

## 5. Native alternatives

| Idea | Verdict |
|---|---|
| **Suggest a Linux equivalent — but only when the program cannot be fixed.** That is the difference between helping and proselytising: suggesting LibreOffice to someone who just successfully installed Office is arrogance; staying quiet when the program depends on a dongle that will never work is abandoning them. | **DONE** — only fires on the `LIMITE` branch |
| **Classify into `nativo` (does the same thing) and `parecido` (trades something away), and say what changes.** "Opens the same files, but Excel macros will not run" is the honest sentence. | **DONE** |
| **Recognise what will never work before running it**, by reading the `.exe`'s import table: HASP/Sentinel, CodeMeter, `winusb`, driver DLLs. | **DONE** — `limites.tsv` + `peinfo.py` |
| Suggest a web (SaaS) alternative | **REJECTED** — trading a program that runs offline for one that requires internet, in a shop, is a downgrade. |

## 6. Diagnosis and honesty

Where the project actually beats the competition.

| Idea | Verdict |
|---|---|
| **`tandem autoteste`** — `doctor` *lists* what exists; the self-test *exercises*. Five field defects were invisible to a list. | **DONE** |
| **Read the failure reason from winetricks' own words** instead of dumping the log: full disk, wrong system clock, DNS, checksum, missing `cabextract`. | **DONE** |
| **Delivery proof** — check the DLL actually arrived instead of trusting the exit code. | **DONE** — v3.3 |
| **The winetricks index as an auditor of the hand-written table.** Invert winetricks' own `w_override_dlls` and compare. It found six mistranslations, one of them installing an Adobe font manager in place of the Visual C++ runtime. | **DONE** |
| **The auditor's blind spot**: it only read `w_override_dlls`, and `vcrun2003` declares `mfc71`, `msvcp71` and `msvcr71` only in `title=` — it was blind exactly where the table was wrong. | **DONE** — v3.4: it reads the title too, behind two narrow filters. 246 → 274 DLLs |
| **Record suspect translations to a file** instead of just complaining on screen: that file is the work list for fixing the table. | **DONE** — v3.3 |
| **`tandem logs`**, which opens the latest log without the owner needing to know where it lives. | **DONE** |
| Upload the log for automated analysis | **REJECTED** — a Wine log contains paths, filenames and sometimes a customer's name. |

## 7. Installing and preparing the environment

| Idea | Verdict |
|---|---|
| **`tandem preparar`** — install Wine, winetricks, adb and Waydroid in one go, including the Waydroid repository with its signing key and `dpkg --add-architecture i386` in the right order. | **DONE** |
| **Offer to install Wine at double-click time**, instead of telling people to open a terminal. That is the moment they want it solved. | **DONE** |
| **You cannot install from `postinst`** — `dpkg` holds a lock and an `apt-get` in there waits forever. | **DONE** — which is why `preparar` is a separate command |
| **`tandem programas`** — GNOME under Wayland does not re-read the application menu until you log out and back in, and `update-desktop-database` does not fix it. Without a list of its own, the owner installs something and cannot find it. | **DONE** |
| **Clean up orphaned shortcuts** — a `.desktop` whose `.lnk` is gone is a button that opens nothing. | **DONE** |
| **Clone a prefix with `.NET` already in it** instead of running `dotnet48` from scratch (30 min, high failure rate). | **REJECTED as designed** — see below. It was investigated in 4.2 and the investigation is what found the three defects 4.2 fixes; the copying itself must not be built the way it was proposed |
| Bundle Wine inside the `.deb` | **REJECTED** — 400 MB, licensing, and it would make us responsible for updating Wine. |

### Why the prefix mould is rejected as designed

The idea: `dotnet48` costs about half an hour and fails often, so keep a prefix
that already has it and copy that instead. The proposal was reviewed in 4.2
along four lines — rule №1, delivery proof, the copy itself, and what a mould
store does to the rest of the code — and it failed on all four. None of the
objections is about effort; each one is a way the shop owner loses something.

- **The only legal donor is the shop's production prefix.** Rule №1 forbids
  writing into a prefix Tandem did not create, and there is no read-only way to
  answer "is this prefix in use right now": every `wineserver` probe writes into
  the prefix it probes. So the check that would make reading safe is itself the
  violation. And the machine this project was born on runs a point-of-sale
  system in its own prefix — that is the prefix a mould would want.
- **The proof of delivery would have approved an empty mould.** Measured, and
  it is the defect 4.2 fixes: `t_dll_do_verbo dotnet48` answers `mscoree.dll`,
  and `mscoree.dll` is in both `system32` and `syswow64` of a prefix with no
  .NET at all, because Wine put it there. A mould with nothing in it would have
  been stamped as complete, and the receipt is permanent under rule №4.
- **A prefix is not a folder of files.** Measured on a real prefix: `wineserver`
  is mode `-r--------`, 11 bytes, and its content is the name of a private
  `/tmp` directory (`wine-P0uk1W`) — a copy run by another user cannot reach it.
  `dosdevices/z:` is a symlink to `/`, so a `tar --dereference` over a prefix
  walks the whole filesystem, and `dosdevices/com1` points at a device node.
  Copying a prefix correctly means knowing which of these to drop, and getting
  it wrong writes the owner's home directory into the artifact.
- **A mould store is a second `.tandem-prefixo`-marked tree.** `t_prefixo_do_arquivo`
  resolves into it and Tandem believes it may write there — so the store becomes
  a prefix Tandem installs into by accident, which is the opposite of a mould.
- **A copy interrupted by a full disk leaves a prefix every existing check calls
  complete.** "Complete" means `system.reg` exists; a truncated copy has one.

What survives, and it is the honest version of the idea: **pay `dotnet48` once
into a prefix Tandem creates for that purpose**, never into or out of somebody
else's. That needs no cloning, no store, no reading of a production
environment, and it keeps rule №1 untouched. It is not built yet, and the
prerequisite it was waiting for — a delivery proof that can actually fail for
`dotnet48` — only started existing in 4.2.

## 8. Android

| Idea | Verdict |
|---|---|
| **Read the binary `AndroidManifest.xml` without the SDK** and compare `minSdkVersion` and ABIs against the running Android, *before* installing. | **DONE** — `apkinfo.py`, pure Python |
| **Parse the output of `waydroid app install`**, which exits 0 even when it fails. | **DONE** |
| **Wait for `sys.boot_completed`**, not `Session: RUNNING`. With GAPPS that is another 20–60 s. | **DONE** |
| **Register `.xapk`/`.apks`/`.apkm` as their own MIME type** — without it the system sees a generic ZIP and the double-click never reaches Tandem. | **DONE** |
| Android Translation Layer (ATL) as a rival to the double-click story | **NOTED, not a rival — 2026-08-13.** ATL's `--install` writes a per-app `.desktop` launcher through xdg-desktop-portal, which is the strongest counter to "nobody makes a `.apk` just work". But it is a per-app shortcut created from a terminal command, **not a file-type handler**, and launching still needs the Java activity name passed by hand. Tandem beats it cleanly: a real MIME handler, split-format aware, no activity name. Worth the one line so the objection is pre-empted. |
| **Say plainly that USB does not exist inside Waydroid.** Thermal printer, card reader, scale, barcode scanner: none of it passes through. For a shop, that sentence saves an afternoon. | **DONE** — it is in the README |
| USB passthrough to Waydroid | **REJECTED, and the reason was wrong until 2026-08.** It was rejected as nonexistent. It exists: Waydroid's LXC config denies no devices, the maintainer shipped `persist.waydroid.uevent` for exactly this, and the actual barrier is that the image does not declare `android.hardware.usb.host` — a 60-byte XML file in a directory Waydroid already bind-mounts. Two people published working procedures. It stays rejected for two better reasons. **Durability:** the working route edits the shipped images and reverts on the next Waydroid update, so a shop's hardware would stop working after an unrelated upgrade, with no message — the precise failure this project refuses to ship. **Rule №1:** editing images Tandem did not create is the Waydroid analogue of writing into somebody else's Wine prefix. And **it would not help anyway**: nobody in any language has reported a printer, pinpad or scale working inside Waydroid even with the feature enabled, while all four are well supported on plain Linux. Diagnose it (`tandem doctor`) and point at the Linux path (`alternativas.tsv`); do not automate it. |

## 9. For the shop owner

| Idea | Verdict |
|---|---|
| **No error path ends in silence.** It is the whole project's yardstick, and the most expensive defect ever found here (zenity refusing accented text under a locale that was never generated) erased the entire interface without a trace. | **DONE** |
| **Portuguese without jargon.** `NO_MATCHING_ABIS` becomes "this app is built for phones only and will not run here". | **DONE** |
| **Take the blame when the blame is ours.** "I installed the dependencies and it still does not open" sends the owner hunting for a defect in a machine that is fine. | **DONE** — v3.3 |
| **State the cost before spending it.** `.NET` takes half an hour; the person needs to know that *before* clicking, not after. | **DONE** — it is in the verb's friendly name |
| **Stop the machine suspending mid-install** — suspending halfway corrupts the prefix. | **DONE** — `systemd-inhibit`, and since v3.4 it is exercised rather than assumed |
| **A "send me the diagnosis" button** producing one file the owner can send to whoever is helping. | **DONE** — v3.4, `tandem socorro`. Its first line says what is inside, because it shows the owner's file paths |
| A multi-screen first-run wizard | **REJECTED** — the product's promise is *two clicks*. A welcome wizard is the negation of it. |

## 10. Engineering

| Idea | Verdict |
|---|---|
| **An evidence hierarchy** (E0 believed → E1 static → E2 tested → E3 exercised → E4 in production), with "done" requiring ≥ E3. | **DONE** — from ProofGate, and it produced almost every fix in this project |
| **A packager that does not depend on `dpkg-deb`** — writes the `ar` archive by hand and runs on any OS. | **DONE** |
| **Reproducible builds**, checked in CI. | **DONE** |
| **CI that really installs, configures and purges the package** on Ubuntu 24.04, the base of Zorin 18. | **DONE** |
| **Executables honouring `TANDEM_LIB`.** With the path hard-coded to `/usr/lib/tandem` there was no way to exercise the main loop without installing the package — and the main loop was precisely the thing that had never run. | **DONE** — v3.3 |
| **Mutation-testing new tests**: break the code on purpose and confirm the test fails. A test that cannot fail proves nothing. | **DONE** — applied to every test block added since v3.3 |
| **The suite must point at the repository, never at the installed package.** Without that, on a machine with Tandem installed the suite was approving the old version. | **DONE** |
| **Generate the doc-drift test from the dispatch table** instead of a hand-written list. With a fixed list it went green while four new commands were in no document at all. | **DONE** — v3.5 |

---

## What running on real Linux added

None of this came from the panels. It came from running the loop with Wine 9.0,
real `winetricks` and an ordinary user account on Ubuntu 24.04 — the same base
as Zorin 18.

| Finding | Verdict |
|---|---|
| **`exec` without a command applies its redirections to the entire shell.** `exec 7> file 2>/dev/null` does not silence the `exec`: it silences stderr for the whole rest of the program. With no graphical session, the loop detected the right DLL, translated it correctly, assembled the correct message — and exited 53 with **zero bytes**. It was hiding inside the code written to fix a silent failure. | **DONE** — four occurrences |
| **Bitness.** winetricks delivered `mfc42.dll` into `syswow64` (32-bit) for a 64-bit program. The v3.3 delivery proof looked in both folders, approved, and wrote the receipt: the dead end again, now with a receipt on top. Half the verbs ship 32-bit payloads only, and winetricks says so in English in the middle of the log. | **DONE** — the check is per-architecture, with a third outcome and its own message |
| **`systemd-inhibit` exists and does not work.** Without D-Bus it exits 1 and takes the wrapped command down with it — and the owner was told to check an internet connection that was perfectly fine. Presence is not function. | **DONE** — it is exercised before use, and the probable cause is only asserted when there is evidence of a download attempt |
| **`t_texto` reads its content from stdin; the argument is the title.** Five new commands passed the text as the argument: they ran, exited 0 and printed nothing. No test caught it because every test exercised library functions, never a whole command. | **DONE** — and a test now runs each command and demands output |
| **The memory/list shortcut bypassed the delivery proof**, writing the receipt from the exit code alone — and doing so on the one path where the lesson comes from outside and deserves *more* suspicion, not less. | **DONE** — v3.5, found by an adversarial audit |
| **Choose the `_x64` verb when the program is 64-bit.** A verb-by-verb survey settled it: most modern verbs already install both payloads, exactly one has a 64-bit sibling (`xact` → `xact_x64`), and eight are 32-bit-only with no sibling. | **DONE** — v3.5. For those eight, a 64-bit program gets warned before the download rather than after |

## The long game: an OS, and why I would not build one yet

The project owner's stated destination: a Linux-based OS that natively runs
Linux, Android **and** Windows install packages, where the OS itself manages
whatever is needed to make them run — plus closing the small places where
Windows is simply nicer than Linux. The example given is exact: on Zorin you
cannot right-click the desktop and create a new file.

The substance is right, and Tandem is already the seed of it. The insight this
project was built on — *the value is not in running the program, it is in
closing the diagnostic loop for someone who cannot read a log* — is an
operating-system-shaped insight. What Tandem does per file, an OS does
system-wide.

Three judgements about it, written down so they can be argued with later.

| Question | Verdict |
|---|---|
| **Should this become a distribution?** | **NOT YET — build the layer, not the distro.** Distributions die of maintenance, not of ideas: security updates, kernel/Mesa/Wine churn, hardware regressions, forever, for every user. A layer installs on the machine somebody already owns — day-one users, no reinstall, and the same code benefits Zorin, Ubuntu and Fedora users at once. If it ever becomes an OS, let it be because the layer got so good that shipping it preinstalled is the obvious move. That is how Bazzite happened; it is not how LindowsOS happened. |
| **Should the goal be "as good as Windows"?** | **RECONSIDER.** Wine will never be Windows for kernel drivers, hardware dongles or Play Integrity, and those are exactly the 5% a shop's livelihood runs on. Competing on parity means losing on the part that matters. Tandem's real edge is the opposite and it is rarer: **it never lies about what it cannot do.** A `limites.tsv` that says "this will never work, here is why, here is what to do instead" is worth more to a shop owner than a compatibility percentage. Keep that as the identity. |
| **Is the right-click paper cut worth chasing?** | **YES — and it belongs to a sibling, not to Tandem.** The gap is not technical: in Nautilus the "New Document" submenu appears as soon as `~/Templates` contains a file. One line fixes it. That is the whole lesson — the Linux desktop is assembled from components where each owns its piece and nobody owns the experience. A layer that owns the paper cuts is a real product. But putting it inside Tandem would blur the identity that makes Tandem good. Same family, different binary. |

### What that makes the next real step

Not an OS. **One handler for every install format a person can double-click.**

Today, on a normal Zorin desktop: double-clicking an `.AppImage` does nothing,
because it arrives without the executable bit. A `.jar` does nothing. A
`.flatpakref`, an `.rpm` on a `.deb` system, an `.msix` — nothing useful. That
is *the same bug Tandem exists to kill*, "I double-clicked and nothing
happened", for formats that are native to Linux rather than foreign to it.

Tandem already owns four formats and the whole diagnostic machinery. Extending
it to the Linux-native ones is the highest-value work available, it needs no
distribution, and it is the piece the eventual OS would have needed anyway.

| Format | What happens today | Verdict |
|---|---|---|
| `.AppImage` | nothing — arrives without the executable bit | **DONE in 3.7** — chmod, arch, truncated download, FUSE worked around, menu entry from the image's own desktop file |
| `.jar` | nothing, or an archive manager opens it | **DONE in 3.7** — program-or-library from the manifest, Java version from the bytecode, `Class-Path` checked against the folder |
| `.deb` double-clicked | nothing at all on the reference machine; a store elsewhere, where a missing dependency reads as a broken file | **DONE in 3.8** — apt simulated before the password, and the release-mismatch verdict separated from the missing-repository one by the shape of the name |
| `.rpm` on a Debian system | nothing useful | **DONE in 3.8** — explained, never converted, and answered with the equivalent from the machine's own repositories |
| `.flatpakref` / `.flatpakrepo` | handled only if a store is installed | **DONE in 3.8** — installs per-user; a .flatpakrepo is called a SOURCE, not an application |
| `.snap`, loose file | needs `--dangerous`, which no tool explains | **DONE in 3.8** — the flag is named to the owner before it is used |
| `.sh` / `.run` installers | a text editor, or a "Run in Terminal" prompt showing nothing | **DONE in 3.8** — and the MIME type deliberately left with the text editor |
| `.msix` / `.appx` | nothing | **REJECTED for now** — Wine support is not there; promising it would be a lie |
| kernel work, own package manager, own desktop | — | **REJECTED** — this is where projects of this shape die |

### What the nine taught, for whoever adds a tenth

Worth writing down, because both lessons generalise and neither was obvious
before the work.

**The diagnosis is worth more than the execution.** Running an AppImage is one
`chmod` and one `exec`. What took the work was the five things that go wrong
afterwards, and four of the five are readable off the file *before* running it —
the truncated download, the wrong processor, the generation, the payload size.
The pattern is `peinfo.py` all over again: the file already knows why it will
fail, and nobody asks it.

**Check every claim against the format's own reference implementation.** Two
claims here could have been wrong for years without anyone noticing: that the
payload offset equals `e_shoff + e_shentsize * e_shnum`, and that class file
major minus 44 is the Java version. Both are now checked in CI against the
authority that decides them — the AppImage runtime's own `--appimage-offset`, and
a JVM that refuses to load a class one version too new. Neither check needs a
maintainer to remember anything.

And one that cost a wrong answer before being caught: **the exceptions in a
format are the whole job.** `META-INF/versions/` exists so a *newer* Java picks
those classes up, so counting them announced "needs Java 30" for a jar that runs
fine on 21. `.deb` had the same shape of trap twice: a package truncated exactly
on a member boundary parses cleanly, and a dependency's architecture qualifier
(`python3:any`) is not part of its name. Every format has one of these. Find it
before shipping.

**Ask the system, do not re-derive it.** The best single decision in the `.deb`
work was not writing a dependency resolver: `apt-get install -s` runs
unprivileged and answers authoritatively, so the resolution is apt's and only the
TRANSLATION is ours. A resolver in shell would have been a second opinion, wrong
exactly when it disagreed with the one that counts. The same test applies to the
next format: what already knows the answer, and can it be asked without a
password?

**Two verdicts that a tool writes identically can be opposite for the owner.**
apt says "not installable" for both "built for another release, nothing to try"
and "needs a repository you have not added, here are the instructions". The
distinction is not in apt's output at all — it is in the SHAPE OF THE NAME, a
library with a release welded into it versus a plain program name. Finding that
distinction is the work; the message is the easy part.

**A refusal has two causes and only one may be silent.** "The owner clicked
Cancel" and "there was nobody to ask" arrive at the same branch, and treating
them the same produced a handler that exited 0 with zero bytes. Every new
question needs `t_tem_gui ||` on its refusal path, and the test that catches it
is running every handler with no window and no terminal and demanding a sentence.

## The other family: a real Windows in a virtual machine

Checked in August 2026, on the sources rather than on memory, because the
question "is somebody already doing this better?" deserves a real answer.

There are two families of tools for running Windows software on Linux, and
they are not competing — they answer different questions.

| | What runs the program | Where the window comes from |
|---|---|---|
| Wine, Bottles, **PlayOnLinux**, Proton, CrossOver | Wine reimplements the Windows API. No Windows anywhere. | Wine draws it natively |
| **WinApps**, **WinBoat**, **Dockur/windows** | A real Windows, in QEMU/KVM | RDP: real Windows draws it, FreeRDP RemoteApp composites the single window onto the Linux desktop |

**What the second family reaches that Wine cannot**, and this is the whole
reason the row exists: a real Windows has a real kernel. A `.sys` driver
loads for real. A legacy HASP4 dongle is handed to the guest with QEMU's
`-device usb-host,vendorid=…,productid=…` and talks to its own driver. Those
are precisely the dead ends this project declares — and a dead-end message
that does not mention them is true about Wine and false about the machine.

**What it costs, and the item every article omits:** the guest must be
Windows **Pro or Enterprise**. Home cannot host Remote Desktop at all, so the
OEM licence on a counter machine does not serve. Plus KVM enabled in the
BIOS, ~4 GB of RAM and ~32 GB of disk that stop being yours.

| Idea | Verdict |
|---|---|
| **Name the route at the dead end.** When the verdict is `driver` or a legacy `dongle`, say that a real Windows in a VM does reach it, check first whether this machine could carry one, and state the Pro-licence cost. | **DONE** — v4.0, `t_texto_maquina_virtual`. Said LAST, after the explanation: offered first it would read as giving up early, which for most programs is wrong advice. |
| **A pre-flight for that route**, in the style of the `apt-get -s` trick: `vmx`/`svm` in `/proc/cpuinfo`, `/dev/kvm`, RAM, free disk — so "buy a Windows Pro licence" is never said to somebody whose BIOS has virtualisation switched off. | **DONE** — v4.0, `t_vm_possivel`, four verdicts, also a line in `tandem doctor` |
| Exclude anti-cheat from the offer | **DONE** — kernel anti-cheat refuses virtual machines by design. Offering it there costs an afternoon and a Windows licence for nothing. |
| **Tandem installing or managing the VM itself** | **REJECTED** — this project is a thin layer of decision, translation and diagnosis. Installing Windows in a container is none of the three, it needs a licence Tandem cannot supply, and it would double the surface for the audience least able to maintain it. Tandem points, the way `tandem alternativas` points. |
| Importing WinApps' app discovery (scan the Windows registry for installed `.exe`) | **REJECTED as new work** — `tandem programas` already does exactly this by reading `system.reg`, and for the same reason WinApps does: convergent design, nothing to take. |
| **Parallels** | **NOT APPLICABLE** — Parallels Desktop is macOS-only. Parallels Workstation for Windows and Linux hosts was discontinued in 2013. Its "Coherence" mode is the same idea as RemoteApp, so it is worth knowing as prior art for the *shape*, and it is not a route on this machine. |
| **PlayOnLinux** | **NOT A RIVAL, AND MOSTLY DEAD** — it is Wine plus per-program install scripts written by hand, the model this project rejected: it works only for programs somebody already wrote a script for. POL-POM-4's own README points at Phoenicis (PlayOnLinux 5), which has been "under development" for years. |
| **WinBoat** (0.9.0 beta, 2026) | **NAME IT, DON'T MANAGE IT** — added by the 2026-08-13 sweep. It is the most usable member of this family yet: an Electron GUI over dockur/windows + FreeRDP RemoteApp, ISO in, per-app windows out, home dir auto-mounted. It belongs in the dead-end message beside WinApps/dockur. But it still needs KVM in BIOS + a container runtime + FreeRDP 3 + a Pro licence, and its USB-dongle passthrough is real-but-flaky (devices unrecognised, unmount on return — its own issue tracker). Firmly outside what a shopkeeper executes, so the verdict is unchanged: point, do not manage. |

**One wording fix the sweep forced (2026-08-13):** the VM message and this file
say "Windows Home cannot host RDP at all." That is true for the *supported*
RemoteApp path, but it is bypassable with RDP-Wrapper-class workarounds, so the
honest line is "the supported path needs Pro/Enterprise; Home only works through
a third-party, ToS-gray workaround" — which for a shop is legally and
operationally worse, not a loophole worth naming. Soften the claim, keep the
conclusion.

The forged-DMI spoofer belongs in this section too, and it is rejected for a
different reason — see below.

## The hardware identity spoof, rejected

Measured and it works: `unshare -m`, a tmpfs over `/sys/class`, a bind-mount
of a directory of hand-written DMI files, and Wine reports whatever
manufacturer, model and serial you put there — in the registry and in WMI
alike. It is the only lever that moves `GetSystemFirmwareTable`; editing
`HKLM\HARDWARE\DESCRIPTION\System\BIOS` does not, because the key is
`REG_OPTION_VOLATILE` and WMI never reads it anyway.

**REJECTED.** It is a hardware-identity forger. It works exactly as well for
defeating a licence as for honouring one, it needs privileges this project
deliberately keeps narrow — the polkit rule is scoped to
`waydroid-container` alone — and shipping it would put Tandem in the business
of manufacturing machine identities. It is written down here so that a later
session rediscovers the reason along with the trick.

What Tandem does instead, and the distinction is the whole point: it
**stabilises** an identity rather than inventing one. The volume serial of C:
and `MachineGuid` are derived from this machine's own `machine-id`, so a
prefix destroyed and remade comes back as the same computer. Same for the
Windows `ProductId`: Tandem reports that Wine's default is shared by every
Wine install on Earth, and does **not** invent a replacement, because that
would be forging a Microsoft licence identifier.

## What the 2026-08-13 prior-art sweep brought back

A seven-agent live-web sweep across eight ecosystems (the "O Terreno do Tandem"
artifact) produced borrowable techniques from the competitors and a handful of
new ideas. Each carries a verdict, same as everything above. The security one is
**DONE** already; the rest are here as decisions, and two of them are the
owner's to make, not the agent's.

### Borrowed from the competitors

| Idea | Where it comes from | Verdict |
|---|---|---|
| **Gate every published list row through the verb-safety checks in CI.** A row naming a winetricks `settings` verb (`sandbox`, `winxp`, `remove_mono`…) installs cleanly and changes the prefix — the AUR "Atomic Arch" attack (June 2026, ~1,500 orphaned packages weaponised) in miniature, and a human reviewing the weekly PR cannot eyeball a verb's class. | **DONE** — `tools/monta-lista.py` refuses a row whose `verbs` or `failed` field names a settings verb or a non-name, and reports it as left-out. The client already re-checks at the point of use (`t_verbo_de_fora_ok`); this closes the same gap at the publish step, which is the one that reaches every Tandem at once. |
| **Stack-pinning: record the Wine + winetricks version, refuse to merge across incompatible stacks.** WineHQ AppDB's hard rule — a test report is worthless unless you know exactly what stack produced it — and the fix ProtonDB applied late (its PC-vs-Deck split). | **NEXT** — a record-format bump (v1→v2), so the moment to do it is now, while the list is empty and there is zero migration cost. Append the two fields; `t_lista_linha` gains "same stack or don't merge". Pure decision/aggregation logic, dead-centre in the identity. |
| **Recency / version decay in the resolver.** ProtonDB's documented weakness is that a stale report for an old Proton never decays; the fix is to weight a newer contradicting report over an old confirmation, and treat "confirmed only on Wine older than the caller's" as reduced confidence. | **NEXT** — pairs with stack-pinning (it needs the version field to be meaningful). Belongs in `t_lista_linha`, which already merges and tie-breaks on `seen`. |
| **Downgrade, don't overwrite, when an established fingerprint's verb set suddenly changes.** The AUR orphan-adoption lesson at the record level: a sudden verb-set flip on a fingerprint with history should *lower* confidence pending re-confirmation, not silently replace the lesson — that is a reputation-inheritance vector. | **NEXT** — folds into the resolver work above. |
| **Anonymous dedup via a machine-local salted pseudonym.** ProtonDB counts one-report-per-reporter but pays with a Steam account; thread the needle with an HMAC over a secret that never leaves the box, sent as an opaque dedup key. Fixes the "3 machines beat 400" problem the list already worries about. | **NEEDS THE OWNER'S DECISION** — it changes the project's "we keep NOTHING" stance to "we keep one opaque, non-reversible per-machine pseudonym." The report argues it reveals nothing *about* the machine, and that is true; but a stable per-machine key is still pseudonymous by definition, and CLAUDE.md is explicit that holding data is the owner's call, not the agent's. Recommended, with that trade-off stated in the open. |
| **Sign the published `lista.tsv`; write the accept/reject policy down.** EasyList suffered for years without a written policy; Flathub proves provenance with a token. An adblock list gets away with plain HTTPS because a bad rule hides a div — a bad Tandem row runs an installer. | **LATER** — the policy half is cheap and is being written into `LIST-FORMAT.md`; the signature half needs a key and a decision about who holds it, which is the owner's. |

### New, from thinking with Tandem rather than copying

| Idea | Verdict |
|---|---|
| **"Por que este verbo?" — an explain-line before the pre-flight install.** Tandem already maps the missing DLL to a verb; say it in one sentence before installing ("this program is asking for MSVCP140.dll, which comes from the Visual C++ 2015–2022 runtime — I'll install that"). Turns a silent install into a legible one. It explains more and executes exactly the same, which is the criterion at the top of this file. | **NEXT** — small, and the most identity-aligned idea here. |
| **A repeatable field-test harness for a real shop program.** Not the weekly PuTTY/Notepad++ run — a `tests/real-shop.sh` the owner runs *on the counter machine* against the actual POS/accounting/fiscal installer, capturing every step of the closed loop to a report Tandem reads back. Turns "the one afternoon" into an instrument, and produces the first honest community-list record. | **NEXT** — the evaluation's single highest-leverage item; costs no code the project doesn't already have the pieces for, and needs the owner's machine and one real installer. |
| **A shareable diagnosis transcript** — after any failure, one jargon-translated, path-stripped transcript of what was tried and why it stopped, for the owner to hand to whoever helps. | **MAYBE** — check the overlap with `tandem socorro` first; it may already be most of this. |
| **A runtime language self-test in `tandem autoteste`.** `conta-literais.py` reads shell statically and has printed a false zero twice; a runtime check that renders each command under a non-Portuguese locale and greps the output for known Portuguese stopwords would catch what the static counter cannot see — a *second instrument*, the pattern the counter's own history says is the only thing that ever works. | **MAYBE** — addresses a documented, recurring failure; worth a prototype. |
| **A printing smoke-test.** For shop software printing *is* the program (§2). Pair it with the field-test harness — Wine + CUPS works, Wine + a USB thermal printer almost never, and the honest answer matters more than the hopeful one. | **LATER** — unchanged verdict, now tied to the harness that would make it real. |

## What the six-lens sweep of 2026-08-13 brought back

Six lenses (the counter, the silences, the `.exe` loop, the native formats, the community list, the language system) proposed 46 ideas against the tree; an adversarial judge ruled on 38 of them and rejected 6 outright, leaving the `silencio` lens unjudged. I verified every surviving claim against the working tree myself before ranking, ruled on the eight unjudged ones, and merged two pairs where two lenses arrived at the same finding from different sides. **38 entries survive**, ranked by identity fit (does it explain more and execute the same? does it close a silence?), then leverage, then cost. Three corrections to the judged material, because a synthesis that hides them is worth less than the measurements: the load-bearing half of the `t_verbo_amigavel` item **is already fixed in the uncommitted tree** (which is why it was rejected), the five `echo "Cancelado."` sites are **also already fixed** there — all five now call `$(t_msg cancelado)` — so that entry survives only in its residue, and `tools/prosa-fora-do-catalogo.py` already exists untracked and is wired into `tests/run.sh:1753`, so the runtime language self-test is being built rather than proposed. Two convergences are marked in the table; convergence is evidence, and both converged items are ranked accordingly.

| Idea | What it closes | Verdict |
|---|---|---|
| **Ask whether the "program" is a saved web page in all nine handlers, not only `.deb`.** `t_parece_pagina_web` (common.sh:323) has exactly two callers — `tandem-deb:59` and the CLI's content-sniff fallback at `tandem:85`, which a double-clicked `.jar` never reaches. Put the check in each of the other handlers AFTER that format's magic byte has failed, exactly where `tandem-deb` has it; the `baixou_pagina_web` key is already translated in all seven catalogues. **Two lenses found this independently.** | He clicked a download link that answered with a login wall or a 404 and the browser saved that HTML under the program's name. Measured on a real 404 page under six names: `.jar` and `.apk` tell him the download stopped part way — which sends him back to the same link to fetch the same page, for ever. Only `.deb` says the true thing. | **NEXT** — the detector, the ordering rule and the translated sentence all already exist; eight handlers were simply never wired to them. |
| **Column 4 of `limites.tsv` is Portuguese in all seven tables, English included.** 15 rows carry a fourth column — the way out, the whole payload of the 4.0 correction — and it is byte-identical Portuguese in `limites.tsv`, `.es`, `.fr`, `.zh_CN`, `.hi` and `.ar` (verified: same md5 across all three sampled). `t_limite_do_programa` (common.sh:1515) appends it to the verdict and it reaches the owner through `limite_com_caminho`. Translate it, and extend `tests/run.sh:1448-1475` to checksum column 4 the way it already checksums 1 and 2. | A Sentinel dongle owner outside Brazil is told his case has a way out and then handed the instructions in a language he cannot read; an English-speaking one gets Portuguese from the *default* table. | **NEXT** — a live breach of rule №2 on a flagship message, and CLAUDE.md's claim that "no row is left holding the Portuguese sentence" is wrong as written. |
| **Time the run, not the installs.** `INICIO=$SECONDS` sits at tandem-exe:222, above the memory-shortcut install block and above the retry loop, so `DUROU` at :315 carries every winetricks download into the number `t_saida_suspeita` compares against 3 seconds. Reset the clock immediately before the last `executar`; keep the wall-clock total separately if the log wants it. `tandem-appimage`, `-jar` and `-script` set theirs correctly, so this is one file. | After a 30-minute `dotnet48` the "it opened and closed by itself" warning is arithmetically dead — so on exactly the runs where Tandem did its job, a program that flashed and vanished is reported to him as "it worked". The same wrong number goes to memory as `SEGUNDOS` and travels into recipes. | **NEXT** — the cheapest item here, and it repairs a shipped guard rather than adding surface; the test must simulate an install or the fix is unverifiable. |
| **Slice the log per verb, not from the last one attempted.** `MARCA_WT` is reassigned inside the `for v in $VERBOS` loop (tandem-exe:543) and the failure explanation slices `tail -n +$((MARCA_WT+1))` after the loop (:600), then runs the whole cause table — internet, D-Bus, full disk, clock, checksum, `cabextract` — over that one slice. Capture the slice per verb, at the moment that verb fails, in a temp file the same shape as the existing `PARCIAL`. | When a program needs two components and the first fails, he is told his internet failed — about a component whose real problem was a missing `cabextract` — because a *later* component downloaded normally. He goes to look at his router. | **NEXT** — a scoping bug that silently converts a good rule into a confident wrong sentence, invisible to every existing test because they all install one verb. |
| **A receipt contradicted by the loader is the strongest table evidence there is, and it is discarded.** The `REPETIDOS` branch (tandem-exe:422-429) records `NAO_RESOLVERAM` and exits without calling `t_anota_suspeita`, which appears only at :272 and :577, both install-time; `SUSPEITAS` is re-initialised empty on every process start. Call it there, dedup the note, and fix the sentence, which asserts "I already installed what this program was asking for" while Wine says otherwise. | `traducao-suspeita.tsv` is the work list that already found six mistranslations, and the one moment where Wine's own loader contradicts a permanent receipt never reaches it. He is told a falsehood with confidence. | **NEXT** — keep the receipt (rule №4 is about cost); this records and reports, it does not retry. |
| **Wine says "No implementation for"; the loop answers with an exit code.** `grep -rn 'unimplemented\|No implementation\|c0000135\|c000007b' src/ tests/ po/` returns **zero hits** (verified), and winedeps.sh's `import_dll Library [^ ]*` grep cannot match that line shape, so the case falls to tandem-exe:486 and its bare `fechou_com_erro "$CODIGO"`. Add a reader beside `t_limite_do_log` and a verdict that says no component will fix this and names the Wine version installed. | "Closed with error (code 53)" sends him looking for a defect in a machine that is fine. This is the third verdict class the loop has no branch for — the dependency exists, Wine has not implemented part of it, and there is nothing to install. | **NEXT** — confirm both wordings against Wine 10.0 on the reference machine before writing the message, keep the exit code as fallback, and stop at naming the version: Tandem does not manage Wine. |
| **Ask the `.exe` whether the download finished.** `peinfo.py` parses the section table into `(rva, vsize, raw_size, raw_offset)` (:89) and the full data directory and compares neither against the file's length (verified). Add two one-sided proofs reported as an ERRO token: `max(raw_offset + raw_size) > filesize`, and data directory 4 — the one entry whose address is a file offset rather than an RVA — giving `cert_offset + cert_size > filesize`. | A 400 MB POS installer cut short over a shop connection is the commonest broken thing that reaches this counter, and today it produces `Bad EXE format` after the wait. The same question is already asked of `.jar`, `.AppImage` and `.deb`; `.exe` is the one reader never asked it. | **NEXT** — only "shorter than declared" may become a verdict: NSIS and Inno append their payload after the last section, so a valid installer is legitimately longer. |
| **Say he opened it from inside a zip.** Nothing in `src/` consults where the file lives — `$PROG` is resolved with `readlink -f` at tandem-exe:13 and the path is used only for the `cd` at :284 (verified). Add a `t_origem_do_arquivo` recognising file-roller's `/tmp/.fr-XXXXXX`, a portal document path under `/run/user/N/doc/`, and a gvfs mount, and attach its sentence to `faltam_arquivos_junto` at :433. | Commercial software reaches a Brazilian shop as a zip on WhatsApp, and he double-clicks the `.exe` inside the archive-manager window — which extracts that one file without the `.msi`, the data folder and the DLLs beside it. "Files are missing next to it" is true and does not tell him to save the whole folder first. | **NEXT** — every existing pre-flight reads the file's contents; this reads its situation, which no reader can see. Additive only: the temp-directory naming is a convention, not an interface. |
| **Give each run its own evidence.** `t_log_init` opens `$TANDEM_ESTADO/$1.log` — one file per handler, no PID, no run id (verified at common.sh:43) — while the run lock is keyed to the FILE on purpose, so two programs may run at once. Both processes take `MARCA=$(wc -l < "$LOG")` and slice from it. Write an unforgeable marker line into the log and slice on that instead of a line count. | Installing two things off a USB stick one after the other, program A offers to install B's components, records them as A's `RESOLVERAM`, and on confirmation publishes them to the community list under A's fingerprint — a lesson about a program that was never open. The 1 MB rotation at :46 is the other half: a run started mid-install leaves the first one slicing a file that no longer holds its output. | **NEXT** — the marker variant keeps one file per handler and is the smaller change; the same root cause already deleted lessons once, in the send queue. |
| **Hold the prefix lock around the dependency installs, not only around `wineboot`.** The only `flock` on `prefixo.lock` wraps prefix creation (tandem-exe:114-119, verified); the winetricks loop and the memory shortcut hold no lock at all, and two different programs both land in `$TANDEM_PREFIXO_PADRAO`. Wait rather than refuse, with a sentence, using the existing `flock -w 1200` pattern. | A clobbered winetricks run can still exit 0, and rule №4 then writes a permanent receipt for a component that is not there — the exact damage the delivery proof exists to prevent, arriving by a route it cannot see, since the DLL may be on disk from the *other* process. He pays for it once and is refused for ever. | **NEXT** — the lock's own comment already names the hazard it does not cover; the timeout branch must end in a sentence, not a silent continue. |
| **When he says "no, it did not work", make the answer outrank the exit code.** The "no" branch of `t_confirma_funcionou` writes `CONFIRMADO=nao` and leaves `RESULTADO=abriu` exactly as the exit code set it — and `acao_memoria`'s field map (src/bin/tandem:912-918) prints RESULTADO, ARQUITETURA, RESOLVERAM, NAO_RESOLVERAM, SEGUNDOS, VISTO_EM and LIMITE, with **no line for CONFIRMADO** (verified: `grep CONFIRMADO src/bin/tandem` returns nothing). Spend one sentence at that moment on what Tandem is already holding. | This is the only moment a person tells Tandem the truth about what happened on screen, and `tandem memoria` then shows him "Result: opened" for the one program he has said is broken — and `tandem socorro` embeds that screen verbatim, so the report he sends to whoever is helping asserts the program works. | **DONE** — v4.11. `tandem memoria` leads with his answer, above the exit code's verdict, which stays underneath rather than being overwritten: "it launched and he says it does not work" is a more useful pair of facts than either alone, and it is the shape somebody helping him needs. Pinned by running the command, not the library - the defect lived in the gap between what a function stores and what a screen prints, which only a run can see. |
| **`tandem repair` reports ownership with the instrument this project already proved wrong.** `aplicar()` writes with both `gio mime` and `xdg-mime default` (tandem-repair:123-124) but the before/after report reads back with `xdg-mime query default` only (:80-84, :159-163, verified), and covers 5 of the 8 type families the command claims — `.rpm`, `.snap` and `.flatpakref` are associated and never mentioned. Ask GIO first, fall back to xdg-mime, print a row for every type claimed. | He runs `tandem repair` because a double click opened a text editor. `.flatpakref` is a subclass of `text/plain`, so xdg-mime answers nothing and the report tells him "before: nobody" — contradicting what he watched happen thirty seconds earlier, in the one command he can least afford to disbelieve. | **NEXT** — `gio` needs no new dependency (`libglib2.0-bin` is already a hard Depends and the write side already calls it); parse its wording and fall back rather than trusting either tool alone. |
| **`t_atalhos_do_sistema` looks in two directories; a snap and a flatpak land in neither.** common.sh:3313 hard-codes `/usr/share/applications` and `/usr/local/share/applications` (verified). snapd exports to `/var/lib/snapd/desktop/applications`, flatpak to `/var/lib/flatpak/exports/share/applications` and `~/.local/share/flatpak/exports/share/applications`. Use `XDG_DATA_DIRS`/`XDG_DATA_HOME` where set plus those three as explicit fallbacks, and call the announce from `tandem-flatpak`, which never calls it at all. | `tandem programas` exists because GNOME under Wayland does not re-read the menu, and a program he cannot find again is a program he has not installed. That promise has been silently unkept for three of the four package managers since 3.8 — `tandem-snap`'s "look in the menu for" line has never once appeared. | **NEXT** — reading the variables alone is not enough: both are empty under the suite's `env -i`, and flatpak's export directory is a subpath. |
| **`tandem socorro`'s last step is a ten-second toast.** `acao_socorro` ends `t_ok "$(t_msg soc_pronto "$arq")"` (src/bin/tandem:1234) and `t_ok` returns as soon as `notify-send -t 10000` succeeds (common.sh:376, verified), so on a GUI machine the toast is the only delivery. Give it what `acao_contribuir` already has thirty lines above: the path on the clipboard, a checked `xdg-open` on the folder, and the warning in a window. | This is the "send me the diagnosis" button, and its last step assumes he can find a file in his home directory from a notification that vanished. What gets lost with it is the third paragraph — "it shows names and paths of files that are on this machine" — the sentence that makes the feature defensible. | **NEXT** — the ledger marks the file DONE on the strength of it existing; the step that gets it to a second human was never built, and both shortcuts are already written in the command directly above. |
| **The list is never downloaded unless somebody types the command.** `t_lista_atualiza` has exactly one caller in the whole tree — `src/bin/tandem:1047`, i.e. `tandem lista atualizar` (verified) — so on a machine whose owner never types it `TANDEM_LISTA` never exists and every merge rule 4.4 added is unreachable. Also: `t_lista_consulta` returns 1 for "no list", "no row" and "nobody confirmed it" alike; give them distinct codes and one sentence each. | Receiving costs the shop nothing and is the half of the list that helps him, yet it needs a command he has never heard of — while sending is on by default. A machine that gives and does not take is the wrong way round. | **NEXT** — this reverses "Automatic sync on install — REJECTED", and the new argument is that 4.2 already reversed that stance for the direction that actually carries data; it must mirror the send path exactly (named off-switch, told once, spawned detached). |
| **A lesson taken from the list can never be corroborated back into it.** `INSTALADOS_AGORA` is assigned once, at tandem-exe:585 inside the detector loop (verified); the list/memory shortcut installs at :256-275 and never touches it, so `RESOLVERAM` stays empty and `t_lista_registro` refuses to build a record. Record the shortcut's verbs too, with an explicit origin field separating "I found this myself" from "I applied yours and it worked". | He is shown "in 340 reports this program needed X" as his reason to trust a suggestion — a number only a shop that rediscovered the lesson from scratch can raise, and the shortcut is precisely what stops rediscovery happening. The count freezes at its first few reporters for ever. | **NEXT** — rides the v1→v2 record bump stack-pinning already forces; never sum the two counts, or the list manufactures confidence from its own output. |
| **The resolver never opens the `failed` field, or a row saying nobody got this working.** `t_lista_linha`'s awk touches fields 1, 3, 5, 6 and 7 only, and drops any row where `$3` is `-` — which is exactly the record `api/lista.js` goes out of its way to accept and `monta-lista.py` publishes. Read both and turn each into one sentence before anything is installed, routing the second into `tandem alternativas`. | He is about to spend half an hour on `dotnet48` that sixty other shops already burned on this same installer without it helping — and Tandem has that on disk and says nothing. A file 300 reports say has never worked reads to him exactly like a file nobody has ever seen. | **NEXT** — explains more and executes strictly less, which is the criterion; never block, and never let a rejection count for more than a confirmation. |
| **Say the translation is unreviewed on the path people actually arrive by.** `t_idioma_revisado` has exactly two call sites, both inside `acao_idioma` (src/bin/tandem:1006 and :1023, verified), while `t_idioma_escolhe` step 3 resolves from the system locale with no command from the user. Fire the notice once per (language, version) from `src/bin/tandem`, non-blocking — **not** from `t_primeira_vez`, which `tandem-exe` calls at line 9, between the double click and the program. | CLAUDE.md's own principle is that shipping an unreviewed translation is defensible and shipping it without saying so is not. The mechanism honours it only for the minority who type `tandem idioma`; everyone else gets the unreviewed prose with the honesty stripped out. | **NEXT** — also the only recruitment channel queue item 0b has: the people running those five catalogues are native speakers who do not know there is anything to review. |
| **Catalogue keys against call sites, in both directions, plus placeholder parity.** Nothing in the tree reads what the messages say — `conta-literais.py`'s ALVOS is `src/bin/tandem*` plus `src/lib/*.sh`. Assert that every key named at a call site exists, that every key in `po/en.po` is reachable, and that the `{1}`..`{9}` set is identical per key across all seven catalogues. Measured now: 648 keys, 618 referenced, 31 unreferenced of which 24 are the dynamic `leitor_` family — leaving seven genuinely dead, two of them buttons. **Two lenses found this independently.** | Roughly sixty translated sentences can never appear, and five languages are waiting on scarce human review — do not spend a volunteer's afternoon on a paragraph nothing asks for. A mistyped key prints a bare identifier on a shop counter and no test can see it; a translation that loses `{1}` renders as flawless French with the filename missing. | **NEXT** — it must model the dynamic lookup at common.sh:2857 and postinst's `diz_msg` wrapper, or it reports 31 misses of which 24 are noise, which is the failure that gets a count ignored. |
| **The AppImage menu entry Tandem writes carries a Portuguese `Comment=`.** `t_integra_appimage` writes `Comment=Instalado pelo Tandem a partir de %s` (common.sh:3005) into `~/.local/share/applications` in all seven languages, and it is invisible to `conta-literais.py` twice over — single-quoted, and the function is neither a prose-named body nor in a `tandem-*` file. The same function copies `Categories=` and `StartupWMClass=` and drops every `Name[xx]=`. | This is the one Tandem sentence he reads months later with Tandem not running — the tooltip under the icon, and what the shell's app search matches on. An AppImage that ships a translated name loses it. | **NEXT** — repairs a live breach of rule №2; the privacy half of the original proposal is dropped, since `Exec=` must carry the same path and `X-Tandem-AppImage=` carries it on purpose as the receipt. |
| **Nothing on the machine records what has already been sent.** In `t_envio_envia` the sieve branch and the 4xx branch both park the line under an explicit written rule; the 2xx branch alone destroys it, and `t_envio_pendentes` counts the queue only. Append accepted lines to a sent ledger beside the queue with their month, show the total in `tandem enviar`, clear it from `tandem esquecer`, and keep `acao_socorro` from sweeping it up. | Sending is on by default and defended by notice. A year later, "what has this machine sent about my shop?" has no answer on the machine — and that is the question a shopkeeper, or whoever audits him, actually asks. | **NEXT** — §3 already rejected telemetry on the rule "nothing the owner cannot see and cannot delete", and what has left this machine is currently neither. |
| **Say what the half-hour install is doing while it is doing it.** `t_progresso_abre` opens `zenity --progress --pulsate` with one static `--text` (common.sh:496, verified) and `t_progresso_texto` is called once per verb, so `winetricks -q dotnet48`, `wineboot -u` under `flock -w 1200` and the apt run at tandem-exe:19-21 all show an identical unchanging bar for their whole duration. Run the blocking command in the background and poll from the foreground so the main shell keeps sole ownership of fd 8 — no watcher, nothing to reap. | Behind the counter, "downloading at 40 kB/s", "hung on a dead mirror" and "finished three seconds ago" are the same picture. He has a customer and cannot tell whether to wait or give up, and the only honest signal is on disk where he will never look. | **NEXT** — nothing in the ledger speaks *during* the wait; a sentence only, never an abort, since killing a slow-but-working `dotnet48` is worse than the silence it replaces. |
| **The residue of the no-zenity fallback: a catalogue message used as printf's format string, and a counter rule that is dead where it is needed.** The five `Cancelado.` sites are already fixed in the uncommitted tree, but four sites still do `printf "$(t_msg …)" "$arg"` (tandem-flatpak:67 and :99, tandem:381 and :554, verified), which is what the `{1} {2}` decision exists to prevent; and `literais()` passes `tudo=tudo` to `citadas_com_prosa` and **not** to `printfs_com_prosa` (conta-literais.py:616), which is still scoped by function name in files that define none — miss thirteen fixed in one sibling and left in the other. | The path taken when zenity is unavailable — the fallback that exists so no path ends in silence — is measured by nothing: `sem_ninguem` runs every handler under `env -i` with no terminal, so no test in the suite has ever entered `[ -t 0 ]`. | **NEXT** — fix the format strings and extend the `script -qec` pty harness already at tests/run.sh:3479 to the other handlers under `TANDEM_IDIOMA_FORCADO=en`; a second instrument, not a sixteenth widening. |
| **Read the log on the success path too.** `PARCIAL` is built at tandem-exe:344-345, below an exit-0 branch that ends at :340, so a successful run's log is never opened. Compute it before the branch and run `t_verbos_do_log` / `t_dlls_sem_traducao` over it — first pass log-only, plus one new memory key that does not overload `abriu`. | The half-works case is how Wine actually fails with commercial software: the program starts, a report prints blank, a component is silently disabled. Today that is stored as an unqualified success. | **MAYBE** — one stated consequence is false (`t_lista_registro` refuses to emit when nothing was learned, so the export pollution is narrower than proposed), and the false-positive rate on optional probed DLLs is unmeasured; let the weekly harness say how often a working program still logs an unresolved import before adding a sentence. |
| **Look at the folder beside the `.exe` before saying a file is missing.** `t_limite_do_programa` (common.sh:1515) matches `limites.tsv` only against the import table of the one file double-clicked, and `faltam_arquivos_junto` says outright that files it should have brought with it are missing — which can name a file sitting in the folder. Check presence first, read its architecture with `peinfo.py`, and only then say something. | Sending somebody to re-download a complete program costs an afternoon, and in a shop-software folder the usual case is that the file is right there and Wine refused it. | **MAYBE** — measure the Wine wording for a bitness-mismatched sibling on the reference machine before writing the sentence; the secondary half (globbing siblings against `limites.tsv` column 1, to reach dongle DLLs loaded with `LoadLibrary`) must never refuse to run and must not be written to memory at tandem-exe:224. |
| **A receipt records the verb and nothing else — no evidence, no date, no way to take one back.** The only four references to `.tandem-verbos` in `src/` are two exact-line `grep -qxF` reads (tandem-exe:241, :401) and two `printf '%s\n' >>` writes (:269, :580) — verified. The delivery proof produces three outcomes and all three collapse into the same bare line. Write `verb<TAB>evidence<TAB>date`, read a bare line as legacy, show it in `tandem memoria`, let `tandem esquecer` reach it. | Under rule №4 a receipt is permanent, which makes "I already installed what this program was asking for" Tandem's most expensive sentence — said with identical confidence whether the DLL was proved present or never checked. `tandem esquecer` exists because memory needs an exit door; the receipt is memory with higher stakes and none. | **MAYBE** — the format change and both readers must land together with a test that reads a legacy file, or every verb looks uninstalled and `dotnet48` gets repaid; adjacent to the receipt-contradiction item above, and cheaper done in the same pass. |
| **Say what was learned last time before the slow check, in `tandem-apk`.** `t_memoria_le` has three callers in the whole tree — tandem-exe:205, :220 and tandem-appimage:101 (verified) — while eight handlers write `LIMITE` verdicts nothing reads. `tandem-apk` calls `t_wd_garantir` at line 63, booting Waydroid, before line 67 re-derives the `minSdkVersion` refusal it recorded last time. | He watches Android boot for 20-60 seconds so Tandem can re-derive a "no" from a file that has not changed. | **MAYBE** — print the remembered verdict, do not refuse from it: §3's rule is that memory suggests and never decides, and a re-imaged Waydroid raises the SDK. Drop the rest — the other handlers' checks are instant and no `alternativas.tsv` row matches an `.apk` verdict. |
| **Let the notification's urgency follow the measured wait.** `t_aviso` uses the default timeout, `t_ok` `-t 10000`, and only `t_erro` `-u critical` (common.sh:365-390, verified); `DUROU` is already computed at tandem-exe:315. Where Tandem has just made somebody wait unattended, let the completion notice persist. | Tandem told him the component takes half an hour, so he went back to the counter. The answer — it worked, here is what it is called — was displayed to an empty chair and then deleted. | **MAYBE** — scope it to `acao_preparar` and the post-winetricks stretch where the wait really was unattended, not to a general rule about urgency; a sticky banner on a short wait is a nuisance, and a nuisance damages the error path that depends on the same mechanism. |
| **Rewrite the shortcut winemenubuilder wrote so it goes through `tandem-exe`.** For `.desktop` files `t_atalhos_nossos` already proves belong to a prefix Tandem created (it filters on `$TANDEM_PREFIXO_PADRAO`), replace `Exec=wine start /unix …/X.lnk` with a call to `tandem-exe` on the same `.lnk` — which `executar` already handles at :283. Identical command, plus the lock, the retry loop, the silent-success guard and the memory. | He opens his POS system twice a day for five years and Tandem is in the loop for the first of those launches. The day it auto-updates and asks for a DLL it did not need yesterday, the shortcut fails and the double click does nothing. | **MAYBE** — blocked on designing the restore path first: per-user work cannot run from dpkg, so a purge would leave every rewritten `Exec=` pointing at a binary that is gone — the exact bug this project exists to kill, introduced by the fix. |
| **Show the rival verb sets in the query, not in the install dialog.** `t_lista_linha` keeps a confirmation count for every rival verb set on a file and prints only the champion, so a 55/45 split reads exactly like unanimity. Expose the losers in the log and through a `tandem lista <file>` query. | The number exists so he can decide, and a number that hides a live disagreement is the class of defect the project already fixed once — verbs from 40 machines presented as 7. | **MAYBE** — do not add a clause to the install dialog: he has no lever to choose a verb set, and the decay and downgrade-on-flip work already accepted is where a live disagreement should lower confidence rather than be narrated on the only screen he sees. |
| **Publish what the rebuild left out, and why, inside the file.** `monta-lista.py` collects `recusadas` — malformed rows, unsafe verbs, exclusions — and prints them to stdout, which `lista.yml` puts only in the pull request body; after the merge nothing records that a row was withheld. Write them into `lista/lista.tsv` as `#` comment lines carrying the reason and the identity, never the refused payload. | Moderation with no appeal and no record is silent censorship of reports people sent in good faith. `LIST-FORMAT.md` already makes a leading `#` legal on the reading side. | **MAYBE** — the visibility half is cheap and applies today to the verb-safety refusals; keying `EXCLUIDAS` by (identity, verbs, confidence) waits for a case that needs it, and publishing tells whoever posted a refused row which filter caught it. |
| **The catalogue compiler drops an entry it cannot parse.** `le_po` matches `msgstr ` with a trailing space (tools/po-para-catalogo.py:108, verified), so an entry written `msgstr[0]`/`msgstr[1]` closes with no msgstr and vanishes from every catalogue — English included, so there is no fallback and `t_msg` prints the bare key. `--check` stays green because both sides agree on the absent key. Make it refuse by name instead of dropping. | A naked identifier on a shop counter is rule №2 broken by a legitimate act of translation. Meanwhile `po/en.po` still ships `{1} line(s) sent`, `{1} second(s)`, `{1} program(s)` and `{1} profile(s)`, which is the defect gettext was adopted to fix. | **MAYBE** — `msgid_plural` is 0 in all seven files today (verified) and a translator cannot introduce one, so only the three-line refusal earns a slot; real plural support means a plural-rule evaluator in bash for six cosmetic strings. |
| **One language for the log, and the message key beside every sentence delivered.** `t_msg` logs a key only on a miss (common.sh:293) while `T_MSG_BASE` holds the English unconditionally, so English costs nothing; and 118 `t_diz` literals across the tree are Portuguese (51 in common.sh, 18 in tandem-exe, 9 in tandem-deb, 8 in tandem-appimage). Log the key and the English base beside every message actually *delivered* — `t_erro`, `t_aviso`, `t_ok`, `t_pergunta` — not on every lookup. | The person helping is not the person reading. A log from an Arabic or Hindi shop is Arabic prose under Portuguese markers, so the helper can neither read it, grep it, nor match it against anything in this repository. | **MAYBE** — overlaps the shareable-transcript work already decided this session, and any new prefix must land outside the slice `t_palavras_do_programa` shows the owner or it reintroduces the 4.5 defect by name. |
| **Find out how wide a no-wrap dialog actually gets, then decide.** `t_erro` and `t_pergunta` both pass `--no-wrap` (common.sh:404, 424), so GTK does not reflow and the hand-wrapping in the source sets the window width — which no translator can know. Measured per language: en longest 198 columns / 42 lines over 78; fr 229 / 70; es 207 / 51; hi 180 / 46. The widest key in five of seven languages is `bitola`, shown through `t_erro` at tandem-exe:412. | A message can be perfectly translated, pass every test, and open a window wider than a shop screen — worst in the five languages nobody has reviewed, on the flagship bitness dead end. | **MAYBE** — render the widest French message under Xvfb at 1366x768 and look before building anything; a ratchet on an inferred failure is how a guard ends up blocking a good release, which is worse than the drift. |
| **Keep the "(needed by …)" half of the `import_dll` line.** `t_verbos_do_log`, `t_pares_do_log` and `t_dlls_sem_traducao` all run the identical `grep -o 'import_dll Library [^ ]*'`, which truncates the match before the needer; the fixtures at tests/run.sh:135-142 already carry the real line shape. Add a separate lookup that greps for the needer of one named DLL, called only when composing the orphan message, with the Windows path reduced to a basename. | It is the difference between knowing WHAT is missing and knowing WHO asked for it — "this program cannot start" versus "one part of this program could not load" — and it names a file he can see in a folder. | **LATER** — do NOT widen `PARES`: the delivery proof reads it with `awk -F'\t' '$2 == alvo'` and a fourth field getting the ordering wrong empties that proof with no symptom. Blocked behind the folder-scan work, which changes the same message with a harder fact. |
| **An exit door for the eight formats that are not Wine.** `acao_uninstall` returns early unless `$TANDEM_PREFIXO_PADRAO/system.reg` exists, so a `.deb`, `.snap`, flatpak or Waydroid app Tandem itself installed has no way back. Every manager answers before the password — `apt-get remove -s` runs unprivileged and prints the whole cascade — so the shape is `tandem-deb`'s: simulate, show what would go, then ask. | Every install path in this project ends in something on the machine with no way back he can reach, and it is asymmetric in the dangerous direction: he is already shown what a `.deb` install would remove, before installing. | **LATER** — blocked on a prerequisite that does not exist: only `tandem-apk` records the identifier it installed under, the other three write `RESULTADO=instalado` and nothing else. Record the identifiers first, and get field evidence on the install paths before adding removal ones. |
| **Check `lista.tsv` against the intake in CI, the way `build.py --check` checks the package.** A `--check` mode on `tools/monta-lista.py` that re-derives the file from the public `acumulado` URL and fails when the committed file carries a row the intake does not support. Needs no key, no secret and no decision — it verifies one published file against a second public source. | The only gate today is a human reading a pull request body, and a verb name is exactly what a human cannot eyeball. A row from a hand edit or a bad merge is indistinguishable from one four hundred shops reported, and it installs into somebody's prefix with a permanent receipt. | **LATER** — blocked until there is a first published row: today it passes because the file is empty, and a guard green for lack of input is the vacuous-guard failure this repository has written up at length. It must skip rather than fail on a 503. |
| **Review credit per entry, not one header bit for 648.** `escreve_catalogo` reads `X-Reviewed-By-Speaker` once for the whole file (tools/po-para-catalogo.py:128) and `t_idioma_revisado` greps for the result, so a speaker who reads 200 sentences cannot record it and the next reviewer starts from zero. Move the mark to the entry, compute the header from the count, and have `tandem idioma` say how many of the 648 a speaker has checked. | The flag will also start lying the moment a review finishes: 4.4 added 34 keys, so a catalogue marked `yes` silently becomes partly unreviewed on the next release and nothing notices. | **LATER** — nobody has reviewed a single entry in any of the five catalogues; building divisible-credit machinery and changing the one authoring path this project calls "exactly ONE path", on a bet about a Poedit round trip, is building for a demand nobody has shown. |


## Drivers: the 2026-08-14 investigation, and why the answer was not "no"

The owner pushed back on a flat "Wine runs in user space, a .sys cannot load,
impossible" - *"o tandem deveria ser essa ponte, essa é a filosofia dele"* - and
he was right to. Six lenses were run against the installed Wine and the current
vendor documentation, each verified adversarially. **"Driver" turned out to be
eight different things, and five of them have a route.** Three of the findings
were shipped defects and are fixed in 4.9; the rest are below with verdicts.

# Drivers: what Tandem can bridge, what it cannot, and where the line is

Synthesised from six lenses and an adversarial verifier. Everything below marked "measured here" I re-ran myself in this session on the installed wine-9.0 (Ubuntu noble, the Zorin 18 base); everything marked otherwise says whose measurement it is and how strong it is.

---

## 1. The decomposition

The owner is right: "driver" is not one thing. It is eight, and only three of them are genuinely closed.

| What the shopkeeper calls a "driver" | Can Tandem bridge it? |
|---|---|
| **A licence daemon** (Sentinel/HASP, CodeMeter) — a Linux service owns the USB key, the Windows DLL asks it over loopback TCP 1947/22350 | **Yes, by diagnosis.** The route exists and the vendor documents it. Tandem can say which of three things is missing before the wait, and must not install the vendor package. |
| **A bridge-chip shim** (FTDI, CH340/CH341, CP210x, PL2303, CDC-ACM) — the "driver CD" for a pinpad, scale or scanner | **Nothing to bridge.** Linux drove it before the CD was opened; Wine maps it to a COM port with nothing installed. Tandem's job is to say so and give the number. |
| **A print driver** | **Already bridged.** CUPS *is* the driver; Wine forwards the queue list. Windows itself stopped accepting new third-party print drivers in 2026, so the file he was told to install is wrong on both operating systems. |
| **A PC/SC smart-card stack** (A3 tokens, CCID readers) | **Yes, and it is the cleanest one.** `winscard.so` is hard-linked to `libpcsclite.so.1` (measured here) and udev already grants the reader to the logged-in user. Two absent apt packages are the entire failure. |
| **A HID device** (Rockey keys, some pads and scales) | **Bridged in Wine, blocked by a file mode.** `winebus.so` links libudev and enumerates `/dev/hidraw*`; `hid.dll` stubs only `HidD_`/`HidP_` oddities. Tandem can *name* the permission; it should not change it. |
| **Raw USB** (WinUSB, libusb-win32) | **No — and not for the usual reason.** Wine's `winusb.dll` has 22 exports and 21 are `__wine_stub_` (measured here; the only implemented one is `WinUsb_Free`). The missing one is `WinUsb_Initialize`, the first call. No permission on the machine changes that. |
| **A real kernel driver that touches hardware** (winio, inpout32, dlportio, giveio, PCI cards, anti-cheat) | **No, and it is worse than "no".** It *loads* into `winedevice.exe` and finds nothing underneath. |
| **A driver *installer*, as a file** | **A fifth thing nobody had named.** Not a driver at all: `DiInstallDriverW` and `UpdateDriverForPlugAndPlayDevicesW` are *soft* stubs (measured here — they are absent from newdev.dll's `__wine_stub_` list), so the installer runs, copies files, reports success and binds nothing. |

Five of eight have a route. That is the answer to the push-back.

---

## 2. What Tandem could actually do, ranked by value to a shopkeeper

### 1. Fix the serial-port gap — Tandem currently prints a COM number Wine never created

**Reproduced here, twice.** Wine's `detect_devices()` counts from 0 per family and `break`s at the first missing index. Measured: with `/dev/ttyUSB1` present and `/dev/ttyUSB0` absent, a fresh `wineboot -u` produced **only** `com1 -> /dev/ttyS0`. I restored the node and the identical command produced `com1`, `com2 -> /dev/ttyUSB0`, `com3 -> /dev/ttyUSB1`. Then, with the hole back in place, `t_portas_seriais` printed `/dev/ttyS0` and `/dev/ttyUSB1` — which `t_texto_portas` numbers COM1 and COM2. **Tandem tells the owner his pinpad is on COM2 when Wine has created no COM2 at all.** A hole is routine: unplug and replug an adapter, a two-port converter, a hub that re-enumerates.

Wrong in the invisible direction, inside the one command written to end exactly this confusion.

- **Files:** `src/lib/common.sh` (`t_portas_seriais`, `t_texto_portas`), `tests/run.sh` against a synthetic layout — `TANDEM_SYS` already exists for this.
- **Root:** no. **Feasibility:** works today. The rescue is already built and already rule-1 safe (`acao_portas fixar` checks `t_prefixo_protegido` at `src/bin/tandem:963`, and `tandem portas fixar COM2 /dev/ttyUSB1` both rescues the invisible device and lands it inside COM1–COM4, where old POS software insists on looking).
- **Bonus, measured here:** `[Software\\Wow6432Node\\Wine\\Ports]` in `system.reg` carries `#link`. The "`wine reg` writes the view it is not read from" hazard in CLAUDE.md **does not bite this key**. Write that down so nobody "fixes" a working command.

### 2. Read the `.inf`, not the `.exe` — the driver CD that is a no-op

The single commonest "driver" a Brazilian counter meets, and the flagship pre-flight is blind to it: `limites.tsv` matches the imports of a *program*, and an NSIS/Inno wrapper's import table says nothing about the `.sys` inside.

An `.inf` is plain text (usually UTF-16LE) carrying `Class=`/`ClassGuid=` and hardware IDs of the shape `USB\VID_xxxx&PID_yyyy`. Two branches out of one parser:

- **Class `Ports`/`HIDClass`/`Printer`/`SmartCardReader`/`USBDevice`** → "This installs a Windows driver for a Gertec PPC930. Linux already recognised that device by itself and it is on COM3. You do not need this file." Gate on **three positives** (VID/PID in sysfs **and** a kernel driver bound **and** a tty node) — anything less says "I could not confirm", the same discipline `t_prefixo_arquitetura` already follows.
- **Class `System`/`Net`/`SCSIAdapter`/`Volume`** → the dead end, said before the download instead of after it.

Ship both branches together, or the permissive one arrives without its brake.

- **Files:** new `src/lib/infinfo.py` in the `peinfo.py` shape, new `src/bin/tandem-inf` (or a pre-flight branch of `tandem-exe`), `src/mime/tandem.xml`, `src/lib/limites.tsv` + six translations, `po/en.po`.
- **Root:** no. **Feasibility:** the parse works today; **the sysfs half is untested** — this container has no `/sys/bus/usb` at all, so it must be exercised on the reference machine before it ships.
- **Free win nobody proposed:** name the device from udev's own shipped hwdb (`/usr/lib/udev/hwdb.d/20-usb-vendor-model.hwdb` maps `usb:v0529p0001` to "HASP copy protection dongle"). A database already on his machine, no table of ours to maintain.
- **Dropped:** the brltty/CH340 theft. Falsified — noble's brltty filters `1a86/7523` to the Baum display behind its own hub and has the generic FTDI/CP210x rules commented out. That was a 22.04 bug.

### 3. Printing — three defects, and one of them is a finished feature that has never fired

For shop software, printing *is* the program, and there is no printing code anywhere in the tree.

- **The dead glob.** `common.sh:2618` looks for `/dev/usblp[0-9]*`. The kernel's usblp driver registers `lp%d` through a `usblp_devnode` that prepends `usb/` — the node is `/dev/usb/lp0`. **The repository already contradicts itself:** `alternativas.tsv` says `/dev/usb/lp0` correctly in all seven languages (verified here). So `portas_impressora_usb` — a complete, translated, seven-language message naming the exact fix command — has never fired on any machine on Earth. And if it did fire it would be wrong twice, because mountmgr maps only `/dev/lp%u` to LPT (measured here: the file contains exactly `/dev/ttyS%u`, `/dev/ttyUSB%u`, `/dev/ttyACM%u`, `/dev/lp%u` and nothing else) — a USB receipt printer is never an LPT port.
- **Nothing ever asks what printers the program will see.** `lpstat -r` / `lpstat -p` is the authority and needs no prefix. The prefix's `Print\Printers` key is a *second* opinion at best: it is written lazily when winspool first loads, so absence means "no program has printed here yet", not "no printers".
- **libcups is `dlopen`'d and only Recommended.** Measured here: `objdump -p winspool.so` shows `NEEDED ntdll.so, libc.so.6` only — libcups appears as a string, loaded at runtime — and `apt-cache show libwine` puts `libcups2t64` under Recommends while libusb, libpcsclite, libgphoto2 and libpcap are hard Depends. A machine without it has zero printers and says nothing. Ask the loader per architecture (`ldconfig -p | grep libcups.so.2`), the same instrument the project already blessed for libfuse and for the same renaming reason. Narrower than the lens claimed: both arches are present here, so this is a check that costs nothing and occasionally saves everything, not a common cause.
- **The permission is a group, not a udev rule.** Measured here: `50-udev-default.rules:89` gives `GROUP="lp"` to any usb_device with interface class `0701??`. For a USB printer the fix is `usermod -aG lp` — one command, the exact shape of the existing `dialout` sentence, which `t_texto_portas` does not currently check even while printing LPT and usblp lines.

- **Files:** `common.sh` (`t_texto_portas`, a doctor line), `src/bin/tandem` (`acao_doctor`), `po/en.po`.
- **Root:** no for all the reading; only installing a missing library or joining a group. **Feasibility:** works today.
- **Hold back:** creating a CUPS queue, and the sentence "your queue must be raw or the paper comes out blank". Nothing tells Tandem the printer is thermal, and no thermal printer has ever been in front of this code. `docs/IDEAS.md` §2 parks that as LATER twice; it stays LATER, tied to the field harness.

### 4. Generalise the daemon probe into a bridge table

Wine's `x86_64-unix` directory *is* the driver-bridge table, and each entry is a runtime dlopen of one Linux library. `t_chave_estado` already asks the right question — is the Linux side here — for exactly two licence families, and only after the program has failed.

Turn it into a table (family → services, port, vendor product name, message) and add the families that are missing: **pcscd** and **CUPS**. Both are the `apt-get install -s` pattern the project already trusts: ask the thing that already knows, before the password.

- **The PC/SC row is the best-conditioned item in the whole set.** Measured here: `winscard.so` is genuinely `NEEDED`-linked to `libpcsclite.so.1`; `70-uaccess.rules:51` is an unconditional `ENV{ID_SMARTCARD_READER}=="?*", TAG+="uaccess"`, so a real CCID reader is handed to the logged-in user with zero udev work; and `pcscd`, `libccid` and `pcsc-tools` all answer `Installed: (none)` on this stock image. That absence is usually the whole answer, and `limites.tsv` row 39 currently hands the owner a four-step procedure with no way to find out which step he is stuck on.
- **The ceiling must travel with it, unchanged:** the reader appearing does not mean the certificate will sign. That sentence is the most valuable one in the file and must not be softened by a green tick above it.
- **Files:** `common.sh` (`t_chave_estado`, `t_texto_chave`), `limites.tsv` row 39 + six translations. **Root:** no for the diagnosis. **Feasibility:** works today.

### 5. Move the Sentinel sentence from post-mortem to pre-flight — and say which Wine is underneath

`grep -rn t_texto_chave src/` returns only `tandem-exe:531-532`, both inside the branch that runs *after* the program has failed — while `LIMITE` is computed at `tandem-exe:200`, before anything runs. The sentence is available before the wait and is not used there.

Split today's single verdict into three measured cases: the key is not plugged in (VID `0529` absent from `/sys/bus/usb/*/idVendor`), the runtime was never installed (no `/usr/sbin/aksusbd*`, no `/etc/udev/rules.d/80-hasp.rules`), or it is installed and stopped (one `pkexec`, root asked once and named).

**Two defects found on the way, and the second is new:**

- `t_servico_vivo` is `pgrep -x "$1"`, an exact match, while Thales' own installed-files list names the binaries `aksusbd_x86_64` and `hasplmd_x86_64`. Only the systemd half rescues a `.deb` install; a script install answers "not running" about a daemon that is running. Match both `name` and `name_x86_64`.
- **Thales names Wine 10.0; this machine offers 9.0 and nothing else.** Measured here: `apt-cache policy wine` → Installed `9.0~repack-4build3`, Candidate the same, and `tandem preparar` runs `apt-get install -y wine`. So `limites.tsv` tells a Sentinel owner the manufacturer publishes that it works on Wine 10.0, on a machine Tandem itself just gave 9.0, and nothing says so. Tandem already knows the version and already has the posture for this (`t_falta_no_wine` names the Wine version and stops).

- **Root:** no for diagnosis; one `systemctl start` if it is installed and stopped. **Feasibility:** works today. **Never fetch the RTE** — Thales' distribution page addresses the software *vendor*, and the download portal is a human-navigated ServiceNow KB. Name the file, open the page, say the supplier hands it over.
- **CodeMeter stays where it is.** Its loopback joint is undocumented at the one place that matters, and no Wine success report exists in 2025–2026. Keep "nobody has reported getting it to work on Wine yet" word for word in all seven tables. One cheap defect to fix regardless: `t_chave_estado` uses `servicos="CodeMeter CodeMeterLin"` while the Linux unit is reportedly lowercase `codemeter.service` — reported by the lens, **not measured here**, so check it against a real install before changing it.

### 6. Unmute the three device channels — a prerequisite, and it costs nothing

`tandem-exe:78` is `export WINEDEBUG=fixme-all,fixme+ntoskrnl,fixme+hal`. That tuning was made for the kernel-driver verdict and never revisited when USB, HID and smartcards went into `limites.tsv`. It silences the one line Thales says you will see (`hidclass.sys`: "Unsupported ioctl %#lx…", a FIXME on channel `hid`), plus `wineusb`'s "Unhandled ioctl" and "Failed to open device: %s".

**Measured here at steady state:** the current setting produced 0 bytes and `…,fixme+hid,fixme+wineusb,fixme+plugplay` also produced 0 bytes. Those channels are silent unless a device is involved. Without them, items 5 and 8 have no evidence to read.

- **Files:** `src/bin/tandem-exe:78`, `common.sh` (`t_limite_do_log`), `po/en.po`. **Root:** no. **Guard:** keep the new lines outside the slice `t_palavras_do_programa` shows the owner, or the 4.5 defect returns by a new door.

### 7. Recognise the driver installer that reports success and binds nothing

Measured here: `newdev.dll`'s stub list is `DiInstallDevice, DiRollbackDriver, DiUninstallDevice, DiShowUpdateDevice, InstallWindowsUpdateDriver` and the `pDi*` family — `DiInstallDriverA/W` and `UpdateDriverForPlugAndPlayDevicesA/W` are **not** in it. They are hand-written *soft* stubs: they log a FIXME and return. `difxapi.dll` ships too. `setupapi` really does export `SetupCopyOEMInfW`, so files genuinely get copied.

That distinction is the whole point. A *hard* stub raises "Call from … to unimplemented function", which `t_falta_no_wine` already catches. A soft stub is invisible to every instrument this project owns — the installer looks like it worked, and the owner reboots wondering why nothing changed.

- **Files:** `limites.tsv` new class + six translations, `po/en.po`. `t_pe_dlls` already reads `ATRASADAS=`, so a delay-loaded `newdev` is caught too.
- **Match on `newdev`/`difxapi` plus a `.sys` or `.inf` inside; never on `setupapi` alone; never refuse to run.** **Root:** no. **Feasibility:** works today.

### 8. Split the `driver` class, and sharpen the two dead ends

`limites.tsv` has ten `driver` rows and all ten are no-way-out, because `t_limite_sem_saida` (`common.sh:1525`) returns 0 for `dongle|driver|anticheat|usb`. So the bare `*.sys` catch-all answers identically for a `.sys` that pokes hardware (hopeless) and a `.sys` that is a licence or IOCTL shim doing no hardware access (loads fine in `winedevice.exe`, often works). That is the same over-strict error the 4.0 correction fixed for dongles, still standing one class over — and it is the row where items 2 and 3 would have rescued somebody.

The escape hatch already runs twice in this same file (7 `dongle` rows have no way out while 10 `dongle-*` rows do; 2 `usb` rows have none while `usb-talvez` does), so this is the third application of a pattern that works.

**One correction that makes it a code change, not a table edit:** column 4 is appended *inside* `limite_sem_saida_txt`, whose opening line is "This program did not open, and Wine has no way to fix it" (verified in `src/lib/idiomas/en.txt:198`). A `driver` row with a way out would deny a way out and then supply one. It needs a new class routed through `limite_com_caminho`, i.e. `t_limite_sem_saida` gets edited.

- **Files:** `common.sh:1525`, `limites.tsv` + six translations, `po/en.po` (`limite_log_hardware`, `limite_log_driver`). **Root:** no.

### 9. Name the permission; do not change it

Read-only, and it corrects a shipped message. Measured here: the only hidraw uaccess rule in the whole tree is `70-uaccess.rules:89`, gated on `ID_AV_PRODUCTION_CONTROLLER`, so a generic HID dongle stays root-only; and `50-udev-default.rules:72` leaves usb_device nodes at `MODE="0664"` root:root.

So `limites.tsv` row 22's guess ("what may be missing is read permission on the device") is right about HID, and can be stated rather than guessed — and corrected, because feature reports are writes, so it is read-**write** that is missing. Row 38 (`hid.dll`) currently gives *claimed* devices advice that cannot work: read `/sys/bus/usb/devices/*/…/driver` and split the sentence — "Linux is already using this device for something else" (point at the ports report) versus "the device is there and this program cannot open it".

**Not proposed: writing a udev rule.** Two of the three verifiers rejected it outright and the third held it. Reasons, in order: for WinUSB there is nothing on the far side to reach (item 3 of §3 below); a `TAG+="uaccess"` rule numbered above 73 is a silent no-op because `73-seat-late.rules` is what runs the builtin, so the button would ask for a password, write a file, change nothing and report success — rule 4, exactly; and for a pinpad or scale it is a permanent system-wide device grant made on behalf of one program, on hardware nobody here has, with `wineusb.so` importing no `libusb_claim_interface` and no `libusb_detach_kernel_driver` (so a device Linux already bound stays contested anyway). This project's only precedent is a polkit rule shipped in the `.deb`, reviewed once, scoped to one systemd unit.

---

## 3. What is genuinely impossible

Three things, and ending the search fast is the product here.

**Raw USB through WinUSB or libusb-win32.** Measured here on 9.0 and confirmed by the lenses against Wine master in August 2026: 21 of 22 exports are `__wine_stub_`, and the only implemented one is `WinUsb_Free`, which frees a handle you can never obtain. Wine 11 does not fix it.
> *To the shopkeeper:* "The part of Wine your program needs to open this device has not been written yet — there is nothing you can install here that changes it." Name the Wine version, because a version is a fact that can change. This one is already caught loudly after the fact: `WinUsb_Initialize` is a hard stub, so it produces "Call from … to unimplemented function", which `t_falta_no_wine` already reads. Only the static row is softer than the truth — "Wine only does part of that" invites exactly the investigation that ends here.

**A `.sys` that touches hardware.** Wine's `load_driver()` takes almost any `.sys` into `winedevice.exe`, an ordinary user process, so the driver *loads*. Measured here: `MmMapIoSpace` is present as a soft stub returning NULL, `IoConnectInterrupt` is `__wine_stub_`, and in `hal.dll` the `READ_PORT_USHORT`/`WRITE_PORT_USHORT` and all six BUFFER variants are hard stubs — so some calls abort loudly and some return zeros silently.
> *To the shopkeeper:* "This program loaded its driver and then found nothing behind it. If it is behaving strangely rather than crashing, that is why — anything it shows you now may be wrong." That sentence currently lives only in a source comment; it needs to reach `limite_log_hardware`. It is the silent-wrong failure this project exists to catch, and today it reads the same as the loud one.

**Kernel anti-cheat, and HASP4/Hardlock.** Anti-cheat runs in the kernel and refuses VMs by design, so nothing on the machine changes the answer. HASP4/Hardlock is the vendor's own position, not ours: Thales' page (last updated 11 May 2026) says those keys "are not expected to work".
> *To the shopkeeper:* for the old purple dongle — "the company that made this key stopped supporting it outside Windows, and a virtual machine may not rescue it either." That last clause is missing today and it matters, because it is the difference between an honest dead end and a trap with a receipt on it.

---

## 4. The line Tandem must not cross

**The virtual machine: name it, never manage it.** Settled in 4.0 and nothing here reopens it. A real Windows in QEMU/KVM genuinely reaches both dead ends above — the kernel is real, so a `.sys` loads for real and a dongle is handed over with `-device usb-host,vendorid=…,productid=…`. It also costs a Windows Pro or Enterprise licence (Home cannot host RemoteApp at all), KVM in the BIOS, ~4 GB RAM and ~32 GB of disk that stop being the shop's. WinBoat's own USB passthrough is experimental, Docker-only with Podman explicitly unsupported, with open bugs on dongle recognition. `t_vm_possivel` already checks whether the machine could carry one and `tandem-exe:515` already excludes anti-cheat on purpose. The **only** change worth making is one clause: the paragraph never mentions the device, which is the sole reason a dongle owner would consider a VM at all. A message edit, not a route.

**Do not write into `/etc`.** No udev rules. See item 9.

**Do not install a vendor's runtime.** Sentinel's RTE, CodeMeter's, a printer vendor's `.so` — third-party root packages, licensing components, and the vendor's to support. Name it, check whether it is already there, stop. This is rule 1 applied off the Wine prefix.

**Do not give fiscal or legal advice.** One lens proposed a SAT/NFC-e sentence for `limites.tsv` and got the tense wrong: São Paulo's CF-e-SAT ended on 31 December 2025, eight months ago, so it would have shipped *expired* tax advice into a shop in seven languages, as a flagship message. Keep the *shape* and delete every acronym, date and state: "the equipment this program is asking for belongs to a generation that has been retired; what replaced it prints on an ordinary thermal printer and needs no driver at all; the person who changes that is whoever supplies your sales system." That is decision, translation and diagnosis. The dated version is none of the three, and it is the owner's call, not the agent's.

**Do not claim a chain nobody has walked.** The "Elgin ships a Linux virtual COM driver, so the printer becomes a COM port Wine maps" story did not survive checking — the virtual-COM driver in that bundle is a *Windows* driver, and what Elgin publishes for Linux is a `.so`, which is unreachable from a Windows `.exe`. That is the answer `limites.tsv` already gives for CliSiTef, PayGo and ACBrLib: your supplier has to use it. New vendor rows are welcome; they get the CodeMeter hedge until somebody reports otherwise.

---

## 5. What this changes about the project's own description of itself

**`limites.tsv` is no longer a table of impossibility. It is a routing table with an impossible tail, and it should say so.**

That is not a rebrand — it is what the file already does and what the code has not caught up with. Fifteen of forty-two rows carry a way out; the fourth column *is* the product of the 4.0 correction. What is wrong is the classification underneath it. `t_limite_sem_saida` still declares four whole classes hopeless, and after this work that list is wrong in **both** directions at once:

- **`driver` is too strict.** Ten rows, all no-way-out, covering a `.sys` that pokes hardware and a `.sys` that only checks a licence with the same sentence. Split it.
- **`usb` is too soft.** "Wine only does part of that, and devices Linux is already using end up contested" reads as a permission problem with a fix behind it, and it is not: the door is missing from Wine. It should stay no-way-out with a *harder* sentence, not gain a fourth column.
- **`dongle` is right and stays right**, on the vendor's own authority.

So the posture question — "does the table describe routes it could partly automate?" — has a two-part answer.

**Yes, and that is the defect.** Four rows hand the owner a procedure and never look to see which step he is stuck on: `winscard.dll` (install three packages, run `pcsc-scan`), `hid.dll` (it is almost always read permission), `rockey*.dll` (same guess), and the Sentinel family (a technician installs it, once). Every one of those is checkable by reading, unprivileged, before the download. The project already decided this shape is right when it built `apt-get install -s` into `tandem-deb` — nobody types a password to be told no — and then did not apply it to the one table whose whole job is telling people what to try. A row that describes a route without checking it is prose, and constraint 5 says prose is not a bridge.

**And no, the descriptions themselves should not become executions.** Everything in §2 explains more and executes the same: it reads sysfs, `ldconfig`, `lpstat`, `ss`, an `.inf`, the Wine log and the prefix's own registry. The only new writes are a registry value in a prefix Tandem created (already guarded) and, at most, a group membership the owner is asked for by name. Nothing installs a vendor package, nothing touches `/etc`, nothing manages a VM.

One line to add to the project's own description, because it is the general answer to the owner's question and it was discovered in 4.0 and never generalised: **a "driver" that has a Linux counterpart is not a driver problem, it is a routing problem** — and routing is decision, translation and diagnosis, which is exactly the three things this project says it is. The Sentinel row works because the key never crosses into Windows. The pinpad works because the chip never needed a driver. The printer works because CUPS is the driver. The `.sys` fails because there is no counterpart, and no amount of layering invents one.

---

*Nothing was changed in the tree. Before any of this lands, `debian/control`, `debian/changelog` and `TANDEM_VERSAO` all still say 4.5 and 4.5's entry is published history — 4.6 has to be opened first.*

## The queue

1. **Fill the community list.** The mechanism exists, it now has both ends —
   `api/lista.js` receives and `.github/workflows/lista.yml` rebuilds — and it is
   still empty. Inventing a line would be exactly the mistake the `confidence`
   field exists to prevent. It only fills with reports from people.
   **And it will fill slowly for a structural reason, not a missing feature:**
   eight of the nine formats install native software, where what Tandem learns
   is derivable from the file itself. The knowledge that is genuinely not
   derivable — which winetricks verbs make an unknown Windows program run — only
   comes from the `.exe` path. The list is about that path, and treating the
   other eight as a gap to close was a misreading.
2. Field-test what has not yet run on a real owner's machine: `preparar`,
   `desinstalar`, `dados`, `socorro`, and a double-click on a real `.xapk`,
   `.AppImage` and `.jar`.
3. **A real shop program** — see below.
4. Nothing more to add: all nine formats are done. What is missing for them is
   field evidence, not code.

## The question still without an answer

**No real commercial shop program has ever run on this.** Since 3.7 the loop runs
weekly against real freely-redistributable Windows software — PuTTY, Notepad++,
7-Zip, WinMerge — through the real `tandem-exe`, with `xdotool` confirming a
window appeared and a screenshot kept. That closed the "no binary somebody else
compiled has ever touched it" gap, and it immediately corrected something the
README had wrong: every real installer tested is 32-bit, even the one that
installs 64-bit software.

What it does not close is commercial software on a counter: a Brazilian POS
system, an accounting package, a fiscal printer driver. The earlier synthetic
`.exe` test already paid for itself — it found four defects in one afternoon, two
of them erasing entire messages in silence — and the real-software harness is a
step closer, but neither is a shop.

Even so, it proves the mechanism works, not that the product is useful. That gap
is still the project's largest uncertainty, and it is why
[CONTRIBUTING.md](../CONTRIBUTING.md) opens by saying a report about a real
program is worth more than a new feature.
