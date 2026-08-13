# The community list format

The idea: a Tandem that gets a program working publishes what it learned, and
every other Tandem receives that lesson on its own — the same way an ad blocker
receives filter lists.

The engineering choice that makes it viable: **the list is a static text file**,
fetched over HTTPS, not an API. That is why EasyList has survived twenty years on
a volunteer's budget while a bespoke service would not: a static file has no
server to fall over, no accounts, no database, no per-user cost, and anyone can
mirror it.

## The two halves, and why they are asymmetric

| | How it works | Why |
|---|---|---|
| **Down** (reading the list) | Automatic, once the owner asks for it | It is a `GET` of a public file. Nothing from the machine leaves. |
| **Up** (contributing) | Tandem **builds** the record; **the owner sends it** | A shop's machine does not talk to any server because an automation decided to. |

That asymmetry is not laziness — it is the project's rule №1 applied to the
network. Automatic contribution would mean a production machine sending data out
with nobody asking, and "only harmless data" is a promise somebody breaks the
first time a file path slips in by accident.

## The record

One line per known program, TAB-separated fields. Single-line, readable,
greppable and mergeable — the same reasons filter lists are plain text.

```
identity  arch  verbs           failed       confidence  machines  seen        note
```

| Field | What it is | Example |
|---|---|---|
| `identity` | `sha256` of size + first and last MiB of the file | `9f2a...c1` |
| `arch` | `32`, `64` or `arm64`, read from the PE header | `64` |
| `verbs` | winetricks verbs that fixed it, comma-separated | `vcrun2022,dotnet48` |
| `failed` | verbs that were installed and did **not** fix it | `vcrun6` |
| `confidence` | `confirmado`, `so-abriu` or `reprovado` | `confirmado` |
| `machines` | how many machines reported the same lesson | `340` |
| `seen` | date of the most recent report, `YYYY-MM` | `2026-08` |
| `note` | one sentence, or empty | `needs the 32-bit build` |

An empty field is `-`. A line starting with `#` is a comment. The first line
declares the format version:

```
# TANDEM-LISTA 1
```

The `confidence` values stay in Portuguese because they are the same tokens the
program writes into its own memory files and recipes; translating them at the
boundary would mean two vocabularies for one concept, and a mismatch there fails
silently.

### The identity is of the FILE, not the user

`t_memoria_id` already existed and serves exactly this: `sha256` of
`size + first MiB + last MiB`. It identifies "the installer for POS system X,
version Y" — **the same** on any machine in the world holding that same file.
It does not carry the filename, the folder, the user, or the machine. Two
different shops running the same system produce the same identity and the
`machines` count goes up; neither learns about the other, and nobody outside can
go from the identity back to the file without already having the file.

### What NEVER goes into a contribution

This is the specification, not a recommendation — `tandem contribuir` refuses to
generate the record if any of it shows up:

- file path, filename, folder name
- username, machine name, IP or MAC address
- log contents
- anything from inside the Wine prefix
- a date with a day (year and month only — a day identifies)

What does go in are facts about the **binary** — which anyone holding the same
file can determine themselves — and **which winetricks verbs fixed it**, which
is public knowledge about public software.

## Why confidence travels with the lesson

Without the `confidence` field, "the process exited 0" and "a person looked at
the screen and said it was right" would arrive at the other end carrying equal
weight. Since Wine's characteristic failure with commercial software is
**opening and being subtly wrong**, a list without that field would spread wrong
lessons as efficiently as right ones — and faster, because errors take no effort
to produce.

## Several rows about the same file

This is the normal shape of a merged list, not a corner case: two shops report
different verb sets for the same installer, or one reports it working and
another reports it broken. So the file format has to say how those resolve, and
until 4.4 it did not — the reader took the first confirmed row it happened to
read and stopped, which meant **whoever got into the file earliest owned that
program for ever**. A later row from four hundred machines was dead text.

The rules, in order:

1. **Rows carrying the same verbs are added up.** Merging reports is the whole
   job of the `machines` field, so two rows saying `vcrun2022` with 200 each are
   400, not 200. A row whose `machines` is `-` has not been merged and counts as
   the one machine it is.
2. **A verb set at least as many machines `reprovado` as `confirmado` is
   dropped.** Rejections used to be read by nobody at all, so two confirmations
   could beat three hundred rejections. Spreading an error takes no more effort
   than spreading a fix.
3. **Of what survives, the most-confirmed verb set wins.** Ties break on the
   most recent `seen`, then on the fewest verbs — less to install for the same
   claimed result — then alphabetically, so the answer never depends on the
   order of the rows in the file.
4. **The machine count shown to the owner is the count of the row that won.**
   It used to be read from the first row matching the identity, ignoring
   confidence entirely, so a rejected row sitting above a confirmed one supplied
   the number: verbs from a 40-machine confirmation, presented as "7 machines".
   The number exists so the owner can decide, and a number describing a
   different lesson is worse than no number.

Whoever builds the merge job on the publishing side does not have to follow
this — the reader is defensive on purpose, because the file arrives from
somewhere else. But a merge that does follow it produces a smaller file that
answers identically.

## What the list does NOT do

- **It installs nothing on its own.** It becomes a suggestion; Tandem still
  asks. A recipe is not an order, and a third party's list even less so.
- **It cannot carry a command.** Every verb is validated against the shape of a
  winetricks verb name before being used. Input from outside cannot carry
  execution.
- **It uploads nothing on its own.** See the table above.
