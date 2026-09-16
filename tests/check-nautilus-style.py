import pathlib
import sys

try:
    import cairo
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    gi.require_version("Gsk", "4.0")
    from gi.repository import Adw, Gdk, Gio, Gtk
except (ImportError, ValueError):
    print("Nautilus style check skipped: GTK 4/libadwaita Python bindings unavailable")
    sys.exit(0)

if not Gtk.init_check():
    print("Nautilus style check skipped: no display")
    sys.exit(0)
Adw.init()
Gtk.Settings.get_default().set_property("gtk-enable-animations", False)
repo = pathlib.Path(__file__).resolve().parent.parent
errors = []
provider = Gtk.CssProvider()
provider.connect("parsing-error", lambda _, section, error: errors.append(str(error)))
provider.load_from_path(str(repo / "dot_config/gtk-4.0/create_colors.css"))
Gtk.StyleContext.add_provider_for_display(
    Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
)
style = Gtk.CssProvider()
style.connect("parsing-error", lambda _, section, error: errors.append(str(error)))
style.load_from_path(str(repo / "dot_config/gtk-4.0/nautilus.css"))
Gtk.StyleContext.add_provider_for_display(
    Gdk.Display.get_default(), style, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1
)
assert not errors, errors


def background_alpha(widget):
    snapshot = Gtk.Snapshot()
    snapshot.render_background(widget.get_style_context(), 0, 0, 100, 100)
    node = snapshot.to_node()
    if node is None:
        return 0
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 100, 100)
    node.draw(cairo.Context(surface))
    surface.flush()
    offset = 50 * surface.get_stride() + 50 * 4
    pixel = int.from_bytes(surface.get_data()[offset:offset + 4], sys.byteorder)
    return (pixel >> 24) / 255


def descendants(widget):
    child = widget.get_first_child()
    while child:
        yield child
        yield from descendants(child)
        child = child.get_next_sibling()


# Mirror Nautilus 50's structural layers without opening user files or windows.
for css_class in ("nautilus-window", "nautilus-file-chooser", "unrelated"):
    window = Adw.Window()
    window.add_css_class(css_class)
    split = Adw.OverlaySplitView()
    if css_class == "nautilus-window":
        window.add_css_class("view")
    elif css_class == "nautilus-file-chooser":
        split.add_css_class("view")
    window.set_content(split)
    content = Adw.ToolbarView()
    sidebar = Adw.ToolbarView()
    for toolbar in (content, sidebar):
        toolbar.set_top_bar_style(Adw.ToolbarStyle.RAISED)
        toolbar.add_top_bar(Adw.HeaderBar())
    split.set_content(content)
    split.set_sidebar(sidebar)
    box = Gtk.Box()
    label = Gtk.Label(label="Files")
    icon = Gtk.Image.new_from_icon_name("folder-symbolic")
    box.append(label)
    box.append(icon)
    menu = Gio.Menu()
    menu.append("Test", "win.test")
    popover = Gtk.PopoverMenu.new_from_model(menu)
    button = Gtk.MenuButton()
    button.set_popover(popover)
    box.append(button)
    dropdown = Gtk.DropDown.new_from_strings(["All files", "Image files"])
    box.append(dropdown)
    content.set_content(box)

    for collapsed in (False, True):
        split.set_collapsed(collapsed)
        for backdrop in (False, True):
            widgets = [window, *descendants(window)]
            for widget in widgets:
                if backdrop:
                    widget.set_state_flags(Gtk.StateFlags.BACKDROP, False)
                else:
                    widget.unset_state_flags(Gtk.StateFlags.BACKDROP)
            expected = 1 if css_class == "unrelated" else 0.9
            assert abs(background_alpha(window) - expected) < 0.01, css_class
            if css_class != "unrelated":
                assert background_alpha(split) == 0
                for widget in widgets:
                    pane = widget.get_parent() == split and (
                        widget.has_css_class("sidebar-pane") or widget.has_css_class("background")
                    )
                    if pane or widget.has_css_class("top-bar"):
                        assert background_alpha(widget) == 0, widget.get_css_name()
            for widget in (window, split, content, box, label, icon):
                assert widget.get_opacity() == 1
            for widget in (label, icon):
                assert widget.get_color().alpha == 1
            # Both context menus and GtkDropDown use popover contents nodes.
            for root in (popover, dropdown):
                contents = [w for w in descendants(root) if w.get_css_name() == "contents"]
                assert contents, root.get_css_name()
                for widget in contents:
                    assert background_alpha(widget) == 1, (css_class, root.get_css_name())
    window.destroy()

print("Nautilus backgrounds are translucent; text, icons, menus and other windows stay opaque")
