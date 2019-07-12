import gio.Application : GioApplication = Application;
import gio.Settings;
import gio.SimpleAction;
import gtk.Application;
import gtk.ApplicationWindow;
import gtk.Adjustment;
import gtk.Switch;
import gtk.ComboBoxText;
import gtk.Window;
import gtk.Button;
import gtk.Revealer;
import gtk.HeaderBar;
import gtk.Stack;
import gtk.StackSidebar;
import gtk.FileChooserButton;
import gtk.ListBox;
import gtk.Dialog;
import gtk.TreeView;
import gtk.ListStore;
import gtk.TreeStore;
import gtk.TreeIter;
import gobject.Signals;
import handy.Leaflet;
import Glade;
import Vals;
import std.stdio;
import std.typecons;
import std.format;

// Widgets annotated with this will get bound to GSettings
struct Setting {
	string setting;
	string prop;
}

mixin template PageAppearance() {
	@ById("sa_appear_wp_picture_chooser") FileChooserButton picChooser;

	void setupAppearance() {
		picChooser.addOnFileSet(delegate void(FileChooserButton) {
			wpsettings.setString("picture-path", picChooser.getFilename());
		});
	}

	void updateAppearance() {
		picChooser.selectFilename(wpsettings.getString("picture-path"));
	}
}

mixin template PageMouse() {
	@ById("adj-mouse-speed") @Setting("mice-accel-speed", "value") Adjustment mouseSpeed;
	@ById("adj-mouse-scroll-speed") @Setting("mice-scroll-speed", "value") Adjustment mouseScrollSpeed;
	@ById("adj-touchpad-speed") @Setting("touchpads-accel-speed", "value") Adjustment touchpadSpeed;
	@ById("adj-touchpad-scroll-speed") @Setting("touchpads-scroll-speed", "value") Adjustment touchpadScrollSpeed;
	@ById("toggle-natural-scrolling") @Setting("touchpads-natural-scrolling", "active") Switch touchpadNatScroll;
	@ById("toggle-tap-click") @Setting("touchpads-tap-click", "active") Switch touchpadTapClick;
	@ById("choose-click-method") @Setting("touchpads-click-method", "active-id") ComboBoxText touchpadClickMethod;
	@ById("choose-scroll-method") @Setting("touchpads-scroll-method", "active-id") ComboBoxText touchpadScrollMethod;
	@ById("toggle-touchpad-dwt") @Setting("touchpads-dwt", "active") Switch touchpadDwt;
	@ById("toggle-dwmouse") @Setting("touchpads-dwmouse", "active") Switch touchpadDwmouse;

}

struct XkbLayout {
	string desc;
	string[string] variants;
}

struct XkbGroup {
	string desc;
	string[string] opts;
}

mixin template PageKeyboard() {
	@ById("store-layouts") ListStore curLayoutStore;
	@ById("tree-layouts") TreeView curLayoutTree;
	@ById("adj-repeat-rate") @Setting("kb-repeat-rate", "value") Adjustment kbRepeatRate;
	@ById("adj-repeat-delay") @Setting("kb-repeat-delay", "value") Adjustment kbRepeatDelay;
	@ById("toggle-ctrl-as-esc") @Setting("m2k-ctrl-as-esc", "active") Switch ctrlAsEsc;
	@ById("toggle-shifts-as-parens") @Setting("m2k-shifts-as-parens", "active") Switch shiftsAsParens;

	XkbLayout[string] layouts;
	XkbGroup[string] optgroups; // TODO use this

	void setupKeyboard() {
		import std.xml;
		import std.file;

		string s = cast(string) std.file.read("/usr/local/share/X11/xkb/rules/evdev.xml"); // TODO dir from meson
		auto xml = new DocumentParser(s);
		xml.onStartTag["layout"] = (ElementParser xml) {
			string key;
			XkbLayout layout;
			xml.onStartTag["configItem"] = (ElementParser xml) {
				xml.onEndTag["name"] = (in Element e) { key = e.text(); };
				xml.onEndTag["description"] = (in Element e) { layout.desc = e.text(); };
				xml.parse();
			};
			xml.onStartTag["variant"] = (ElementParser xml) {
				string key;
				string desc;
				xml.onEndTag["name"] = (in Element e) { key = e.text(); };
				xml.onEndTag["description"] = (in Element e) { desc = e.text(); };
				xml.parse();
				layout.variants[key] = desc;
			};
			xml.parse();
			layouts[key] = layout;
		};
		xml.parse();

		updateKeyboard();

		auto actAdd = new SimpleAction("add-keyboard-layout", null);
		actAdd.addOnActivate(delegate void(Variant, SimpleAction) {
			auto dialog = new AddLayoutDialog();
			dialog.setLayouts(layouts);
			dialog.dialog.setTransientFor(toplevel);
			if (dialog.dialog.run() == GtkResponseType.OK) {
				dialog.addToSettings(settings);
			}
			dialog.dialog.destroy();
		});
		toplevel.addAction(actAdd);

		auto actRemove = new SimpleAction("remove-keyboard-layout", null);
		actRemove.addOnActivate(delegate void(Variant, SimpleAction) {
			import std.algorithm : remove;

			auto iter = curLayoutTree.getSelectedIter();
			if (iter is null)
				return;
			auto layList = settings.getValue("xkb-layouts").toDVal!(Tuple!(string, string)[]);
			auto idx = iter.getTreePath().getIndices()[0];
			settings.setValue("xkb-layouts", layList.remove(idx).toVariant!());
		});
		toplevel.addAction(actRemove);
	}

	void updateKeyboard() {
		curLayoutStore.clear();
		auto layList = settings.getValue("xkb-layouts").toDVal!(Tuple!(string, "layout_key",
				string, "variant_key")[]);
		foreach (ref tup; layList) {
			auto layout = layouts.get(tup.layout_key, XkbLayout(format("[UNKNOWN] %s", tup.layout_key), null));
			auto variant = layout.variants.get(tup.variant_key, "Default");
			TreeIter row;
			curLayoutStore.append(row);
			curLayoutStore.setValue(row, 0, format("%s\n<span size='smaller'>%s</span>", layout.desc, variant));
		}
	}
}

class AddLayoutDialog {
	@ById("dialog_add_keyboard_layout") Dialog dialog;
	@ById("tree_add_keyboard_layout") TreeView tree;
	@ById("tree_store_xkb_layouts") TreeStore layoutStore;

	mixin Glade!("/technology/unrelenting/numbernine/settings/dialogs.glade");
	mixin Css!("/technology/unrelenting/numbernine/settings/style.css", dialog);

	void setLayouts(ref XkbLayout[string] layouts) {
		layoutStore.clear();
		foreach (lkey, layout; layouts) {
			TreeIter layI = layoutStore.append(null);
			layoutStore.setValue(layI, 0, lkey);
			layoutStore.setValue(layI, 1, layout.desc);
			layoutStore.setValue(layI, 2, lkey);
			foreach (vkey, vdesc; layout.variants) {
				TreeIter varI = layoutStore.append(layI);
				layoutStore.setValue(varI, 0, format("%s(%s)", lkey, vkey));
				layoutStore.setValue(varI, 1, vdesc);
				layoutStore.setValue(varI, 2, lkey);
				layoutStore.setValue(varI, 3, vkey);
			}
		}
	}

	void addToSettings(Settings settings) {
		auto iter = tree.getSelectedIter();
		if (iter is null)
			return;
		auto layList = settings.getValue("xkb-layouts").toDVal!(Tuple!(string, string)[]);
		layList ~= tuple(iter.getValueString(2), iter.getValueString(3));
		settings.setValue("xkb-layouts", layList.toVariant!());
	}
}

class SettingsApp {
	Settings settings;
	Settings wpsettings;

	@ById("sa_toplevel") ApplicationWindow toplevel;

	// Header
	@ById("sa_header_back") Button headerBack;
	@ById("sa_header_back_revealer") Revealer headerBackRevealer;
	@ById("sa_header_leaflet") Leaflet headerLeaflet;
	@ById("sa_header_bar_main") HeaderBar headerBarMain;
	@ById("sa_header_bar_sidebar") HeaderBar headerBarSidebar;

	// Window content
	@ById("sa_top_leaflet") Leaflet topLeaflet;
	@ById("sa_top_stack_sidebar") StackSidebar topStackSidebar;
	@ById("sa_top_stack") Stack topStack;

	mixin Glade!("/technology/unrelenting/numbernine/settings/settings.glade");
	mixin Css!("/technology/unrelenting/numbernine/settings/style.css", toplevel);

	// Do not include pages before setupSettings -- setup* are auto-called in order
	void setupSettings() {
		settings = new Settings("technology.unrelenting.numbernine.settings",
				"/technology/unrelenting/numbernine/settings/");
		wpsettings = new Settings("technology.unrelenting.numbernine.wallpaper",
				"/technology/unrelenting/numbernine/wallpaper/");
		settings.addOnChanged(delegate void(string, Settings) { callUpdates(); });
		wpsettings.addOnChanged(delegate void(string, Settings) { callUpdates(); });
	}

	mixin PageAppearance!();
	mixin PageMouse!();
	mixin PageKeyboard!();

	void callUpdates() {
		import std.algorithm : startsWith;

		static foreach (mem; __traits(allMembers, typeof(this)))
			static if (startsWith(mem, "update"))
				__traits(getMember, this, mem)();
	}

	void setupAnnotBinds() {
		import std.traits : getUDAs;

		static foreach (mem; __traits(allMembers, typeof(this)))
			static foreach (sett; getUDAs!(__traits(getMember, typeof(this), mem), Setting))
				settings.bind(sett.setting, __traits(getMember, this, mem), sett.prop, GSettingsBindFlags.DEFAULT);
	}

	void setupLeaflet() {
		// XXX: xml builder supports bindings, but glade erases them on saving
		// https://source.puri.sm/Librem5/libhandy/issues/12 -- probably an issue about this
		// TODO: recheck
		headerLeaflet.bindProperty("folded", headerBackRevealer, "reveal-child", GBindingFlags.SYNC_CREATE);
		headerLeaflet.bindProperty("folded", headerBarSidebar, "show-close-button", GBindingFlags.SYNC_CREATE);
		const bidi = GBindingFlags.BIDIRECTIONAL | GBindingFlags.SYNC_CREATE;
		headerLeaflet.bindProperty("visible-child-name", topLeaflet, "visible-child-name", bidi);
		headerLeaflet.bindProperty("mode-transition-duration", headerBackRevealer, "transition-duration", bidi);
		headerLeaflet.bindProperty("child-transition-duration", topLeaflet, "child-transition-duration", bidi);
		headerLeaflet.bindProperty("child-transition-type", topLeaflet, "child-transition-type", bidi);
		headerLeaflet.bindProperty("mode-transition-duration", topLeaflet, "mode-transition-duration", bidi);
		headerLeaflet.bindProperty("mode-transition-type", topLeaflet, "mode-transition-type", bidi);

		updateTitle();
		Signals.connect(topStack, "notify::visible-child", &updateTitle);

		headerBack.addOnClicked(delegate void(Button) {
			headerLeaflet.setVisibleChildName("sidebar");
		});
	}

	void setupRunFirstUpdate() {
		callUpdates();
	}

	void updateTitle() {
		import gobject.Value;

		auto title = scoped!Value("");
		topStack.childGetProperty(topStack.getVisibleChild(), "title", title);
		headerBarMain.setTitle(title.getString());
		headerLeaflet.setVisibleChildName("content");
	}
}

//__gshared extern(C) string[] rt_options = [ "trapExceptions=0" ];
__gshared extern (C) bool hdy_init(int* argc, char*** argv);

shared static this() {
	hdy_init(null, null);
}

int main(string[] args) {
	auto app = scoped!Application("technology.unrelenting.numbernine.settings", GApplicationFlags.FLAGS_NONE);
	app.addOnActivate(delegate(GioApplication a) {
		auto sett = new SettingsApp();
		sett.toplevel.setApplication(app);
		sett.toplevel.showAll();
	});
	return app.run(args);
}
