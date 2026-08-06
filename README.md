# Tandem

**Double-click a file. It runs.**

Tandem makes `.exe`, `.msi`, `.apk` and `.xapk` files behave like native
applications on Linux — no terminal, no manual setup, no reading forum threads
about which `winetricks` verb you need.

```
.exe .msi   →  Wine     — missing runtimes detected and installed automatically
.apk .xapk  →  Android  — compatibility checked before installing, in plain language
```

[Português](LEIAME.md)

---

## Why

Running a Windows program or an Android app on Linux is possible today, but the
path there is hostile to anyone who is not a developer: install Wine, create a
prefix, discover which runtime is missing by reading `err:module:import_dll` in a
terminal, translate that to a `winetricks` verb, install it, try again. For
Android, start a container service, then a session, then wait for a boot that has
no visible progress, then find out your `.apk` was ARM-only after it fails.

Tandem does that work for you and reports the outcome in a sentence a shop owner
can act on.

## What it actually does

### Windows programs

- **Detects missing runtimes from Wine's own output.** When a program fails,
  Wine prints `err:module:import_dll Library MSVCP140.dll not found`. Tandem
  parses those lines, maps each DLL to the `winetricks` package that provides it,
  installs, and retries — up to three rounds. This is the loop an experienced
  user performs by hand.
- **Distinguishes "you're missing a runtime" from "the program is incomplete."**
  DLLs with no known mapping are usually files the program itself should have
  shipped. Tandem says so instead of installing something random.
- **Routes by file type.** `.msi` goes through `msiexec /i`, `.lnk` through
  `wine start /unix`. Associating `.msi` with plain `wine` — a common mistake —
  fails every time.
- **Checks architecture before running.** A 32-bit program on a system without
  `wine32` gets an actionable message, not a silent exit.
- **Never fails silently.** Every failure path ends in a dialog. The original
  sin of "double-click and nothing happens" is treated as a bug.

### Android apps

- **Inspects the package before installing.** A bundled binary-XML parser
  (no Android SDK required) reads the package name, `minSdkVersion` and the
  native ABIs, and compares them to the running Android. You are told
  *"this app needs Android 15, yours is 13"* rather than watching an install fail.
- **Handles split packages.** `.xapk`, `.apks` and `.apkm` are extracted and
  installed through ADB with `install-multiple`, including OBB data files. Most
  large apps are distributed this way and a plain installer cannot handle them.
- **Reads the real result.** `waydroid app install` exits 0 even when the install
  fails. Tandem parses the output and translates `NO_MATCHING_ABIS`,
  `INSTALL_FAILED_OLDER_SDK` and friends into plain language.
- **Waits for the right signal.** `Session: RUNNING` means the session manager
  started, not that Android booted. Tandem waits for `sys.boot_completed`.

### Safety

Wine prefixes that Tandem did not create are **read-only to the automation**.
If a program lives inside an existing prefix, Tandem runs it *in that prefix* and
refuses to install anything into it — it reports what is missing and stops.

This exists because the project was born on a machine that also runs a
point-of-sale system in its own prefix. Automation that "helpfully" installs a
runtime into a working production environment is worse than no automation.

Add prefixes explicitly with:

```bash
tandem protect ~/.wine-something
```

## Install

Download the `.deb` from [Releases](../../releases) and double-click it, or:

```bash
sudo apt install ./tandem_2.4_all.deb
```

Then check your environment:

```bash
tandem doctor
```

Tandem does not install Wine or Waydroid — it connects what you already have.
`tandem doctor` tells you what is missing and how to get it.

## Requirements

| For | You need |
|---|---|
| Windows programs | `wine`, and `winetricks` for automatic dependencies |
| 32-bit programs | `wine32` (`sudo dpkg --add-architecture i386`) |
| Android apps | [`waydroid`](https://docs.waydro.id/), initialized |
| Split packages (`.xapk`) | `adb` |
| ARM-only apps on x86 | [libhoudini / libndk](https://github.com/casualsnek/waydroid_script) |

Tested on Zorin OS 18.1 (Ubuntu 24.04 base). Should work on any Debian-based
distribution with a freedesktop-compliant desktop.

## Usage

Mostly none — you double-click files. When you want the command line:

```bash
tandem                    # panel
tandem install file.xapk  # install or run anything
tandem android            # open the Android screen
tandem doctor             # environment diagnosis
tandem repair             # re-apply file associations
tandem backup             # save the Windows environment
tandem restore            # restore it
tandem protect <path>     # mark a Wine prefix as untouchable
tandem logs               # show the latest log
```

## Build

No Debian host or `dpkg-deb` required — the packager writes the `ar` archive
directly:

```bash
python3 build.py --check
```

## Tests

The suite runs without Wine, without Waydroid and without installing the
package: the shell libraries are sourced straight from `src/lib`, and the
Android packages are synthesised — including a real binary `AndroidManifest.xml`,
so the manifest parser is exercised on the same code path a real APK takes.

```bash
bash tests/run.sh
```

Optional tools (`shellcheck`, `dpkg-deb`, `desktop-file-validate`) are used when
present and skipped when absent, so the suite passes on a bare machine.

## What will never work

Being honest about this up front saves everyone an afternoon:

- **USB devices inside Android.** Waydroid has no USB passthrough. Thermal
  printers, card readers, barcode scanners and scales do not exist inside the
  container. No automation changes this.
- **Banking and payment apps.** Play Integrity detects the container. There is
  no reliable workaround.
- **Windows software with kernel drivers.** Anti-cheat, some POS payment
  middleware, hardware dongles. Wine runs in user space.
- **Hardware-locked licensing.** Wine reports empty or synthetic BIOS and disk
  serials. Software that fingerprints the machine may refuse to activate — or
  crash on the activation screen.

## Licence

MIT. See [LICENSE](LICENSE).
