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
| **Clone a prefix with `.NET` already in it** instead of running `dotnet48` from scratch (30 min, high failure rate). | **LATER** — needs extreme care never to read from a protected prefix in use, plus somewhere to fetch the ready-made prefix from |
| Bundle Wine inside the `.deb` | **REJECTED** — 400 MB, licensing, and it would make us responsible for updating Wine. |

## 8. Android

| Idea | Verdict |
|---|---|
| **Read the binary `AndroidManifest.xml` without the SDK** and compare `minSdkVersion` and ABIs against the running Android, *before* installing. | **DONE** — `apkinfo.py`, pure Python |
| **Parse the output of `waydroid app install`**, which exits 0 even when it fails. | **DONE** |
| **Wait for `sys.boot_completed`**, not `Session: RUNNING`. With GAPPS that is another 20–60 s. | **DONE** |
| **Register `.xapk`/`.apks`/`.apkm` as their own MIME type** — without it the system sees a generic ZIP and the double-click never reaches Tandem. | **DONE** |
| **Say plainly that USB does not exist inside Waydroid.** Thermal printer, card reader, scale, barcode scanner: none of it passes through. For a shop, that sentence saves an afternoon. | **DONE** — it is in the README |
| USB passthrough to Waydroid | **REJECTED** — it does not exist. Promising it would be a lie. |

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
| `.flatpakref` / `.flatpakrepo` | handled only if a store is installed | **DEPOIS** |
| `.deb` double-clicked | a store opens, or nothing; a missing dependency reads as a broken file | **DEPOIS** — the diagnosis Tandem is best at, applied to the format the distribution itself uses |
| `.rpm` on a Debian system | nothing useful | **DEPOIS** — refuse with the reason, and name the equivalent |
| `.msix` / `.appx` | nothing | **REJECTED for now** — Wine support is not there; promising it would be a lie |
| kernel work, own package manager, own desktop | — | **REJECTED** — this is where projects of this shape die |

### What the two done ones taught, for whoever does the next

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
fine on 21. The next format will have its own version of that clause. Find it
before shipping.

## The queue

1. **Fill the community list.** The mechanism exists and is empty, and inventing
   a line would be exactly the mistake the `confidence` field exists to prevent.
   It only fills with reports from people.
2. Field-test what has not yet run on a real owner's machine: `preparar`,
   `desinstalar`, `dados`, `socorro`, and a double-click on a real `.xapk`,
   `.AppImage` and `.jar`.
3. **A real shop program** — see below.
4. `.deb` and `.rpm`, then `.flatpakref`. See the table above for why that order.

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
