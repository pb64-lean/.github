#!/usr/bin/env bash
# assurance-scan.sh <tree> [--excludes "dir1 dir2 ..."]
#
# Static assurance scan for a Lean/Bazel repository. Produces a classified
# report (assurance-report.md in the invoking directory, mirrored to
# $GITHUB_STEP_SUMMARY when set):
#
#   FAIL          sorry / admit in .lean sources (outside excluded dirs,
#                 ignoring line comments)
#   INFORMATIONAL axiom, unsafe, @[extern], partial def inventories;
#                 handwritten C/C++ files; vendored third_party trees
#   PINS          toolchain and dependency revision report
#
# Exit code 1 iff proof holes were found; the informational classes never
# fail the scan — they are an auditable inventory, not a lint.
set -euo pipefail

tree="${1:?usage: assurance-scan.sh <tree> [--excludes \"dir1 dir2\"]}"
shift || true

excludes="third_party bazel-* .lake .git"
while [ $# -gt 0 ]; do
  case "$1" in
    --excludes)
      excludes="$excludes ${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

report="$(pwd)/assurance-report.md"
: > "$report"
cd "$tree"

grep_excludes=()
find_prunes=()
set -f
for e in $excludes; do
  [ -n "$e" ] || continue
  grep_excludes+=("--exclude-dir=$e")
  find_prunes+=(-o -name "$e")
done
set +f

# grep over .lean sources honoring excludes; prints file:line:content with
# leading ./ stripped; exits 0 even on no match.
lean_grep() {
  grep -rInE "$1" --include='*.lean' "${grep_excludes[@]}" . 2>/dev/null \
    | sed 's|^\./||' || true
}

# find honoring excludes-as-prunes
scan_find() {
  find . \( -false "${find_prunes[@]}" \) -prune -o "$@" -print 2>/dev/null \
    | sed 's|^\./||' || true
}

emit() { printf '%s\n' "$*" >> "$report"; }

count_lines() {
  if [ -z "$1" ]; then
    echo 0
  else
    printf '%s\n' "$1" | wc -l | tr -d ' '
  fi
}

# Render a match list as a collapsible markdown section.
emit_class() {
  local title="$1" matches="$2"
  local n
  n=$(count_lines "$matches")
  emit ""
  emit "<details><summary><b>${title}</b> — ${n} occurrence(s)</summary>"
  emit ""
  if [ -n "$matches" ]; then
    emit '```'
    printf '%s\n' "$matches" >> "$report"
    emit '```'
  else
    emit "_none_"
  fi
  emit ""
  emit "</details>"
}

# ── Classes ──────────────────────────────────────────────────────────────────

# Proof holes: sorry/admit as standalone tokens, dropping lines whose content
# starts with a line comment. Block-comment mentions may still match; that is
# the safe failure direction (reword the comment).
holes=$(lean_grep '\b(sorry|admit)\b' \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*--' || true)

theorems=$(lean_grep '(^|[[:space:]])(theorem|lemma)[[:space:]]')
axioms=$(lean_grep '(^|[[:space:]])axiom[[:space:]]')
unsafes=$(lean_grep '(^|[[:space:]])unsafe[[:space:]]')
externs=$(lean_grep '@\[extern')
partials=$(lean_grep '\bpartial[[:space:]]+(def|instance)\b')

c_files=$(scan_find -type f \( -name '*.c' -o -name '*.h' -o -name '*.cc' \
  -o -name '*.cpp' -o -name '*.hpp' \))
c_inventory=""
if [ -n "$c_files" ]; then
  while IFS= read -r f; do
    c_inventory+="$f ($(wc -l < "$f" | tr -d ' ') lines)"$'\n'
  done <<< "$c_files"
  c_inventory="${c_inventory%$'\n'}"
fi

vendored=""
while IFS= read -r d; do
  [ -n "$d" ] || continue
  files=$(find "$d" -type f | wc -l | tr -d ' ')
  kb=$(du -sk "$d" | cut -f1)
  vendored+="${d#./} (${files} files, ${kb} KB)"$'\n'
done < <(find . -maxdepth 3 -type d -name third_party -not -path '*/bazel-*/*' 2>/dev/null)
vendored="${vendored%$'\n'}"

# ── Report ───────────────────────────────────────────────────────────────────

repo_label="${GITHUB_REPOSITORY:-$(basename "$(pwd)")}"
emit "# Assurance report — ${repo_label}"
emit ""
emit "Excluded from source classes: \`${excludes}\` (vendored code is inventoried separately)."
emit ""
emit "| Class | Count | Policy |"
emit "| --- | --- | --- |"
emit "| \`sorry\` / \`admit\` | $(count_lines "$holes") | **fails the scan** |"
emit "| \`theorem\` / \`lemma\` | $(count_lines "$theorems") | counted |"
emit "| \`axiom\` | $(count_lines "$axioms") | listed |"
emit "| \`unsafe\` | $(count_lines "$unsafes") | listed |"
emit "| \`@[extern]\` (FFI) | $(count_lines "$externs") | listed |"
emit "| \`partial def/instance\` | $(count_lines "$partials") | listed |"
emit "| handwritten C/C++ files | $(count_lines "$c_inventory") | inventoried |"
emit "| vendored trees | $(count_lines "$vendored") | inventoried |"

emit_class "Proof holes (sorry / admit)" "$holes"
emit_class "Theorems and lemmas" "$theorems"
emit_class "Axioms" "$axioms"
emit_class "Unsafe declarations" "$unsafes"
emit_class "FFI surface (@[extern])" "$externs"
emit_class "Partial definitions (unproven termination)" "$partials"
emit_class "Handwritten C/C++" "$c_inventory"
emit_class "Vendored trees" "$vendored"

# ── Pins report ──────────────────────────────────────────────────────────────

emit ""
emit "## Toolchain and dependency pins"
emit ""
emit '```'

if [ -f .bazelversion ]; then
  emit "bazel:            $(cat .bazelversion)"
else
  emit "bazel:            n/a"
fi

while IFS= read -r f; do
  rev=$(grep -o '"rev"[^,}]*' "$f" | head -1 | tr -d '" ' | cut -d: -f2 || true)
  emit "nixpkgs:          ${rev:-unparsed}  ($f)"
done < <(scan_find -type f -name 'nixpkgs.json')

while IFS= read -r f; do
  lrev=$(grep -oE 'leanUpstreamStdRev = "[0-9a-f]+"' "$f" | grep -oE '[0-9a-f]{7,}' || true)
  lver=$(grep -oE 'version = "[^"]+"' "$f" | head -1 | cut -d'"' -f2 || true)
  emit "lean:             ${lver:-unparsed} @ ${lrev:-unparsed}  ($f)"
done < <(scan_find -type f -name 'nixpkgs.nix')

if [ -f MODULE.bazel ]; then
  hacl=$(grep -oE 'hacl-star-[0-9a-f]+' MODULE.bazel | head -1 | sed 's/hacl-star-//' || true)
  hacl_sha=$(grep -B2 -A8 'hacl-star/archive' MODULE.bazel | grep -oE 'sha256 = "[^"]+"' | head -1 | cut -d'"' -f2 || true)
  if [ -n "$hacl" ]; then
    emit "hacl-star:        ${hacl} (sha256 ${hacl_sha:-unparsed})"
  fi
  emit "bazel_dep pins:"
  grep -E '^bazel_dep\(' MODULE.bazel | sed 's/^/  /' >> "$report" || true
  gosdk=$(grep -oE 'go_sdk\.download\(version = "[^"]+"' MODULE.bazel | cut -d'"' -f2 || true)
  [ -n "$gosdk" ] && emit "go sdk:           ${gosdk}"
fi

while IFS= read -r f; do
  emit "lean-toolchain:   $(cat "$f")  ($f)"
done < <(scan_find -type f -name 'lean-toolchain')

emit '```'

# ── Publish + verdict ────────────────────────────────────────────────────────

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$report" >> "$GITHUB_STEP_SUMMARY"
fi

if [ -n "$holes" ]; then
  echo "ASSURANCE FAIL: sorry/admit present:" >&2
  printf '%s\n' "$holes" >&2
  exit 1
fi
echo "assurance scan clean: no sorry/admit outside excluded directories"
