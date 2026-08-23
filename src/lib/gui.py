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
.oneui-ghost { background: @GHOSTBG@; color: @GHOSTFG@; }
.oneui-mono textview, .oneui-mono text { font-family: monospace; font-size: 13px; color: @CTEXT@; }
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
    except Exception:
        return CANT_DRAW
    return CANT_DRAW


if __name__ == "__main__":
    sys.exit(main())
