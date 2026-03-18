#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift_tests_dir="$repo_root/VibeScribeUITests"
md_file="$repo_root/VibeScribeUITests/TEST_CASES.md"
aid_file="$repo_root/VibeScribe/AccessibilityIdentifiers.swift"

errors=0

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    errors=$((errors + 1))
}

file_has_exact_line() {
    local needle="$1"
    local file="$2"
    grep -Fxq -- "$needle" "$file"
}

matches_out_of_scope() {
    local id="$1"
    local token prefix
    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        if [[ "$token" == *"*" ]]; then
            prefix="${token%\*}"
            if [[ "$id" == "$prefix"* ]]; then
                return 0
            fi
        elif [[ "$id" == "$token" ]]; then
            return 0
        fi
    done < "$tmpdir/out_of_scope_ids.txt"
    return 1
}

shopt -s nullglob
swift_files=("$swift_tests_dir"/*.swift)
shopt -u nullglob

if [[ ${#swift_files[@]} -eq 0 ]]; then
    fail "No Swift UI test files found in $swift_tests_dir"
fi

for file in "$md_file" "$aid_file" "${swift_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        fail "Missing required file: $file"
    fi
done

if [[ $errors -gt 0 ]]; then
    exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

rg -o 'func test[A-Za-z0-9_]+' "${swift_files[@]}" \
    | awk '{print $2}' \
    | sort -u \
    | sed '/^$/d' > "$tmpdir/swift_methods.txt"

sed -n 's/^- Method: `\(test[A-Za-z0-9_]*\)`/\1/p' "$md_file" \
    | sort -u \
    | sed '/^$/d' > "$tmpdir/markdown_methods.txt"

swift_method_count="$(wc -l < "$tmpdir/swift_methods.txt" | tr -d ' ')"
markdown_method_count="$(wc -l < "$tmpdir/markdown_methods.txt" | tr -d ' ')"

if [[ "$swift_method_count" -ne "$markdown_method_count" ]]; then
    fail "Method count mismatch: Swift=$swift_method_count, Markdown=$markdown_method_count"
fi

comm -23 "$tmpdir/swift_methods.txt" "$tmpdir/markdown_methods.txt" > "$tmpdir/missing_in_markdown.txt"
comm -13 "$tmpdir/swift_methods.txt" "$tmpdir/markdown_methods.txt" > "$tmpdir/stale_in_markdown.txt"

if [[ -s "$tmpdir/missing_in_markdown.txt" ]]; then
    fail "Markdown is missing test methods:\n$(cat "$tmpdir/missing_in_markdown.txt")"
fi
if [[ -s "$tmpdir/stale_in_markdown.txt" ]]; then
    fail "Markdown contains stale test methods:\n$(cat "$tmpdir/stale_in_markdown.txt")"
fi

header_total="$(
    sed -n 's/^> \*\*\([0-9][0-9]*\) automated UI tests\*\*.*/\1/p' "$md_file" \
        | head -n 1
)"
if [[ -z "$header_total" ]]; then
    fail "Cannot parse header test count from TEST_CASES.md"
elif [[ "$header_total" -ne "$swift_method_count" ]]; then
    fail "Header test count mismatch: Header=$header_total, Swift=$swift_method_count"
fi

awk '
    /final class [A-Za-z0-9_]+Tests:/ {
        class_name = $3
        sub(/:.*/, "", class_name)
        order[++count] = class_name
        class_tests[class_name] = 0
    }
    /func test[A-Za-z0-9_]+\(/ && class_name != "" {
        class_tests[class_name]++
    }
    END {
        for (i = 1; i <= count; i++) {
            print order[i] " " class_tests[order[i]]
        }
    }
' "${swift_files[@]}" | sort > "$tmpdir/swift_class_counts.txt"

awk -F'|' '
    /^\| `[^`]+Tests` \|/ {
        class_name = $2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", class_name)
        gsub(/`/, "", class_name)
        class_count = $5
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", class_count)
        print class_name " " class_count
    }
' "$md_file" | sort > "$tmpdir/markdown_class_counts.txt"

if ! diff -u "$tmpdir/swift_class_counts.txt" "$tmpdir/markdown_class_counts.txt" > "$tmpdir/class_counts.diff"; then
    fail "Per-class test counts mismatch:\n$(cat "$tmpdir/class_counts.diff")"
fi

sed -n 's/^[[:space:]]*static let \([A-Za-z0-9_]*\) = ".*"/\1/p' "$aid_file" \
    | sort -u > "$tmpdir/app_declared_ids.txt"

rg -n 'accessibilityIdentifier\(' "$repo_root/VibeScribe" -S \
    | rg -o 'AccessibilityID\.[A-Za-z0-9_]+' -N \
    | sed 's/AccessibilityID\.//' \
    | sort -u > "$tmpdir/attached_ids.txt"

sed -n 's/^[[:space:]]*static let \([A-Za-z0-9_]*\) = ".*"/\1/p' "${swift_files[@]}" \
    | sort -u > "$tmpdir/test_mirror_ids.txt"

awk '
    /Elements intentionally out of fast UI automation scope:/ { in_scope = 1; next }
    in_scope && /^## / { in_scope = 0 }
    in_scope { print }
' "$md_file" \
    | rg -o '`[^`]+`' -N \
    | sed 's/^`//; s/`$//' \
    | sort -u > "$tmpdir/out_of_scope_ids.txt" || true

while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! file_has_exact_line "$id" "$tmpdir/app_declared_ids.txt"; then
        fail "UI test AID mirror ID is not declared in app AccessibilityID: $id"
    fi
    if ! file_has_exact_line "$id" "$tmpdir/attached_ids.txt" && ! matches_out_of_scope "$id"; then
        fail "UI test AID mirror ID is not attached in views and not marked out-of-scope: $id"
    fi
done < "$tmpdir/test_mirror_ids.txt"

while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! file_has_exact_line "$id" "$tmpdir/test_mirror_ids.txt" && ! matches_out_of_scope "$id"; then
        fail "Attached accessibility ID is neither test-mirrored nor out-of-scope in TEST_CASES.md: $id"
    fi
done < "$tmpdir/attached_ids.txt"

while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    if [[ "$token" == *"*" ]]; then
        prefix="${token%\*}"
        if ! rg -q "^${prefix}" "$tmpdir/attached_ids.txt"; then
            fail "Out-of-scope wildcard has no matching attached IDs: $token"
        fi
    elif ! file_has_exact_line "$token" "$tmpdir/attached_ids.txt" && ! file_has_exact_line "$token" "$tmpdir/app_declared_ids.txt"; then
        fail "Out-of-scope ID is unknown (not declared/attached): $token"
    fi
done < "$tmpdir/out_of_scope_ids.txt"

if [[ $errors -gt 0 ]]; then
    printf '\nValidation failed with %d error(s).\n' "$errors" >&2
    exit 1
fi

printf 'Validation passed.\n'
printf 'Methods: %s\n' "$swift_method_count"
printf 'Class count map: %s entries\n' "$(wc -l < "$tmpdir/swift_class_counts.txt" | tr -d ' ')"
printf 'Attached accessibility IDs: %s\n' "$(wc -l < "$tmpdir/attached_ids.txt" | tr -d ' ')"
printf 'Out-of-scope IDs in markdown: %s\n' "$(wc -l < "$tmpdir/out_of_scope_ids.txt" | tr -d ' ')"
