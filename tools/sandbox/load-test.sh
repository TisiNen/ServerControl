#!/bin/bash
# Load test for the Server Control plasmoid: runs it in a Podman sandbox with no
# network and fails if QML errors or warnings refer to files in the package.
#
# Usage: tools/sandbox/load-test.sh [options] [package-dir]
#   -v, --verbose   print the full plasmoidviewer log
#   --config        print the applet config plasmoidviewer wrote
#   --rebuild       rebuild the image without cache
#   --self-test     check that the test catches a deliberately broken QML file
#   --servers FILE  preset the `servers` config key from a JSON file
#                   (use only harmless commands: true, false, echo, sleep)
#   package-dir     defaults to ./package in the repository root
set -euo pipefail

SANDBOX_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$SANDBOX_DIR/../.." && pwd)
IMAGE=servercontrol-sandbox
ENGINE=${CONTAINER_ENGINE:-podman}

verbose=0
dump_config=0
rebuild=0
self_test=0
servers_file=
package=$REPO_DIR/package

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose) verbose=1 ;;
        --config) dump_config=1 ;;
        --rebuild) rebuild=1 ;;
        --self-test) self_test=1 ;;
        --servers) servers_file=$(realpath "${2:?--servers needs a file}"); shift ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) package=$1 ;;
    esac
    shift
done

package=$(cd "$package" && pwd)

# Build the image if it is missing; otherwise a cached build is a near no-op
# that still picks up changes to the Containerfile or entrypoint.
build_args=(-q -t "$IMAGE")
[[ $rebuild -eq 1 ]] && build_args+=(--no-cache)
if ! "$ENGINE" image exists "$IMAGE" 2>/dev/null; then
    echo "Building $IMAGE image (first run, takes a few minutes)..."
fi
"$ENGINE" build "${build_args[@]}" "$SANDBOX_DIR" >/dev/null

run_test() {
    # keep-id maps the host user to the container user, so the package is
    # readable even when its directory is private (e.g. mktemp -d).
    "$ENGINE" run --rm --network none --userns=keep-id \
        -e VERBOSE="$verbose" -e DUMP_CONFIG="$dump_config" \
        -v "$1:/package:ro,Z" \
        "$IMAGE"
}

# Copies the package to a temp dir. The caller removes it.
copy_package() {
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    cp -r "$package/." "$tmp/"
}

# plasmoidviewer discards a preset applet config, so a test config becomes
# the default of the `servers` key in a copy of the package instead.
if [[ -n $servers_file ]]; then
    copy_package
    python3 - "$servers_file" "$tmp/contents/config/main.xml" <<'PY'
import json, sys
from xml.sax.saxutils import escape
text = open(sys.argv[1]).read()
try:
    servers = json.dumps(json.loads(text))
except ValueError:
    servers = text.strip()  # invalid JSON on purpose, to test the fallback
path = sys.argv[2]
xml = open(path).read()
old = '<entry name="servers" type="String">\n      <default>[]</default>'
if old not in xml:
    sys.exit("main.xml: servers default not found")
open(path, "w").write(xml.replace(old, old.replace("[]", escape(servers))))
PY
    package=$tmp
fi

if [[ $self_test -eq 1 ]]; then
    copy_package
    main=$tmp/contents/ui/main.qml
    # A reference to an undefined type must be reported.
    printf 'import QtQuick\nItem {\n    ThisTypeDoesNotExist {}\n}\n' >"$main"
    output=$(run_test "$tmp") && rc=0 || rc=$?
    echo "$output"
    # Require the actual QML report, not just any failure (e.g. a mount problem).
    if [[ $rc -eq 0 ]] || ! grep -q "ThisTypeDoesNotExist" <<<"$output"; then
        echo "SELF-TEST FAILED: broken QML was not detected"
        exit 1
    fi
    echo "SELF-TEST PASSED: broken QML was detected"
    exit 0
fi

run_test "$package"
