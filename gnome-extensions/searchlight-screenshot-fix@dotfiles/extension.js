// GNOME's "Take a Screenshot" search result does not open the screenshot UI
// right away: it waits for the overview's 'hidden' signal, so the overview
// itself does not end up in the capture. SearchLightNG runs the search without
// ever showing the overview, so that signal only fires the next time the app
// grid is opened and closed. When the overview is not open, open the
// screenshot UI ourselves once the SearchLightNG popup has faded out.

import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Screenshot from 'resource:///org/gnome/shell/ui/screenshot.js';
import * as SystemActions from 'resource:///org/gnome/shell/misc/systemActions.js';

// Long enough for SearchLightNG's hide animation (100 ms in our config) to finish.
const OPEN_DELAY_MS = 250;

export default class SearchLightScreenshotFix extends Extension {
    enable() {
        const actions = SystemActions.getDefault();
        const original = actions.activateScreenshotUI;
        this._actions = actions;
        this._original = original;

        actions.activateScreenshotUI = (...args) => {
            if (Main.overview.visible || Main.overview.animationInProgress)
                return original.apply(actions, args);

            if (this._timeoutId)
                return undefined;

            this._timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, OPEN_DELAY_MS, () => {
                this._timeoutId = 0;
                Screenshot.showScreenshotUI();
                return GLib.SOURCE_REMOVE;
            });
            return undefined;
        };
    }

    disable() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
        }
        if (this._actions) {
            this._actions.activateScreenshotUI = this._original;
            this._actions = null;
            this._original = null;
        }
    }
}
