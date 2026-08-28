# Tandem for the RPM families (Fedora, openSUSE)

`tandem.spec` builds Tandem for the distributions that use `.rpm`. It does **not**
carry its own copy of the program: it installs from the distribution-agnostic
`tandem_<version>_generic.tar.gz` that `build.py` publishes with every release,
running that bundle's own `install.sh` with `DESTDIR` set. So an RPM install and
a `.deb` install place exactly the same files — the two can never drift — and the
`%files` list is generated from the tarball's `MANIFEST`, so it cannot rot as
files are added or removed.

`build.py --check` verifies that the spec's `Version:` matches `debian/control`,
so a release bump that forgets the spec turns CI red instead of shipping a stale
package.

This spec has been built and installed end to end on a real Fedora, where
`tandem doctor` correctly reads `package family: dnf`.

## Fedora — publish on COPR

[COPR](https://copr.fedorainfracloud.org/) is Fedora's community build service.
It builds the spec and hosts a repository users enable with one command.

1. Sign in to <https://copr.fedorainfracloud.org/> with a Fedora account.
2. **New Project** → name it `tandem`, tick the Fedora releases (and, if you
   like, the EPEL ones) you want to build for.
3. **Packages → Add → SCM**:
   - Clone URL: `https://github.com/ChrnX0/Tandem`
   - Commit-ish: `main`
   - Subdirectory: `packaging/rpm`
   - Spec file: `tandem.spec`
   - Build source: **rpkg** (or **make_srpm**; the plain spec works with rpkg).
4. **Build** the package. COPR downloads the release tarball named in `Source0`
   and builds. When it turns green, the repository is live.

Users then install with:

```bash
sudo dnf copr enable <your-copr-user>/tandem
sudo dnf install tandem
```

To rebuild for a new release, bump the version and press **Rebuild** (or enable
COPR's automatic rebuilds on a new Git tag).

## openSUSE — publish on OBS

The [Open Build Service](https://build.opensuse.org/) builds the same spec for
openSUSE (and, if you want, for many other distributions at once).

1. Sign in to <https://build.opensuse.org/> with an openSUSE account.
2. Create a package under your home project (e.g. `home:<user>/tandem`).
3. Upload `tandem.spec` and the release tarball
   `tandem_<version>_generic.tar.gz` (or add the release URL as a remote
   source). The spec's `%if 0%{?suse_version}` branches already pick the
   openSUSE package names (`glib2-tools`, `java-openjdk-headless`).
4. Enable the openSUSE repositories you want to build for; OBS builds on every
   change.

Users then install by adding your OBS repository and running
`sudo zypper install tandem`.

## One manual step is yours

As with the AUR, the only step that cannot be automated from this repository is
the account itself — a Fedora account for COPR, an openSUSE account for OBS.
Everything the build needs is here and versioned.
