#!/usr/bin/osascript -l JavaScript

const systemEvents = Application("System Events");
const simulator = systemEvents.processes.byName("Simulator");
const window = simulator.windows[0];

function safe(getter, fallback = "") {
    try { return getter(); } catch (_) { return fallback; }
}

function describe(element) {
    const role = safe(() => element.role());
    if (["AXButton", "AXTextField", "AXSecureTextField", "AXRadioButton", "AXCheckBox"].includes(role)) {
        const title = safe(() => element.title());
        const description = safe(() => element.description());
        const value = safe(() => element.value());
        const position = safe(() => element.position(), []);
        const size = safe(() => element.size(), []);
        console.log(JSON.stringify({ role, title, description, value, position, size }));
    }

}

describe(window);
for (const element of safe(() => window.entireContents(), [])) describe(element);
