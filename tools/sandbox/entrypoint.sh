#!/bin/bash
# Runs inside the sandbox container. Starts Xvfb, runs plasmoidviewer on the
# package mounted at /package for a few seconds and reports QML problems.
#
# Env:
#   RUN_SECONDS  how long plasmoidviewer runs (default 15)
#   VERBOSE=1    print the full plasmoidviewer log
#   DUMP_CONFIG=1  print the applet config plasmoidviewer wrote
set -u

PACKAGE=/package
RUN_SECONDS=${RUN_SECONDS:-15}
LOG=$(mktemp)

if [[ ! -f $PACKAGE/metadata.json ]]; then
    echo "FAIL: $PACKAGE/metadata.json not found (is the package mounted?)"
    exit 2
fi

mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

Xvfb "$DISPLAY" -screen 0 1280x1024x24 -nolisten tcp >/dev/null 2>&1 &
for _ in $(seq 50); do
    [[ -S /tmp/.X11-unix/X${DISPLAY#:} ]] && break
    sleep 0.1
done
if [[ ! -S /tmp/.X11-unix/X${DISPLAY#:} ]]; then
    echo "FAIL: Xvfb did not start"
    exit 2
fi

dbus-run-session -- timeout "$RUN_SECONDS" plasmoidviewer -a "$PACKAGE" >"$LOG" 2>&1
rc=$?

if [[ ${VERBOSE:-0} == 1 ]]; then
    echo "----- full plasmoidviewer log -----"
    cat "$LOG"
    echo "-----------------------------------"
fi

if [[ ${DUMP_CONFIG:-0} == 1 ]]; then
    for f in ~/.config/plasmoidviewer*; do
        [[ -e $f ]] || continue
        echo "----- $f -----"
        cat "$f"
    done
fi

# Problems that point at files in the package, plus applet load failures that
# don't carry a file path.
problems=$(grep -E "$PACKAGE/|error when loading applet|Error loading (QML|the applet)|Could not (find|load) (applet|plugin)" "$LOG" | sort -u)

status=0
if [[ -n $problems ]]; then
    echo "QML problems:"
    echo "$problems"
    status=1
fi
# timeout exits with 124 when it had to stop plasmoidviewer, i.e. the viewer
# was still running. Anything else means it crashed or quit early.
if [[ $rc -ne 124 ]]; then
    echo "FAIL: plasmoidviewer exited early with code $rc (crash or startup failure)"
    [[ ${VERBOSE:-0} == 1 ]] || tail -n 30 "$LOG"
    status=1
fi

if [[ $status -eq 0 ]]; then
    echo "PASS: widget loaded without QML errors (${RUN_SECONDS}s run)"
fi
exit $status
