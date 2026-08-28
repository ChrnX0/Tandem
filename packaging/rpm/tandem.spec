# Tandem RPM spec — for the rpm families (Fedora via COPR, openSUSE via OBS).
#
# Tandem ships primarily as a .deb; this builds the SAME bytes for the rpm
# families from the distribution-agnostic generic tarball that build.py emits
# from its one layout, so an rpm install and a .deb install can never drift.
# The %%files list is generated from the MANIFEST that drove the install, so it
# cannot rot as files are added or removed.

Name:           tandem
Version:        4.80
Release:        1%{?dist}
Summary:        Run Windows, Android and Linux packages by double-clicking

License:        MIT
URL:            https://github.com/ChrnX0/Tandem
Source0:        %{url}/releases/download/v%{version}/tandem_%{version}_generic.tar.gz
BuildArch:      noarch

Requires:       bash
Requires:       python3
Requires:       zenity
Requires:       desktop-file-utils
Requires:       xdg-utils
Requires:       shared-mime-info
Requires:       hicolor-icon-theme
%if 0%{?suse_version}
Requires:       glib2-tools
%else
Requires:       glib2
%endif

# The optional engines: each format works once its engine is present, and Tandem
# says in plain language what to install when one is missing — so these are weak
# dependencies, never hard ones. A name a given distro does not carry is simply
# ignored, which is exactly what a weak dependency is for.
Recommends:     wine
Recommends:     winetricks
Recommends:     fuse
Recommends:     squashfs-tools
Recommends:     flatpak
Recommends:     gtk4
Recommends:     libadwaita
Recommends:     python3-gobject
Recommends:     libnotify
Recommends:     curl
%if 0%{?suse_version}
Recommends:     java-openjdk-headless
%else
Recommends:     java-latest-openjdk-headless
%endif

%description
Tandem makes nine Linux install formats open with a double click — .exe, .msi,
.apk, .xapk, .AppImage, .jar, .deb, .rpm, .flatpakref, .snap and shell
installers. It is a thin layer of decision, translation and diagnosis on top of
wine, winetricks, waydroid, the AppImage runtime, java, the system package
manager and flatpak: it runs the program, detects what is missing, installs it
when it safely can, and — above all — never lets an error end in silence. Every
message is shown in the user's own language.

%prep
%autosetup -n %{name}-%{version}

%build
# Nothing to compile: Tandem is shell and Python.

%install
# The generic tarball's own installer stages every file with its correct mode
# when DESTDIR is set, and does no post-install work in that mode — exactly what
# a package build needs.
DESTDIR=%{buildroot} bash install.sh

# Generate the packaged-files list from the very MANIFEST that drove the
# install (plus explicit ownership of Tandem's own directories), so %%files can
# never disagree with what actually landed.
{
    find %{buildroot}/usr/lib/%{name} \
         %{buildroot}/usr/share/%{name} \
         %{buildroot}/usr/share/doc/%{name} -type d 2>/dev/null \
        | sed "s#^%{buildroot}#%%dir #"
    awk -F'\t' 'NF { print "/" $2 }' MANIFEST
} | sort -u > %{_builddir}/%{name}-files.list

%files -f %{_builddir}/%{name}-files.list

%post
# Refresh the shared caches (each optional: a machine missing one still gets a
# working Tandem) and show the one-time install notice, READ from the catalogue
# in the machine's language — never sourced, so a translation file that will one
# day arrive from a stranger can never execute as root.
update-desktop-database %{_datadir}/applications &>/dev/null || :
update-mime-database %{_datadir}/mime &>/dev/null || :
gtk-update-icon-cache -f %{_datadir}/icons/hicolor &>/dev/null || :
lang="${LANG%%.*}"; lang="${lang%%@*}"
for f in "%{_prefix}/lib/%{name}/idiomas/$lang.txt" \
         "%{_prefix}/lib/%{name}/idiomas/${lang%%_*}.txt" \
         "%{_prefix}/lib/%{name}/idiomas/en.txt"; do
    [ -r "$f" ] || continue
    printf '\n'
    for key in instalado_resumo envio_aviso_ligado; do
        T_KEY="@$key" awk 'BEGIN{k=ENVIRON["T_KEY"]} $0==k{i=1;next} substr($0,1,1)=="@"{i=0} i{print}' "$f"
        printf '\n'
    done
    break
done

%postun
update-desktop-database %{_datadir}/applications &>/dev/null || :
update-mime-database %{_datadir}/mime &>/dev/null || :
gtk-update-icon-cache -f %{_datadir}/icons/hicolor &>/dev/null || :

%changelog
* Fri Aug 28 2026 Paulo Eduardo <noreply@users.noreply.github.com> - 4.80-1
- Package the generic tarball for the rpm families (Fedora, openSUSE).
