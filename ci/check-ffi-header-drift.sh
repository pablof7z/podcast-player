#!/usr/bin/env bash
set -euo pipefail

# Check that NmpCore.h declarations match Rust FFI implementations.
# This script detects drift between the C header and the Rust extern "C" symbols.

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

# Extract function names from the C header.
# Pattern: nmp_app_* function declarations
echo "Extracting function names from C header..."
HEADER_FUNCS=$(
    grep -oP 'nmp_app_\w+(?=\s*\()' "$HEADER_FILE" | sort | uniq
)

# Extract function names from Rust FFI code.
# We need to find all `#[no_mangle] pub extern "C" fn nmp_app_*` in non-test files.
echo "Extracting function names from Rust FFI code..."
RUST_FUNCS=$(
    # Find all Rust files in the FFI directory, excluding test files
    find "$FFI_DIR" -name "*.rs" \
        ! -name "*_tests.rs" \
        ! -name "*_tests_ext.rs" \
        ! -name "*_test.rs" \
        -type f \
    | while read -r file; do
        # Skip test modules with #[cfg(test)]
        if grep -q "#\[cfg(test)\]" "$file"; then
            # Filter out lines inside #[cfg(test)] blocks
            awk '
                /^#\[cfg\(test\)\]/ { in_test = 1; next }
                /^#\[/ && !/^#\[cfg\(test\)\]/ { in_test = 0 }
                !in_test && /^#\[no_mangle\]/ {
                    # Read next line to get the function declaration
                    getline next_line
                    if (next_line ~ /pub.*extern.*"C".*fn nmp_app_/) {
                        match(next_line, /fn (nmp_app_\w+)/, arr)
                        if (arr[1]) print arr[1]
                    }
                }
            ' "$file"
        else
            # No test module, just extract nmp_app_* functions
            grep -oP '#\[no_mangle\]\s*(?:pub\s+)?(?:unsafe\s+)?(?:extern\s+"C"\s+)?fn\s+\K(nmp_app_\w+)' "$file" || true
        fi
    done | sort | uniq
)

echo ""
echo "C Header declarations ($(echo "$HEADER_FUNCS" | wc -l) functions):"
echo "$HEADER_FUNCS" | head -10
echo "..."
echo ""

echo "Rust FFI implementations ($(echo "$RUST_FUNCS" | wc -l) functions):"
echo "$RUST_FUNCS" | head -10
echo "..."
echo ""

# Find differences
ONLY_IN_HEADER=$(comm -23 <(echo "$HEADER_FUNCS") <(echo "$RUST_FUNCS"))
ONLY_IN_RUST=$(comm -13 <(echo "$HEADER_FUNCS") <(echo "$RUST_FUNCS"))

EXIT_CODE=0

if [[ -n "$ONLY_IN_HEADER" ]]; then
    echo "ERROR: Functions declared in header but NOT found in Rust code:"
    echo "$ONLY_IN_HEADER" | while read -r func; do
        echo "  - $func"
    done
    echo ""
    EXIT_CODE=1
fi

if [[ -n "$ONLY_IN_RUST" ]]; then
    echo "ERROR: Functions implemented in Rust but NOT declared in header:"
    echo "$ONLY_IN_RUST" | while read -r func; do
        echo "  - $func"
    done
    echo ""
    EXIT_CODE=1
fi

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✓ FFI header is in sync with Rust FFI implementations."
fi

exit $EXIT_CODE
