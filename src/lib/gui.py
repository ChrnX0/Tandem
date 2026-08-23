#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""The modern face of Tandem: GTK4 + libadwaita dialogs.

This is the OPTIONAL modern backend for the handful of windows a shop owner
sees - the error, the yes/no question, and the long-text viewer. The shell
(common.sh) tries this first and falls back to zenity when it is not here, so
nothing depends on it: an old machine without libadwaita, or a headless run,
loses the new look and keeps every word. That fallback is the whole reason this
can exist without breaking the project's first rule - no error ends in silence.

Contract, so the shell can read exit codes the same way it reads zenity's:

    gui.py --check                 -> 0 if GTK4 + libadwaita import here, else 1
    gui.py error <text> [ok]       -> shows the error; 0 when shown, 2 when it
                                      could not draw (caller falls back)
    gui.py question <text> <yes> <no>
                                   -> 0 = the yes button, 1 = the no button,
                                      2 = could not draw (caller falls back)
    gui.py text <title>            -> long text on STDIN in a scrollable window;
                                      0 when shown, 2 when it could not draw
    gui.py panel <title> <summary> -> the health triage as coloured cards; one
                                      "sev<TAB>text" finding per line on STDIN
                                      (sev 1=red, 2=amber), empty STDIN = one
                                      green all-clear card. 0 shown, 2 cannot draw

Every drawing path is wrapped so a failure NEVER reaches the owner as a Python
traceback - it becomes exit 2, and the shell shows the zenity window instead.
The text is Unicode from Python's own strings, so the locale/charmap trap that
erases zenity's accented windows cannot happen here.
"""
import os
import sys

CANT_DRAW = 2   # the shell reads this as "fall back to zenity"


def _imports_ok():
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Gtk, Adw  # noqa: F401
    return True


def _has_display():
    return bool(os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))


# A small, calm stylesheet: Tandem's teal accent over libadwaita's own modern
# shapes. Everything else (rounding, spacing, dark/light) comes from libadwaita,
# so this stays tiny and cannot fight the system theme.
_CSS = b"""
@define-color accent_color #0C7A6E;
@define-color accent_bg_color #0E7A6E;
@define-color accent_fg_color #ffffff;
.tandem-icon { min-width: 44px; min-height: 44px; border-radius: 12px; }
.tandem-icon-ok    { background: rgba(46,158,91,.16);  color: #2E9E5B; }
.tandem-icon-warn  { background: rgba(179,117,24,.16); color: #B37518; }
.tandem-icon-error { background: rgba(194,70,52,.16);  color: #C24634; }
.tandem-body { padding: 22px 24px 20px 24px; }
.tandem-mono textview, .tandem-mono text { font-family: monospace; }
.tandem-card { padding: 14px 16px; }
.tandem-summary { margin-bottom: 4px; }
"""


def _build(app, title):
    from gi.repository import Gtk, Adw, Gdk
    prov = Gtk.CssProvider()
    prov.load_from_data(_CSS)
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = Adw.ApplicationWindow(application=app)
    win.set_title(title)
    win.set_resizable(False)
    return win


def _message_window(app, kind, text, buttons, result, default_code):
    """A calm libadwaita window: icon, message, one or two pill buttons.

    buttons is a list of (label, exit_code, is_default). Clicking any closes the
    window and sets result['code'] to that button's code. If the owner closes
    the window ANOTHER way - the X, Escape - result stays at default_code, which
    is set the moment the window is shown: for an error that is 0 (it WAS shown),
    for a question that is the "no" code (closing a question is a safe refusal,
    exactly as zenity treats it). result stays at CANT_DRAW only if drawing threw
    before present(), so the shell falls back to zenity only on a real failure.
    """
    from gi.repository import Gtk, Adw

    win = _build(app, "Tandem")
    win.set_size_request(400, -1)
    win.set_default_size(430, -1)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    root.append(Adw.HeaderBar(show_end_title_buttons=True,
                              title_widget=Adw.WindowTitle(title="Tandem")))

    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    body.add_css_class("tandem-body")

    icon_name = {"error": "dialog-error-symbolic",
                 "warn": "dialog-warning-symbolic",
                 "question": "dialog-question-symbolic"}.get(kind, "dialog-information-symbolic")
    icon_cls = {"error": "tandem-icon-error",
                "question": "tandem-icon-ok"}.get(kind, "tandem-icon-warn")
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
    ic = Gtk.Image.new_from_icon_name(icon_name)
    ic.set_pixel_size(22)
    ic.add_css_class("tandem-icon")
    ic.add_css_class(icon_cls)
    ic.set_valign(Gtk.Align.START)
    row.append(ic)
    msg = Gtk.Label(label=text, wrap=True, xalign=0.0, yalign=0.0)
    msg.set_max_width_chars(46)
    msg.set_hexpand(True)
    row.append(msg)
    body.append(row)

    btnbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10,
                     halign=Gtk.Align.END, homogeneous=False)
    btnbox.set_margin_top(6)
    for label, code, is_default in buttons:
        b = Gtk.Button(label=label)
        b.add_css_class("pill")
        if is_default:
            b.add_css_class("suggested-action")

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


def _panel_card(sev, text):
    """One finding as a calm card: a colour-coded status icon and the sentence.

    sev is '1' (act now -> red), '2' (worth knowing -> amber), anything else is
    treated as all-clear/info (green). The colours reuse the same .tandem-icon-*
    classes the message windows use, so the whole face is one visual language.
    """
    from gi.repository import Gtk
    icon_name = {"1": "dialog-error-symbolic",
                 "2": "dialog-warning-symbolic"}.get(sev, "emblem-ok-symbolic")
    icon_cls = {"1": "tandem-icon-error",
                "2": "tandem-icon-warn"}.get(sev, "tandem-icon-ok")
    card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
    card.add_css_class("card")
    card.add_css_class("tandem-card")
    ic = Gtk.Image.new_from_icon_name(icon_name)
    ic.set_pixel_size(20)
    ic.add_css_class("tandem-icon")
    ic.add_css_class(icon_cls)
    ic.set_valign(Gtk.Align.START)
    card.append(ic)
    lbl = Gtk.Label(label=text, wrap=True, xalign=0.0, yalign=0.0)
    lbl.set_hexpand(True)
    card.append(lbl)
    return card


def _panel_window(app, title, summary, findings, result):
    """The Tandem Central: the machine's health triage as coloured cards.

    findings is a list of (sev, text). Empty findings means "all is well" - a
    single green card carrying the summary. Otherwise the summary is a heading
    over one card per finding (already sorted worst-first by the shell).
    """
    from gi.repository import Gtk, Adw

    win = _build(app, title)
    win.set_resizable(True)
    win.set_default_size(560, 520)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    root.append(Adw.HeaderBar(title_widget=Adw.WindowTitle(title=title)))

    scr = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
    body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
    body.add_css_class("tandem-body")

    if not findings:
        # All clear: one green card, no separate heading (the card says it).
        body.append(_panel_card("0", summary))
    else:
        if summary:
            head = Gtk.Label(label=summary, wrap=True, xalign=0.0)
            head.add_css_class("title-4")
            head.add_css_class("tandem-summary")
            body.append(head)
        for sev, text in findings:
            body.append(_panel_card(sev, text))

    scr.set_child(body)
    root.append(scr)
    win.set_content(root)
    win.present()
    result["code"] = 0


def _text_window(app, title, content, result):
    from gi.repository import Gtk, Adw

    win = _build(app, title)
    win.set_resizable(True)
    win.set_default_size(720, 560)

    root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    root.append(Adw.HeaderBar(title_widget=Adw.WindowTitle(title=title)))

    scr = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
    tv = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                      left_margin=16, right_margin=16, top_margin=14, bottom_margin=14,
                      wrap_mode=Gtk.WrapMode.WORD_CHAR)
    tv.get_buffer().set_text(content)
    tv.add_css_class("tandem-mono")
    scr.set_child(tv)
    root.append(scr)
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
            findings = []
            for line in sys.stdin.read().splitlines():
                if not line.strip():
                    continue
                if "\t" in line:
                    sev, text = line.split("\t", 1)
                else:
                    sev, text = "2", line
                findings.append((sev, text))
            return _run(lambda a, r: _panel_window(a, title, summary, findings, r))
    except Exception:
        return CANT_DRAW
    return CANT_DRAW


if __name__ == "__main__":
    sys.exit(main())
