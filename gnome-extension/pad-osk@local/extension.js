// D-Bus bridge so `pad` can show GNOME's on-screen keyboard without a touchscreen.
// busctl --user call org.gnome.Shell /org/local/PadOsk org.local.PadOsk Toggle
import Gio from 'gi://Gio';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const IFACE = `<node>
  <interface name="org.local.PadOsk">
    <method name="Toggle"><arg type="b" direction="out" name="visible"/></method>
    <method name="Show"/>
    <method name="Hide"/>
  </interface>
</node>`;

export default class PadOskExtension extends Extension {
    enable() {
        this._settings = new Gio.Settings({schema_id: 'org.gnome.desktop.a11y.applications'});
        this._dbus = Gio.DBusExportedObject.wrapJSObject(IFACE, this);
        this._dbus.export(Gio.DBus.session, '/org/local/PadOsk');
    }

    disable() {
        this._dbus?.unexport();
        this._dbus = null;
        this._settings = null;
    }

    Show() {
        // The keyboard object only exists while the a11y setting is on.
        if (!this._settings.get_boolean('screen-keyboard-enabled'))
            this._settings.set_boolean('screen-keyboard-enabled', true);
        Main.keyboard.open(Main.layoutManager.focusIndex);
    }

    Hide() {
        Main.keyboard.close();
    }

    Toggle() {
        if (Main.keyboard.visible) {
            this.Hide();
            return false;
        }
        this.Show();
        return true;
    }
}
