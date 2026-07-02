#!/usr/bin/env bash
set -euo pipefail

# Check that NmpCore.h declarations match the app's own Rust FFI implementations.
# This script detects drift between the C header and the app-local
# `extern "C"` symbols this repository owns and links Swift against.
#
# Scope of NmpCore.h — it declares two distinct symbol families:
#   1. App-local FFI — apps/nmp-app-podcast/src/ffi/ (owned + built in THIS repo)
#   2. Core NMP C-ABI — nmp_app_*, nmp_free_string, nmp_nip21_*,
#      nmp_signer_broker_* — provided by the pinned upstream runtime crate
#      (nmp-native-runtime, ADR-0069). These used to live in the standalone
#      `nmp-ffi` / `nmp-signer-broker` crates, which were DELETED when the
#      C-ABI surface folded into nmp-native-runtime/UniFFI. There is no longer
#      an `nmp-ffi` crate rev in Cargo.lock to diff against, so this script can
#      no longer scan an upstream source tree for those symbols.
#
# What this check authoritatively enforces (the load-bearing invariant):
#
#   ERROR — an app-local symbol (src/ffi/) is NOT declared in NmpCore.h.
#           This is real, silent drift: a missing declaration makes the symbol
#           unreachable from Swift with no compile/link error to catch it.
#
# The reverse direction (a header symbol with no app-local definition) is NOT
# treated as an error here: those are the core NMP C-ABI symbols listed above,
# owned by the pinned upstream runtime. Their existence is enforced elsewhere —
# the iOS/Android link step (Build and Test) fails loudly if any declared core
# symbol is absent from the linked archives. They are reported as informational.
#
# Header retirement: NmpCore.h is retained through the A0–A6 migration slices;
# when the C header is fully retired in A7 this script is removed with it.
# Tracking: podcast-player epic #597.
#
# NOTE: Uses only POSIX-compatible tools (grep -E, sed, awk) to support
#       BSD grep on macOS as well as GNU grep on Linux.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEADER_FILE="${REPO_ROOT}/App/Sources/Bridge/NmpCore.h"
FFI_DIR="${REPO_ROOT}/apps/nmp-app-podcast/src/ffi"

if [[ ! -f "$HEADER_FILE" ]]; then
    echo "Error: Header file not found: $HEADER_FILE"
    exit 1
fi

if [[ ! -d "$FFI_DIR" ]]; then
    echo "Error: FFI directory not found: $FFI_DIR"
    exit 1
fi

# ---------------------------------------------------------------------------
# Extract function names from a stream of Rust source lines.
#
# Matches the pattern:
#   pub [unsafe] extern "C" fn nmp_<name>(
#
# This is the reliable single-line form: the `fn nmp_` is always on the same
# line as `extern "C"` in well-formed Rust FFI code, regardless of how many
# other attributes (e.g. #[allow(...)]) may appear between #[no_mangle] and
# the function declaration.
# ---------------------------------------------------------------------------
extract_nmp_funcs() {
    grep -E 'pub[[:space:]]+(unsafe[[:space:]]+)?extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+nmp_' \
    | grep -oE 'fn[[:space:]]+nmp_[A-Za-z0-9_]+' \
    | sed 's/fn[[:space:]]*//'
}

# ---------------------------------------------------------------------------
# Extract function names from the C header.
# Pattern: any nmp_* name immediately before '('
# ---------------------------------------------------------------------------
echo "Extracting function names from C header..."
HEADER_FUNCS=$(
    grep -oE 'nmp_[A-Za-z0-9_]+[[:space:]]*\(' "$HEADER_FILE" \
    | sed 's/[[:space:]]*($//' \
    | sort | uniq
)

HEADER_COUNT=$(echo "$HEADER_FUNCS" | grep -cE '^nmp_' || true)
echo "  -> $HEADER_COUNT declarations found."

# ---------------------------------------------------------------------------
# Extract function names from LOCAL Rust FFI code.
# We scan apps/nmp-app-podcast/src/ffi/ excluding dedicated test files.
# ---------------------------------------------------------------------------
echo "Extracting function names from local Rust FFI code..."
LOCAL_FUNCS=$(
    find "$FFI_DIR" -name "*.rs" \
        ! -name "*_tests.rs" \
        ! -name "*_tests_ext.rs" \
        ! -name "*_test.rs" \
        -type f \
    | xargs grep -hE \
        'pub[[:space:]]+(unsafe[[:space:]]+)?extern[[:space:]]+"C"[[:space:]]+fn[[:space:]]+nmp_' \
        2>/dev/null \
    | extract_nmp_funcs \
    | sort | uniq
)

LOCAL_COUNT=$(echo "$LOCAL_FUNCS" | grep -cE '^nmp_' || true)
echo "  -> $LOCAL_COUNT local symbols found."

echo ""
echo "Summary:"
echo "  Header:      $HEADER_COUNT declarations"
echo "  Local FFI:   $LOCAL_COUNT app-owned symbols"
echo ""

# ---------------------------------------------------------------------------
# Load-bearing check: every app-local symbol MUST be declared in NmpCore.h.
# ---------------------------------------------------------------------------
ONLY_IN_LOCAL=$(
    comm -13 <(echo "$HEADER_FUNCS") <(echo "$LOCAL_FUNCS") \
    | grep -vE '^[[:space:]]*$' || true
)

# Informational: header symbols with no app-local definition — the core NMP
# C-ABI provided by the pinned upstream runtime (validated by the linker).
ONLY_IN_HEADER=$(
    comm -23 <(echo "$HEADER_FUNCS") <(echo "$LOCAL_FUNCS") \
    | grep -vE '^[[:space:]]*$' || true
)

EXIT_CODE=0

if [[ -n "$ONLY_IN_LOCAL" ]]; then
    echo "ERROR: Local app symbols (nmp-app-podcast/src/ffi) NOT declared in NmpCore.h:"
    echo "$ONLY_IN_LOCAL" | while read -r func; do
        echo "  - $func"
    done
    echo ""
    echo "  These are unreachable from Swift. Add the declaration to NmpCore.h."
    echo ""
    EXIT_CODE=1
fi

if [[ -n "$ONLY_IN_HEADER" ]]; then
    ONLY_IN_HEADER_COUNT=$(echo "$ONLY_IN_HEADER" | grep -cE '^nmp_' || true)
    echo "INFO: $ONLY_IN_HEADER_COUNT header declaration(s) are core NMP C-ABI symbols"
    echo "      provided by the pinned upstream runtime (nmp-native-runtime), not by"
    echo "      this repo. Their presence in the linked archives is enforced by the"
    echo "      iOS/Android link step, not by this script."
    echo ""
fi

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✓ Every app-local FFI symbol is declared in NmpCore.h."
fi

exit $EXIT_CODE
