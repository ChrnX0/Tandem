#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""The modern face of Tandem: GTK4 + libadwaita dialogs, in a One UI-inspired
visual language.

This is the OPTIONAL modern backend for the handful of windows a shop owner
sees - the error, the yes/no question, the long-text viewer and the health
panel. The shell (common.sh) tries this first and falls back to zenity when it
is not here, so nothing depends on it: an old machine without libadwaita, or a
headless run, loses the new look and keeps every word. That fallback is the
whole reason this can exist without breaking the project's first rule - no error
ends in silence.

The look is an ORIGINAL theme inspired by the One UI design language (rounded
"squircle" cards, generous space, bottom-weighted actions, a vivid accent,
depth) - none of Samsung's own fonts or icons are used or shipped. It adapts to
the system light/dark preference.

Contract, so the shell can read exit codes the same way it reads zenity's:

    gui.py --check                 -> 0 if GTK4 + libadwaita import here, else 1
    gui.py error <text> [ok]       -> shows the error; 0 when shown, 2 when it
                                      could not draw (caller falls back)
    gui.py question <text> <yes> <no>
                                   -> 0 = the yes button, 1 = the no button,
                                      2 = could not draw (caller falls back)
    gui.py text <title>            -> long text on STDIN in a scrollable window;
                                      0 when shown, 2 when it could not draw
    gui.py panel <title> <summary> [action_file] [fix_label]
                                   -> the health triage as coloured cards; one
                                      "sev<TAB>text<TAB>action" finding per line
                                      on STDIN (sev 1=red, 2=amber; action is a
                                      one-click-fix token or empty), empty STDIN =
                                      one green all-clear card. When action_file
                                      is given, a finding with an action token
                                      gets a fix_label button that WRITES that
                                      token to action_file and closes; the shell
                                      reads the file and runs the remedy. 0 shown,
                                      2 cannot draw
    gui.py menu <title> <subtitle> [action_file] [version]
                                   -> the Tools menu as tappable One UI rows; one
                                      "token<TAB>label<TAB>icon<TAB>group" tool per
                                      line on STDIN, grouped by <group> in order.
                                      A click WRITES the token to action_file and
                                      closes; a plain close leaves it untouched so
                                      the shell reads "" and stops. <version> (e.g.
                                      "Tandem 4.78") is shown beside the title so
                                      the owner can read it without a terminal.
                                      0 shown, 2 cannot draw

Every drawing path is wrapped so a failure NEVER reaches the owner as a Python
traceback - it becomes exit 2, and the shell shows the zenity window instead.
The text is Unicode from Python's own strings, so the locale/charmap trap that
erases zenity's accented windows cannot happen here.
"""
import os
import sys

CANT_DRAW = 2   # the shell reads this as "fall back to zenity"


def _write_action(path, token):
    """Record a clicked one-click-fix token where the shell will read it.

    This is the whole contract between a panel Fix button and t_painel: the
    choice comes back through a file, never stdout, so gui.py's stdout stays
    free. Extracted to module level (no GTK import) so a test can prove the
    write without a display. A failure to write is swallowed - a fix that could
    not be recorded is simply not run, never a traceback on the owner's screen.
    """
    if not path:
        return False
    try:
        with open(path, "w") as f:
            f.write(token)
        return True
    except Exception:
        return False


# Each system's own mark, drawn fresh (no trademark art copied): the Windows
# four-pane window, the Android robot head, and the Linux Tux penguin. Kept as
# small SVG strings and rendered through the same librsvg loader the desktop uses
# for icons, so a program's row shows what it is at a glance. The owner rejected
# emoji here ("o android parece um emoji... o linux deveria ser um pinguim").
_GLYPHS = {
    "windows": (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="#3f6ef0">'
        '<rect x="3.5" y="3.5" width="7.4" height="7.4" rx="1.4"/>'
        '<rect x="13.1" y="3.5" width="7.4" height="7.4" rx="1.4"/>'
        '<rect x="3.5" y="13.1" width="7.4" height="7.4" rx="1.4"/>'
        '<rect x="13.1" y="13.1" width="7.4" height="7.4" rx="1.4"/></g></svg>'),
    "android": (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        '<g stroke="#1ec46a" stroke-width="1.6" stroke-linecap="round">'
        '<line x1="8" y1="6.8" x2="6.4" y2="4.3"/><line x1="16" y1="6.8" x2="17.6" y2="4.3"/></g>'
        '<path fill="#1ec46a" d="M5 13.6a7 7 0 0 1 14 0z"/>'
        '<circle cx="9.7" cy="10.7" r="1" fill="#fff"/><circle cx="14.3" cy="10.7" r="1" fill="#fff"/></svg>'),
    "linux": (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        '<path fill="#2f2f33" stroke="#7c8698" stroke-width=".4" d="M12 2.4c2.5 0 4.2 1.9 4.2 4.7 0 1-.2 1.6-.2 2.5 0 1.9 2.3 3.6 2.9 6 .4 1.8-.3 2.8-1.5 2.9l.6 1.8c.1.4-.2.8-.6.8h-3c-.3 0-.5-.1-.6-.4-.3.3-.8.4-1.7.4s-1.4-.1-1.7-.4c-.1.3-.3.4-.6.4h-3c-.4 0-.7-.4-.6-.8l.6-1.8c-1.2-.1-1.9-1.1-1.5-2.9.6-2.4 2.9-4.1 2.9-6 0-.9-.2-1.5-.2-2.5C7.8 4.3 9.5 2.4 12 2.4z"/>'
        '<path fill="#fff" d="M12 9.2c1.8 0 3 1.9 3 4.6 0 2.4-1 4.4-3 4.4s-3-2-3-4.4c0-2.7 1.2-4.6 3-4.6z"/>'
        '<circle cx="10.6" cy="6.6" r=".95" fill="#fff"/><circle cx="13.4" cy="6.6" r=".95" fill="#fff"/>'
        '<circle cx="10.7" cy="6.7" r=".42" fill="#1a1a1a"/><circle cx="13.3" cy="6.7" r=".42" fill="#1a1a1a"/>'
        '<path fill="#f7a838" d="M10.9 7.7h2.2l-1.1 1.5z"/>'
        '<path fill="#f7a838" d="M9.8 20.4l1.6-1.1.3 1.6zM14.2 20.4l-1.6-1.1-.3 1.6z"/></svg>'),
}


# The chip labels for the systems are their names - the same in every language,
# so they live here (a descriptive category label), not in the message
# catalogues, and the shell passes only the labels that actually translate.
_PLATFORM_LABEL = {"windows": "Windows", "android": "Android", "linux": "Linux"}


def _platform_image(kind, size=20):
    """A Gtk.Image of a system's mark at `size` px, or an empty image if the
    kind is unknown or the loader is unavailable - never a traceback."""
    from gi.repository import Gtk
    try:
        from gi.repository import GdkPixbuf, Gio, GLib
        svg = _GLYPHS.get(kind)
        if not svg:
            return Gtk.Image()
        from gi.repository import Gdk
        stream = Gio.MemoryInputStream.new_from_bytes(GLib.Bytes(svg.encode()))
        pb = GdkPixbuf.Pixbuf.new_from_stream_at_scale(stream, size, size, True)
        img = Gtk.Image.new_from_paintable(Gdk.Texture.new_for_pixbuf(pb))
        img.set_pixel_size(size)
        return img
    except Exception:
        return Gtk.Image()


def _update_dot(atualizavel, tem_update):
    """The state of the small dot on a program's icon, decided from the two
    fields the library engine provides. Pure. Four states:
      gray    - Tandem does not manage this program's updates (a Windows or
                Android program, an AppImage, a distro package)
      amber   - an update is waiting (tem_update = sim)
      green   - checked and up to date (tem_update = nao)
      unknown - updatable, but no successful check has proved its state yet
                (first launch, or offline): never a false green.
    Returns (css state, message key)."""
    if atualizavel != "sim":
        return "gray", "dot_gerido"
    if tem_update == "sim":
        return "amber", "dot_atualizar"
    if tem_update == "nao":
        return "green", "dot_atual"
    return "unknown", "dot_checando"


def _icon_with_dot(tipo, atualizavel, tem_update, msgs, size=30):
    """The platform mark with the status dot pinned to its lower-right corner,
    a tooltip on the dot naming what it means. Falls back to the bare mark if
    anything goes wrong - never a traceback."""
    from gi.repository import Gtk
    img = _platform_image(tipo, size)
    try:
        state, key = _update_dot(atualizavel, tem_update)
        ov = Gtk.Overlay()
        ov.set_child(img)
        dot = Gtk.Box()
        dot.add_css_class("oneui-dot")
        dot.add_css_class("oneui-dot-%s" % state)
        dot.set_halign(Gtk.Align.END)
        dot.set_valign(Gtk.Align.END)
        tip = msgs.get(key)
        if tip:
            dot.set_tooltip_text(tip)
        ov.add_overlay(dot)
        return ov
    except Exception:
        return img


def _display_fonte(fonte, msgs):
    """How a program's source reads on screen. Every source is a proper noun
    that stays as it is in any language - Wine, AppImage, Flatpak, snap,
    Waydroid - except "sistema", which is an on-disk token (a plain word, not a
    name) and gets a translated label when shown; the record on disk keeps
    "sistema". Pure."""
    if fonte == "sistema":
        return msgs.get("fonte_sistema", "System")
    return fonte


def _dot_priority(atualizavel, tem_update):
    """Sort rank for the 'by update' view: what needs attention first. Amber (an
    update waits) before the not-checked ring, before green (current), before the
    programs Tandem does not manage. Pure."""
    state, _ = _update_dot(atualizavel, tem_update)
    return {"amber": 0, "unknown": 1, "green": 2, "gray": 3}.get(state, 4)


def _order_items(records, mode):
    """Order the library for display, and for the 'system' view group it with a
    header before each system. Pure - returns a flat list of ('group', tipo) and
    ('app', record) items, so the caller just walks it. Three modes, like a file
    manager: by name (A->Z), by system (grouped), by update (what needs acting on
    first). Anything unexpected falls back to by-name.
    A record is (tipo, nome, fonte, lancador, atualizavel, tem_update)."""
    def by_name(rs):
        return sorted(rs, key=lambda r: r[1].lower())
    if mode == "sistema":
        out = []
        for tp in ("windows", "android", "linux"):
            grp = by_name([r for r in records if r[0] == tp])
            if grp:
                out.append(("group", tp))
                out.extend(("app", r) for r in grp)
        rest = by_name([r for r in records
                        if r[0] not in ("windows", "android", "linux")])
        out.extend(("app", r) for r in rest)
        return out
    if mode == "update":
        ordered = sorted(records, key=lambda r: (_dot_priority(r[4], r[5]),
                                                 r[1].lower()))
        return [("app", r) for r in ordered]
    return [("app", r) for r in by_name(records)]


def _imports_ok():
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Gtk, Adw  # noqa: F401
    return True


def _has_display():
    return bool(os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))


# The One UI-inspired palette, one for light and one for dark. Built by token
# replacement (not %/format) so the literal % in the gradients needs no
# escaping. The accent gradient is the same in both - it glows on dark and pops
# on light. Kept here as data so a colour change is one line, never a hunt.
_LIGHT = {
    "@BG@": "linear-gradient(180deg,#eef1f6 0%,#e6eaf2 100%)",
    "@TITLE@": "#10131a", "@SUB@": "#5b6472",
    "@CARD@": "#ffffff", "@CTEXT@": "#1a1f29",
    "@BE0@": "rgba(233,72,72,.14)", "@BE1@": "#E94848",
    "@BW0@": "rgba(233,160,40,.16)", "@BW1@": "#E0850F",
    "@BO0@": "rgba(38,190,120,.16)", "@BO1@": "#16A65B",
    "@GHOSTBG@": "rgba(20,30,60,.06)", "@GHOSTFG@": "#2a3040",
    "@SHADOW@": "0 10px 30px rgba(20,30,60,.10)",
    "@BT0@": "rgba(47,107,255,.12)", "@BT1@": "#2f6bff",
    "@ROWHOV@": "rgba(47,107,255,.06)",
}
_DARK = {
    "@BG@": "linear-gradient(180deg,#0d0f14 0%,#141824 100%)",
    "@TITLE@": "#f2f5fa", "@SUB@": "#98a2b4",
    "@CARD@": "#1b2130", "@CTEXT@": "#e7ecf5",
    "@BE0@": "rgba(233,72,72,.22)", "@BE1@": "#ff6b6b",
    "@BW0@": "rgba(233,160,40,.22)", "@BW1@": "#ffc04d",
    "@BO0@": "rgba(38,190,120,.22)", "@BO1@": "#4fd894",
    "@GHOSTBG@": "rgba(255,255,255,.08)", "@GHOSTFG@": "#d6dcea",
    "@SHADOW@": "0 12px 34px rgba(0,0,0,.48)",
    "@BT0@": "rgba(75,140,255,.20)", "@BT1@": "#6f9bff",
    "@ROWHOV@": "rgba(120,160,255,.10)",
}

_CSS_TEMPLATE = """
window, .oneui-root { background: @BG@; }
headerbar { background: transparent; box-shadow: none; }
.oneui-title { font-size: 26px; font-weight: 800; letter-spacing: -0.5px; color: @TITLE@; }
.oneui-sub { font-size: 15px; color: @SUB@; }
.oneui-card { background: @CARD@; border-radius: 28px; box-shadow: @SHADOW@; }
.oneui-card-pad { padding: 18px 20px; }
.oneui-card-msg { padding: 26px; }
.oneui-cardtext { font-size: 15px; color: @CTEXT@; }
.oneui-msg { font-size: 16px; color: @CTEXT@; }
.oneui-badge { min-width: 48px; min-height: 48px; border-radius: 18px; }
.oneui-badge-error { background: @BE0@; color: @BE1@; }
.oneui-badge-warn  { background: @BW0@; color: @BW1@; }
.oneui-badge-ok    { background: @BO0@; color: @BO1@; }
.oneui-pill { border-radius: 22px; padding: 12px 26px; font-weight: 700; font-size: 15px; }
.oneui-primary { background: linear-gradient(135deg,#2f6bff 0%,#12b6c8 100%); color: #ffffff; box-shadow: 0 8px 18px rgba(47,107,255,.35); }
.oneui-primary:hover { filter: brightness(1.05); }
.oneui-updateall { background: linear-gradient(135deg,#f5a623 0%,#e0850f 100%); color: #ffffff; box-shadow: 0 8px 18px rgba(224,133,15,.35); }
.oneui-updateall:hover { filter: brightness(1.05); }
.oneui-ghost { background: @GHOSTBG@; color: @GHOSTFG@; }
.oneui-mono textview, .oneui-mono text { font-family: monospace; font-size: 13px; color: @CTEXT@; }
.oneui-progress > trough { min-height: 14px; border-radius: 999px; background: @GHOSTBG@; }
.oneui-progress > trough > progress { min-height: 14px; border-radius: 999px; background: linear-gradient(90deg,#2f6bff 0%,#12b6c8 100%); }
.oneui-search { border-radius: 999px; min-height: 40px; }
.oneui-chip { border-radius: 999px; padding: 7px 18px; font-weight: 600; background: @GHOSTBG@; color: @GHOSTFG@; box-shadow: none; }
.oneui-chip:checked { background: linear-gradient(135deg,#2f6bff 0%,#12b6c8 100%); color: #ffffff; }
.oneui-toolslink { background: none; box-shadow: none; color: @SUB@; font-weight: 600; padding: 6px 14px; border-radius: 999px; }
.oneui-toolslink:hover { background: @GHOSTBG@; }
.oneui-dot { min-width: 12px; min-height: 12px; border-radius: 999px; border: 2px solid @CARD@; margin: 0 1px 1px 0; }
.oneui-dot-amber { background: @BW1@; }
.oneui-dot-green { background: @BO1@; }
.oneui-dot-gray  { background: @SUB@; }
.oneui-dot-unknown { background: @CARD@; border-color: @SUB@; }
.oneui-updtag { font-size: 13px; font-weight: 700; color: @BW1@; }
.oneui-grouphdr { font-size: 13px; font-weight: 800; color: @SUB@; margin: 10px 6px 2px 6px; letter-spacing: 0.4px; }
.oneui-ordena { border-radius: 999px; min-height: 36px; }
.oneui-ordena > button { border-radius: 999px; background: @GHOSTBG@; color: @GHOSTFG@; box-shadow: none; padding: 4px 12px; }
.oneui-badge-tool { background: @BT0@; color: @BT1@; }
.oneui-menucard { background: @CARD@; border-radius: 22px; box-shadow: @SHADOW@; padding: 14px 18px; }
.oneui-menucard:hover { background: @ROWHOV@; }
.oneui-chev { color: @SUB@; }
"""


def _css_for(dark):
    pal = _DARK if dark else _LIGHT
    css = _CSS_TEMPLATE
    for k, v in pal.items():
        css = css.replace(k, v)
    return css.encode()


def _is_dark():
    """Whether the system asks for dark. Defaults to light if it cannot tell,
    so a wrong guess never makes light text on a light window."""
    try:
        from gi.repository import Adw
        return bool(Adw.StyleManager.get_default().get_dark())
    except Exception:
        return False


def _build(app, title, resizable=False):
    from gi.repository import Gtk, Adw, Gdk
    prov = Gtk.CssProvider()
    prov.load_from_data(_css_for(_is_dark()))
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = Adw.ApplicationWindow(application=app)
    win.set_title(title)
    win.set_resizable(resizable)
    win.add_css_class("oneui-root")
    return win


def _flat_header():
    from gi.repository import Gtk, Adw
    hb = Adw.HeaderBar(show_end_title_buttons=True)
    hb.add_css_class("flat")
    hb.set_title_widget(Gtk.Label(label=""))
    return hb


def _badge(kind, size=26):
    """A rounded squircle status badge. kind: 'error'/'warn'/'ok' (or a
    severity '1'/'2'/other)."""
    from gi.repository import Gtk
    name = {"error": "dialog-error-symbolic", "1": "dialog-error-symbolic",
            "warn": "dialog-warning-symbolic", "2": "dialog-warning-symbolic",
            "question": "dialog-question-symbolic"}.get(kind, "emblem-ok-symbolic")
    cls = {"error": "oneui-badge-error", "1": "oneui-badge-error",
           "warn": "oneui-badge-warn", "2": "oneui-badge-warn",
           "question": "oneui-badge-ok"}.get(kind, "oneui-badge-ok")
    ic = Gtk.Image.new_from_icon_name(name)
    ic.set_pixel_size(size)
    ic.add_css_class("oneui-badge")
    ic.add_css_class(cls)
    return ic


def _message_window(app, kind, text, buttons, result, default_code):
    """A One UI-styled message window: the message in a big rounded card up top,
    the actions as pill buttons anchored at the BOTTOM (the reachable half).

    buttons is a list of (label, exit_code, is_default). Clicking any closes the
    window and sets result['code']. If the owner closes the window ANOTHER way -
    the X, Escape - result stays at default_code, set the moment the window is
    shown: 0 for an error (it WAS shown), the "no" code for a question (a plain
    close is a safe refusal). result stays at CANT_DRAW only if drawing threw
    before present(), so the shell falls back to zenity only on a real failure.
    """
    from gi.repository import Gtk

    win = _build(app, "Tandem")
    win.set_size_request(460, -1)
    win.set_default_size(480, 380)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    root.append(_flat_header())

    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
    body.set_margin_top(20)
    body.set_margin_bottom(24)
    body.set_margin_start(24)
    body.set_margin_end(24)

    card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    card.add_css_class("oneui-card")
    card.add_css_class("oneui-card-msg")
    badge = _badge(kind, size=30)
    badge.set_halign(Gtk.Align.START)
    card.append(badge)
    msg = Gtk.Label(label=text, wrap=True, xalign=0.0, yalign=0.0)
    msg.add_css_class("oneui-msg")
    msg.set_max_width_chars(48)
    card.append(msg)
    body.append(card)

    # The spacer pushes the actions to the bottom - the One UI reachable half.
    body.append(Gtk.Box(vexpand=True))

    btnbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12,
                     halign=Gtk.Align.END)
    for label, code, is_default in buttons:
        b = Gtk.Button(label=label)
        b.add_css_class("oneui-pill")
        b.add_css_class("oneui-primary" if is_default else "oneui-ghost")

        def _mk(c):
            def _cb(_btn):
                result["code"] = c
                win.close()
            return _cb
        b.connect("clicked", _mk(code))
        btnbox.append(b)
        if is_default:
            win.set_default_widget(b)
    body.append(btnbox)

    root.append(body)
    win.set_content(root)
    win.present()
    result["code"] = default_code   # shown: from here a plain close is not a failure


def _panel_card(sev, text, action="", fix_label="Fix", on_fix=None):
    """One finding as a rounded card: a squircle status badge, the sentence, and
    (when the finding carries an action token and we have somewhere to record it)
    a gradient "Fix" pill on the right that runs the one-click remedy.
    """
    from gi.repository import Gtk
    card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
    card.add_css_class("oneui-card")
    card.add_css_class("oneui-card-pad")
    b = _badge(sev, size=22)
    b.set_valign(Gtk.Align.CENTER)
    card.append(b)
    lbl = Gtk.Label(label=text, wrap=True, xalign=0.0, yalign=0.0)
    lbl.add_css_class("oneui-cardtext")
    lbl.set_hexpand(True)
    lbl.set_valign(Gtk.Align.CENTER)
    card.append(lbl)
    if action and on_fix is not None:
        btn = Gtk.Button(label=fix_label)
        btn.add_css_class("oneui-pill")
        btn.add_css_class("oneui-primary")
        btn.set_valign(Gtk.Align.CENTER)
        btn.connect("clicked", lambda _b, tok=action: on_fix(tok))
        card.append(btn)
    return card


def _panel_window(app, title, summary, findings, action_file, fix_label, result):
    """The Tandem Central: the machine's health triage as One UI cards.

    findings is a list of (sev, text, action). Empty findings means "all is
    well" - a single green card carrying the summary. Otherwise a big title with
    the summary as a subtitle sits above one card per finding (already sorted
    worst-first by the shell). A finding with an action token, when action_file
    is set, gets a Fix pill; clicking it writes the token to action_file and
    closes the window, so the shell can run the remedy. The choice travels
    through the file, never stdout.
    """
    from gi.repository import Gtk

    win = _build(app, title, resizable=True)
    win.set_default_size(620, 560)

    def on_fix(tok):
        _write_action(action_file, tok)
        win.close()

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    root.append(_flat_header())

    scr = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    body.set_margin_top(6)
    body.set_margin_bottom(26)
    body.set_margin_start(26)
    body.set_margin_end(26)

    # The header: a big title, and the summary as a quiet subtitle. When all is
    # well there are no cards, so the summary rides the green card instead.
    head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    head.set_margin_bottom(6)
    t = Gtk.Label(label=title, xalign=0.0, wrap=True)
    t.add_css_class("oneui-title")
    head.append(t)
    if findings and summary:
        s = Gtk.Label(label=summary, xalign=0.0, wrap=True)
        s.add_css_class("oneui-sub")
        head.append(s)
    body.append(head)

    if not findings:
        body.append(_panel_card("0", summary))
    else:
        for sev, text, action in findings:
            body.append(_panel_card(sev, text, action, fix_label, on_fix))

    scr.set_child(body)
    root.append(scr)
    win.set_content(root)
    win.present()
    result["code"] = 0


def _menu_row(label, icon, on_click):
    """One tool as a full-width, tappable One UI row: an accent-tinted squircle
    icon, the sentence, and a quiet chevron. The whole row is the button - a One
    UI settings row, not a label with a small button beside it."""
    from gi.repository import Gtk
    btn = Gtk.Button()
    btn.add_css_class("oneui-menucard")
    btn.set_hexpand(True)
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
    ic = Gtk.Image.new_from_icon_name(icon or "application-x-executable-symbolic")
    ic.set_pixel_size(22)
    ic.add_css_class("oneui-badge")
    ic.add_css_class("oneui-badge-tool")
    ic.set_valign(Gtk.Align.CENTER)
    row.append(ic)
    lbl = Gtk.Label(label=label, wrap=True, xalign=0.0, yalign=0.5)
    lbl.add_css_class("oneui-cardtext")
    lbl.set_hexpand(True)
    row.append(lbl)
    chev = Gtk.Image.new_from_icon_name("go-next-symbolic")
    chev.set_pixel_size(16)
    chev.add_css_class("oneui-chev")
    chev.set_valign(Gtk.Align.CENTER)
    row.append(chev)
    btn.set_child(row)
    btn.connect("clicked", lambda _b: on_click())
    return btn


def _menu_window(app, title, subtitle, items, action_file, version, result):
    """The Tools menu ("Ferramentas") as One UI cards: everything the library is
    not - doctor, backup, ports, the community list - one tappable row per tool,
    grouped into sections with quiet headers. items is a list of
    (token, label, icon, group); a group header is drawn whenever the group
    changes from the previous row (the shell emits the rows already in order). A
    click writes the token to action_file and closes; closing the window ANOTHER
    way (X, Escape) leaves the file untouched, so the shell reads "" and stops.
    The choice travels through the file, never stdout - the panel/home contract.

    `version` (e.g. "Tandem 4.78") is shown as a quiet right-aligned label beside
    the title, the way the zenity panel put it in its window title: the owner has
    to be able to read which Tandem he is running without opening a terminal.
    """
    from gi.repository import Gtk

    win = _build(app, title, resizable=True)
    win.set_default_size(560, 660)

    def choose(token):
        _write_action(action_file, token)
        win.close()

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    root.append(_flat_header())

    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    body.set_margin_top(2)
    body.set_margin_start(24)
    body.set_margin_end(24)

    head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    toprow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    t = Gtk.Label(label=title, xalign=0.0, hexpand=True)
    t.add_css_class("oneui-title")
    toprow.append(t)
    if version:
        v = Gtk.Label(label=version, xalign=1.0)
        v.add_css_class("oneui-sub")
        v.set_valign(Gtk.Align.END)
        toprow.append(v)
    head.append(toprow)
    if subtitle:
        s = Gtk.Label(label=subtitle, xalign=0.0, wrap=True)
        s.add_css_class("oneui-sub")
        head.append(s)
    body.append(head)
    root.append(body)

    scr = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
    listbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    listbox.set_margin_top(10)
    listbox.set_margin_bottom(22)
    listbox.set_margin_start(24)
    listbox.set_margin_end(24)

    last_group = None
    for token, label, icon, group in items:
        if group and group != last_group:
            h = Gtk.Label(label=group, xalign=0.0)
            h.add_css_class("oneui-grouphdr")
            listbox.append(h)
            last_group = group
        listbox.append(_menu_row(label, icon, lambda t=token: choose(t)))

    scr.set_child(listbox)
    root.append(scr)
    win.set_content(root)
    win.present()
    result["code"] = 0


def _text_window(app, title, content, result):
    from gi.repository import Gtk

    win = _build(app, title, resizable=True)
    win.set_default_size(720, 580)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    root.append(_flat_header())

    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    body.set_margin_top(4)
    body.set_margin_bottom(24)
    body.set_margin_start(24)
    body.set_margin_end(24)

    t = Gtk.Label(label=title, xalign=0.0, wrap=True)
    t.add_css_class("oneui-title")
    body.append(t)

    # The report itself sits in a rounded card, monospace, scrollable.
    card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    card.add_css_class("oneui-card")
    scr = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
    tv = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                      left_margin=20, right_margin=20, top_margin=18, bottom_margin=18,
                      wrap_mode=Gtk.WrapMode.WORD_CHAR)
    tv.get_buffer().set_text(content)
    tv.add_css_class("oneui-mono")
    scr.set_child(tv)
    card.append(scr)
    body.append(card)

    root.append(body)
    win.set_content(root)
    win.present()
    result["code"] = 0


def _progress_window(app, title, result):
    """An indeterminate One UI progress window - the pulsing bar shown while a
    long install runs. It reads lines from stdin and, for each one that begins
    with '#', updates the message: the exact protocol zenity --progress speaks,
    so this is a drop-in reader on the same FIFO. It closes when stdin reaches
    EOF (the shell closing its write end in t_progresso_fecha). Purely cosmetic:
    it only ever SHOWS work, never blocks it and never offers to cancel it.
    """
    import threading
    from gi.repository import Gtk, GLib

    win = _build(app, "Tandem", resizable=False)
    win.set_default_size(460, -1)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    root.append(_flat_header())

    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
    body.set_margin_top(4)
    body.set_margin_bottom(28)
    body.set_margin_start(26)
    body.set_margin_end(26)

    card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
    card.add_css_class("oneui-card")
    card.add_css_class("oneui-card-msg")

    lbl = Gtk.Label(label=title, wrap=True, xalign=0.0)
    lbl.add_css_class("oneui-msg")
    card.append(lbl)

    bar = Gtk.ProgressBar()
    bar.add_css_class("oneui-progress")
    card.append(bar)

    body.append(card)
    root.append(body)
    win.set_content(root)
    win.present()
    result["code"] = 0

    def _close():
        try:
            win.close()
        except Exception:
            pass
        return False

    def _tick():
        bar.pulse()
        return True

    GLib.timeout_add(110, _tick)

    def _reader():
        # readline, not iteration: iterating a pipe read-aheads a whole buffer
        # and the label would lag behind the work by many lines. readline
        # returns each line as it arrives, and "" at EOF.
        try:
            for line in iter(sys.stdin.readline, ""):
                line = line.rstrip("\n")
                if line.startswith("#"):
                    msg = line[1:].strip()
                    GLib.idle_add(lbl.set_label, msg or title)
        except Exception:
            pass
        GLib.idle_add(_close)

    threading.Thread(target=_reader, daemon=True).start()


def _home_window(app, title, records, action_file, result, msgs):
    """The Tandem main screen: the shop's library of programs, not a menu of
    commands. records is a list of (tipo, nome, fonte, lancador, atualizavel).
    Each row shows the system's own mark, the name, where it came from, and an
    Open button; a search box and per-system chips filter the list; a bottom bar
    installs a new file. A click writes ONE token to action_file and closes, the
    same contract the health panel uses - abrir<TAB>fonte<TAB>lancador, instalar,
    or ferramentas - so the shell reads the file and does the rest. gui.py never
    launches or installs anything itself.
    """
    from gi.repository import Gtk, GLib

    win = _build(app, title, resizable=True)
    win.set_default_size(680, 620)

    def choose(token):
        _write_action(action_file, token)
        win.close()

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    root.append(_flat_header())

    outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    outer.set_margin_top(2)
    outer.set_margin_start(22)
    outer.set_margin_end(22)

    # Title + count.
    head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    t = Gtk.Label(label=title, xalign=0.0, hexpand=True)
    t.add_css_class("oneui-title")
    head.append(t)
    sub = Gtk.Label(label=(msgs.get("count") or str(len(records))), xalign=1.0)
    sub.add_css_class("oneui-sub")
    sub.set_valign(Gtk.Align.END)
    head.append(sub)
    outer.append(head)

    # Search.
    search = Gtk.SearchEntry()
    search.set_placeholder_text(msgs.get("search", "Search a program"))
    search.add_css_class("oneui-search")
    outer.append(search)

    # Controls row: the system filter chips on the left, the "organize" selector
    # on the right. state carries the active system filter AND the sort mode.
    controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    chips = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8, hexpand=True)
    state = {"tipo": "", "ordem": "nome"}
    chip_btns = []

    def make_chip(tipo, label):
        b = Gtk.ToggleButton(label=label)
        b.add_css_class("oneui-chip")
        chip_btns.append((b, tipo))
        chips.append(b)
        return b

    make_chip("", msgs.get("all", "All")).set_active(True)
    present = []
    for r in records:
        if r[0] not in present:
            present.append(r[0])
    for tp in ("windows", "android", "linux"):
        if tp in present:
            make_chip(tp, _PLATFORM_LABEL.get(tp, tp))
    controls.append(chips)

    # The organize selector: by name (A->Z), by system (grouped), by update
    # (what needs acting on first) - a file manager's view menu. The order of
    # these two lists is the contract with _MODES below.
    modos = [("nome", msgs.get("ordem_nome", "By name")),
             ("sistema", msgs.get("ordem_sistema", "By system")),
             ("update", msgs.get("ordem_update", "By update"))]
    nomes = Gtk.StringList()
    for _k, lab in modos:
        nomes.append(lab)
    ordena = Gtk.DropDown(model=nomes)
    ordena.add_css_class("oneui-ordena")
    ordena.set_valign(Gtk.Align.CENTER)
    controls.append(ordena)
    outer.append(controls)

    root.append(outer)

    # The list itself, scrollable. It is rebuilt whenever the search text, the
    # active chip, or the sort mode changes - grouping inserts header rows and
    # reorders, so a visibility toggle would not be enough.
    scr = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
    listbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
    listbox.set_margin_top(6)
    listbox.set_margin_bottom(20)
    listbox.set_margin_start(22)
    listbox.set_margin_end(22)

    def card_for(record):
        tipo, nome, fonte, lancador, atualizavel, tem_update = record
        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        card.add_css_class("oneui-card")
        card.add_css_class("oneui-card-pad")
        card.append(_icon_with_dot(tipo, atualizavel, tem_update, msgs, 30))
        meta = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1, hexpand=True)
        nm = Gtk.Label(label=nome, xalign=0.0)
        nm.add_css_class("oneui-cardtext")
        nm.set_ellipsize(3)  # PANGO_ELLIPSIZE_END
        meta.append(nm)
        # The source line, and on a program with an update waiting an amber note
        # right beside it - so the fact is not hidden in a tooltip nobody hovers.
        subrow = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        sb = Gtk.Label(label=_display_fonte(fonte, msgs), xalign=0.0)
        sb.add_css_class("oneui-sub")
        subrow.append(sb)
        if atualizavel == "sim" and tem_update == "sim":
            tag = Gtk.Label(label=msgs.get("dot_atualizar", "Update available"),
                            xalign=0.0)
            tag.add_css_class("oneui-updtag")
            subrow.append(tag)
        meta.append(subrow)
        card.append(meta)
        btn = Gtk.Button(label=msgs.get("open", "Open"))
        btn.add_css_class("oneui-pill")
        btn.add_css_class("oneui-ghost")
        btn.set_valign(Gtk.Align.CENTER)
        btn.connect("clicked",
                    lambda _b, f=fonte, l=lancador: choose("abrir\t%s\t%s" % (f, l)))
        card.append(btn)
        return card

    def header_for(group_key):
        # A system group header reuses the platform name; nothing else groups.
        label = _PLATFORM_LABEL.get(group_key, group_key)
        h = Gtk.Label(label=label, xalign=0.0)
        h.add_css_class("oneui-grouphdr")
        return h

    def rebuild(*_a):
        child = listbox.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            listbox.remove(child)
            child = nxt
        q = search.get_text().strip().lower()
        tp = state["tipo"]
        kept = [r for r in records
                if (not tp or r[0] == tp) and (not q or q in r[1].lower())]
        for kind, val in _order_items(kept, state["ordem"]):
            listbox.append(header_for(val) if kind == "group" else card_for(val))

    scr.set_child(listbox)
    root.append(scr)

    # Bottom bar. When at least one program has an update, an "Update all" button
    # sits above the install action - the Play-Store gesture the owner asked for.
    bar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
    bar.set_margin_top(6)
    bar.set_margin_bottom(16)
    bar.set_margin_start(22)
    bar.set_margin_end(22)
    upd_srcs = []
    for r in records:
        if r[4] == "sim" and r[5] == "sim" and r[2] not in upd_srcs:
            upd_srcs.append(r[2])
    if upd_srcs:
        upall = Gtk.Button(label=msgs.get("bib_atualizar_tudo", "Update all"))
        upall.add_css_class("oneui-pill")
        upall.add_css_class("oneui-updateall")
        # The token carries the managers that had an update WHEN THE SCREEN WAS
        # DRAWN, so the update acts on that snapshot rather than re-reading a
        # cache that a background refresh may have emptied in the meantime.
        upall.connect("clicked",
                      lambda _b, s="\t".join(upd_srcs): choose("atualizar-tudo\t" + s))
        bar.append(upall)
    prim = Gtk.Button(label=msgs.get("install", "Install or open a file"))
    prim.add_css_class("oneui-pill")
    prim.add_css_class("oneui-primary")
    prim.connect("clicked", lambda _b: choose("instalar"))
    bar.append(prim)
    # Everything the old menu did that is not a program - doctor, backup, ports,
    # health - still has a home, one tap away, so the library replaces the menu
    # without taking anything from the one person who cannot get it from a
    # terminal. The shell opens the tools list on this token.
    tools = Gtk.Button(label=msgs.get("tools", "Tools"))
    tools.add_css_class("oneui-toolslink")
    tools.set_halign(Gtk.Align.CENTER)
    tools.set_margin_top(10)
    tools.connect("clicked", lambda _b: choose("ferramentas"))
    bar.append(tools)
    root.append(bar)

    # Search text, the active system chip, and the sort mode all just rebuild
    # the list.
    search.connect("search-changed", rebuild)

    def on_chip(btn, tipo):
        if not btn.get_active():
            btn.set_active(True)   # a chip cannot be toggled off; one is always on
            return
        state["tipo"] = tipo
        for b, _tp in chip_btns:
            if b is not btn:
                b.set_active(False)
        rebuild()

    for b, tp in chip_btns:
        b.connect("toggled", on_chip, tp)

    def on_ordena(dd, _param):
        i = dd.get_selected()
        if 0 <= i < len(modos):
            state["ordem"] = modos[i][0]
            rebuild()

    ordena.connect("notify::selected", on_ordena)

    # An initial sort mode can be forced (used to render each view); harmless
    # when unset.
    ini = os.environ.get("TANDEM_GUI_ORDEM", "")
    keys = [m[0] for m in modos]
    if ini in keys:
        state["ordem"] = ini
        ordena.set_selected(keys.index(ini))

    rebuild()   # first paint

    win.set_content(root)
    win.present()
    result["code"] = 0


def _run(build_fn):
    from gi.repository import Adw, Gio
    result = {"code": CANT_DRAW}
    app = Adw.Application(application_id="org.tandem.Gui",
                          flags=Gio.ApplicationFlags.NON_UNIQUE)

    def on_activate(a):
        build_fn(a, result)
    app.connect("activate", on_activate)
    app.run([])
    return result["code"]


def main():
    argv = sys.argv[1:]
    if not argv:
        return CANT_DRAW
    kind = argv[0]

    if kind == "--check":
        try:
            _imports_ok()
            return 0
        except Exception:
            return 1

    if not _has_display():
        return CANT_DRAW
    try:
        _imports_ok()
    except Exception:
        return CANT_DRAW

    try:
        if kind == "error":
            text = argv[1] if len(argv) > 1 else ""
            ok = argv[2] if len(argv) > 2 else "OK"
            return _run(lambda a, r: _message_window(
                a, "error", text, [(ok, 0, True)], r, 0))

        if kind == "question":
            text = argv[1] if len(argv) > 1 else ""
            yes = argv[2] if len(argv) > 2 else "Yes"
            no = argv[3] if len(argv) > 3 else "No"
            # Closing a question (X, Escape) is a safe "no" (code 1), matching
            # zenity --question and t_pergunta's "no window = no".
            return _run(lambda a, r: _message_window(
                a, "question", text, [(no, 1, False), (yes, 0, True)], r, 1))

        if kind == "text":
            title = argv[1] if len(argv) > 1 else "Tandem"
            content = sys.stdin.read()
            return _run(lambda a, r: _text_window(a, title, content, r))

        if kind == "panel":
            title = argv[1] if len(argv) > 1 else "Tandem"
            summary = argv[2] if len(argv) > 2 else ""
            action_file = argv[3] if len(argv) > 3 and argv[3] else None
            fix_label = argv[4] if len(argv) > 4 and argv[4] else "Fix"
            findings = []
            for line in sys.stdin.read().splitlines():
                if not line.strip():
                    continue
                parts = line.split("\t")
                sev = parts[0] if parts[0] else "2"
                text = parts[1] if len(parts) > 1 else ""
                action = parts[2] if len(parts) > 2 else ""
                findings.append((sev, text, action))
            return _run(lambda a, r: _panel_window(
                a, title, summary, findings, action_file, fix_label, r))

        if kind == "menu":
            title = argv[1] if len(argv) > 1 else "Tandem"
            subtitle = argv[2] if len(argv) > 2 else ""
            action_file = argv[3] if len(argv) > 3 and argv[3] else None
            version = argv[4] if len(argv) > 4 else ""
            items = []
            for line in sys.stdin.read().splitlines():
                if not line.strip():
                    continue
                parts = line.split("\t")
                token = parts[0]
                label = parts[1] if len(parts) > 1 else ""
                icon = parts[2] if len(parts) > 2 else ""
                group = parts[3] if len(parts) > 3 else ""
                items.append((token, label, icon, group))
            return _run(lambda a, r: _menu_window(
                a, title, subtitle, items, action_file, version, r))

        if kind == "progress":
            title = argv[1] if len(argv) > 1 else "Tandem"
            return _run(lambda a, r: _progress_window(a, title, r))

        if kind == "home":
            title = argv[1] if len(argv) > 1 else "Tandem"
            action_file = argv[2] if len(argv) > 2 and argv[2] else None
            # Labels come tab-joined in one argument, in a fixed order, so they
            # arrive translated without a pile of positional arguments.
            keys = ["all", "open", "install", "search", "count", "tools",
                    "dot_atualizar", "dot_atual", "dot_gerido", "dot_checando",
                    "ordem_nome", "ordem_sistema", "ordem_update",
                    "bib_atualizar_tudo", "fonte_sistema"]
            labels = (argv[3] if len(argv) > 3 else "").split("\t")
            msgs = {}
            for i, k in enumerate(keys):
                if i < len(labels) and labels[i]:
                    msgs[k] = labels[i]
            records = []
            for line in sys.stdin.read().splitlines():
                if not line.strip():
                    continue
                parts = line.split("\t")
                # tem_update is the sixth field (4.73); default "nao" so a record
                # from an older caller still renders, just without an amber dot.
                while len(parts) < 6:
                    parts.append("nao" if len(parts) == 5 else "")
                records.append(tuple(parts[:6]))
            return _run(lambda a, r: _home_window(
                a, title, records, action_file, r, msgs))
    except Exception:
        return CANT_DRAW
    return CANT_DRAW


if __name__ == "__main__":
    sys.exit(main())
