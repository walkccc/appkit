# The product's words: one tree, every surface.
#
#   store/metadata/app/<language>.json        name, subtitle, short description
#   store/metadata/version/<language>.json    description, keywords, promo text
#   store/metadata/changelog/<version>/<language>.md   what changed, per release
#   store/metadata/pages/<page>/<language>.md          privacy, support, terms
#
# The App Store calls this metadata, Play calls it a listing, a website calls it
# a page. Same words. What each surface takes:
#
#   iOS      name, subtitle, keywords, description, whatsNew, the page URLs
#   Android  title, short + full description, release notes, the page URLs
#
# The pages a listing LINKS to are here too, and are served from the product's
# own site rather than published by appkit.

# --- the changelog ----------------------------------------------------------
#
# A version is a folder: the stores take the one being shipped, the web renders
# all of them. A single whatsNew field has no history. A repo with no changelog/
# keeps using that field, so adoption is incremental.

# The newest version in the changelog, by sort order rather than by mtime.
copy_latest_version() {
  local dir="$1/changelog"
  [[ -d "$dir" ]] || return 1
  python3 - "$dir" <<'PY'
import pathlib, sys

versions = [p.name for p in pathlib.Path(sys.argv[1]).iterdir() if p.is_dir()]
if not versions:
    sys.exit(1)


def key(version):
    # 1.10.0 is newer than 1.9.0; a plain string sort says otherwise.
    return [int(part) if part.isdigit() else part for part in version.split(".")]


print(sorted(versions, key=key)[-1])
PY
}

# What's new for one language at one version, falling back to the version file's
# own whatsNew when there is no changelog folder.
copy_whats_new() {
  local dir="$1" version="$2" language="$3" path
  path="$dir/changelog/$version/$language.md"
  if [[ -f "$path" ]]; then
    cat "$path"
    return 0
  fi
  python3 - "$dir/version/$language.json" <<'PY'
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
if path.exists():
    sys.stdout.write(json.loads(path.read_text()).get("whatsNew", ""))
PY
}

# --- coverage ---------------------------------------------------------------
#
# The check nobody does by hand: every language the manifest declares has every
# field, in every surface. A missing one does not fail a push — the store simply
# shows the previous release's words, or English, and nobody notices for months.
copy_coverage() {
  local dir="$1" languages="$2" version="$3"
  python3 - "$dir" "$languages" "$version" <<'PY'
import json, pathlib, sys

root, languages, version = pathlib.Path(sys.argv[1]), sys.argv[2].split(), sys.argv[3]
gaps = []


def has(path, field=None):
    if not path.exists():
        return False
    if field is None:
        return bool(path.read_text().strip())
    return bool(json.loads(path.read_text()).get(field))


for language in languages:
    for field in ("name",):
        if not has(root / "app" / f"{language}.json", field):
            gaps.append(f"app/{language}: no {field}")
    for field in ("description",):
        if not has(root / "version" / f"{language}.json", field):
            gaps.append(f"version/{language}: no {field}")

    if (root / "changelog").is_dir():
        note = root / "changelog" / version / f"{language}.md"
        if not has(note):
            gaps.append(f"changelog/{version}/{language}.md: missing")

    if (root / "pages").is_dir():
        for page in sorted(p for p in (root / "pages").iterdir() if p.is_dir()):
            if not has(page / f"{language}.md"):
                gaps.append(f"pages/{page.name}/{language}.md: missing")

for gap in gaps:
    print(f"  {gap}", file=sys.stderr)
print(f"{len(languages)} language(s) checked")
sys.exit(1 if gaps else 0)
PY
}

# --- export -----------------------------------------------------------------
#
# One JSON with everything, for a surface that is not a store: a web repo
# imports it and renders its own /changelog, /privacy and /support from the same
# words the listings carry. Generated, never hand-edited, so the site cannot
# drift from the store.
copy_export() {
  local dir="$1" languages="$2" out="$3"
  python3 - "$dir" "$languages" "$out" <<'PY'
import json, pathlib, sys

root, languages, out = pathlib.Path(sys.argv[1]), sys.argv[2].split(), pathlib.Path(sys.argv[3])


def read_json(path):
    return json.loads(path.read_text()) if path.exists() else {}


def read_text(path):
    return path.read_text().strip() if path.exists() else ""


def version_key(version):
    return [int(part) if part.isdigit() else part for part in version.split(".")]


bundle = {"languages": languages, "app": {}, "changelog": [], "pages": {}}

for language in languages:
    app = read_json(root / "app" / f"{language}.json")
    version = read_json(root / "version" / f"{language}.json")
    bundle["app"][language] = {
        "name": app.get("name", ""),
        "subtitle": app.get("subtitle", ""),
        "shortDescription": app.get("shortDescription") or app.get("subtitle", ""),
        "description": version.get("description", ""),
    }

changelog = root / "changelog"
if changelog.is_dir():
    for folder in sorted((p for p in changelog.iterdir() if p.is_dir()),
                         key=lambda p: version_key(p.name), reverse=True):
        bundle["changelog"].append({
            "version": folder.name,
            "notes": {language: read_text(folder / f"{language}.md") for language in languages},
        })

pages = root / "pages"
if pages.is_dir():
    for folder in sorted(p for p in pages.iterdir() if p.is_dir()):
        bundle["pages"][folder.name] = {
            language: read_text(folder / f"{language}.md") for language in languages
        }

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(bundle, ensure_ascii=False, indent=2) + "\n")
print(f"exported {len(languages)} language(s), {len(bundle['changelog'])} release(s), "
      f"{len(bundle['pages'])} page(s) → {out}")
PY
}
