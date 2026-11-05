#!/bin/bash
# Writes a server list (JSON file) into every Server Control widget in the
# running Plasma session. A stand-in for the settings UI until phase 3.
#
# Usage: tools/set-config.sh FILE.json
#   e.g. tools/set-config.sh examples/demo-local.json
set -euo pipefail

file=${1:?usage: tools/set-config.sh FILE.json}
plugin=com.github.TisiNen.servercontrol

# Fails with a readable message if the file isn't valid JSON. The result is
# the compact JSON as a JavaScript string literal.
literal=$(python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except ValueError as e:
    sys.exit(f"{sys.argv[1]}: not valid JSON: {e}")
print(json.dumps(json.dumps(data)))
' "$file")

qdbus=$(command -v qdbus6 || command -v qdbus-qt6 || command -v qdbus || true)
if [[ -z $qdbus ]]; then
    echo "qdbus6 not found (package qt6-qttools or qdbus-qt6)" >&2
    exit 1
fi

script="
let n = 0;
for (const c of desktops().concat(panels())) {
    for (const w of c.widgets('$plugin')) {
        w.currentConfigGroup = ['General'];
        w.writeConfig('servers', $literal);
        w.reloadConfig();
        n++;
    }
}
print('Updated ' + n + ' Server Control widget(s)');
"
"$qdbus" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script"
