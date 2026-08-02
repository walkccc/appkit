# The listing text: one tracked tree per app, two stores read out of it.
#
#   store/metadata/app/<language>.json      name, subtitle, short description,
#                                           the URLs — the things that outlive
#                                           any one release
#   store/metadata/version/<language>.json  description, keywords, promo text,
#                                           what's new
#   store/metadata/changelog/<version>/<language>.md   what changed, per release
#   store/metadata/pages/<page>/<language>.md          privacy, support, terms
#
# Keyed by the CAPTURE language, never a store's spelling of it: `ja` is `ja` on
# the App Store and `ja-JP` on Play, and a tree keyed by either serves only that
# one. The emitters rename on the way out.
#
# A file named for a STORE locale wins for that row — es-ES and es-MX are
# photographed once and written twice ("vídeo"/"video", "móvil"/"celular").
#
# Neither store's layout is the tracked one; both are materialised at push time
# and thrown away.

# store/changelog/<version>/<language>.md wins over the version file's whatsNew
# for the release being pushed.
#
# Folded into the STAGED tree, never the tracked one — a push must not edit what
# it is publishing, and the first version of this did exactly that.
_fold_changelog_asc() {
  local version="$1" src="$2" dst="$3" rows=("${@:4}")
  [[ -d "$src/changelog/$version" ]] || return 0
  python3 - "$src/changelog/$version" "$dst/version/$version" "${rows[@]}" <<'FOLD'
import json, pathlib, sys

notes, staged = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
rows = [pair.split("=", 1) for pair in sys.argv[3:]]

folded = 0
for language, locale in rows:
    note = notes / f"{language}.md"
    if not note.exists() or not note.read_text().strip():
        continue
    target = staged / f"{locale}.json"
    data = json.loads(target.read_text()) if target.exists() else {}
    data["whatsNew"] = note.read_text().strip()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    folded += 1
if folded:
    print(f"  what's new from the changelog for {folded} locale(s)")
FOLD
}

_fold_changelog_play() {
  local version="$1" src="$2" dst="$3" rows=("${@:4}")
  [[ -n "$version" && -d "$src/changelog/$version" ]] || return 0
  python3 - "$src/changelog/$version" "$dst/notes.json" "${rows[@]}" <<'FOLD'
import json, pathlib, sys

notes, staged = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
rows = [pair.split("=", 1) for pair in sys.argv[3:]]

release = []
for language, locale in rows:
    note = notes / f"{language}.md"
    if note.exists() and note.read_text().strip():
        release.append({"language": locale, "text": note.read_text().strip()})
if release:
    staged.write_text(json.dumps(release, ensure_ascii=False, indent=2) + "\n")
    print(f"  release notes from the changelog for {len(release)} locale(s)")
FOLD
}

# What each store will refuse, in characters — never bytes: every CJK locale
# fails a `wc -c` check that en-US passes.
metadata_check() {
  local dir="$1" stores="$2"
  python3 - "$dir" "$stores" <<'CHECK'
import json, pathlib, sys

APP_STORE = {
    "name": 30, "subtitle": 30, "keywords": 100,
    "promotionalText": 170, "description": 4000, "whatsNew": 4000,
}
PLAY = {"name": 30, "shortDescription": 80, "description": 4000, "whatsNew": 500}

root, stores = pathlib.Path(sys.argv[1]), sys.argv[2].split()
limits = {}
for store in stores:
    for field, limit in (APP_STORE if store == "appStore" else PLAY).items():
        # The tighter of the two: text that fits one store and not the other is
        # a listing that fails halfway through a push, having already changed
        # the locales before it.
        limits[field] = min(limit, limits.get(field, limit))

problems, counted, files = [], 0, 0
for path in sorted(root.rglob("*.json")):
    files += 1
    language = path.stem
    data = json.loads(path.read_text())
    for field, value in data.items():
        if not value or field.startswith("_"):
            continue
        counted += 1
        limit = limits.get(field)
        if limit and len(value) > limit:
            problems.append(f"{language}/{field}: {len(value)} > {limit}")
        if field == "keywords" and ", " in value:
            problems.append(
                f"{language}/keywords: has a space after a comma — that is an indexed character")

print(f"checked {counted} filled field(s) across {files} file(s) for: {', '.join(stores)}")
for problem in problems:
    print(f"  over: {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
CHECK
}

# asc's layout: app-info verbatim, and the version fields under the version
# being shipped. One file per locale ROW rather than per source file — two rows
# may share a capture, and both listings still want a folder of their own.
#
# `scope` is what a release actually changes. `notes` — the default upload —
# stages what's new and nothing else, because that is the only field that
# differs release to release; a description or a set of keywords is reworded
# deliberately, on its own day, and pushing all of it every time is how an edit
# someone made in App Store Connect gets quietly overwritten by a tree nobody
# re-pulled. `all` is that deliberate day.
#
# An omitted FIELD is a no-op to `asc metadata apply`, so a narrower stage
# leaves the rest of the listing standing rather than blanking it. An omitted
# LOCALIZATION is not — asc reads the missing file as a delete, which is why
# what this function leaves out, `asc_mirror_untouched` puts back as it lives
# before anything is planned. Staging less is safe; staging nothing at all was
# not.
metadata_stage_asc() {
  local version="$1" scope="$2" src="$3" dst="$4" rows=("${@:5}")
  python3 - "$version" "$scope" "$src" "$dst" "${rows[@]}" <<'STAGE'
import json, pathlib, shutil, sys

version, scope = sys.argv[1], sys.argv[2]
src, dst = pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])
rows = [pair.split("=", 1) for pair in sys.argv[5:]]

APP_INFO = {"name", "subtitle", "privacyPolicyUrl", "privacyChoicesUrl"}
VERSION = {"description", "keywords", "marketingUrl", "promotionalText",
           "supportUrl", "whatsNew"}

shutil.rmtree(dst, ignore_errors=True)
(dst / "version" / version).mkdir(parents=True)

# The app-info half is skipped entirely on a notes push — not staged empty,
# which would read as "these fields are intentionally blank" to anyone opening
# the staged tree to see what a run is about to send. What lands there instead
# is the live app-info, mirrored in afterwards: identical to Connect, so it
# plans no change, and honest about why it is in a tree the push is not for.
kinds = [("version", {"whatsNew"}, dst / "version" / version)]
if scope == "all":
    (dst / "app-info").mkdir(parents=True)
    kinds = [("app", APP_INFO, dst / "app-info"),
             ("version", VERSION, dst / "version" / version)]


def fields_for(folder, language, locale):
    """The store locale's own file if it has one, else the capture language's."""
    for stem in (locale, language):
        path = folder / f"{stem}.json"
        if path.exists():
            return json.loads(path.read_text())
    return {}


written = 0
for kind, keep, out in kinds:
    for language, locale in rows:
        data = fields_for(src / kind, language, locale)
        values = {k: v for k, v in data.items() if k in keep and v}
        if not values:
            continue
        (out / f"{locale}.json").write_text(
            json.dumps(values, ensure_ascii=False, indent=2) + "\n")
        written += 1
print(f"staged {written} file(s) for App Store Connect ({scope})")
STAGE
  _fold_changelog_asc "$version" "$src" "$dst" "${rows[@]}"
}

# Play's shape: one listing object per locale, plus the release notes, which
# hang off a track release rather than off the listing.
metadata_stage_play() {
  local src="$1" dst="$2" rows=("${@:3}")
  python3 - "$src" "$dst" "${rows[@]}" <<'STAGE'
import json, pathlib, shutil, sys

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
rows = [pair.split("=", 1) for pair in sys.argv[3:]]

shutil.rmtree(dst, ignore_errors=True)
(dst / "listings").mkdir(parents=True)


def fields_for(folder, language, locale):
    for stem in (locale, language):
        path = folder / f"{stem}.json"
        if path.exists():
            return json.loads(path.read_text())
    return {}


notes, written = [], 0
for language, locale in rows:
    app = fields_for(src / "app", language, locale)
    version = fields_for(src / "version", language, locale)
    if not app:
        continue

    listing = {
        "language": locale,
        "title": app.get("name", ""),
        # Play's short description has no App Store counterpart: the subtitle is
        # 30 characters and this is 80. An app that ships both writes both; one
        # that writes only a subtitle gets it here rather than an empty field,
        # which Play rejects.
        "shortDescription": app.get("shortDescription") or app.get("subtitle", ""),
        "fullDescription": version.get("description", ""),
    }
    if not listing["title"] or not listing["fullDescription"]:
        sys.exit(f"{locale}: Play needs both a title and a full description")
    (dst / "listings" / f"{locale}.json").write_text(
        json.dumps(listing, ensure_ascii=False, indent=2) + "\n")
    written += 1

    if version.get("whatsNew"):
        notes.append({"language": locale, "text": version["whatsNew"]})

(dst / "notes.json").write_text(json.dumps(notes, ensure_ascii=False, indent=2) + "\n")
print(f"staged {written} listing(s) for Play")
STAGE
  _fold_changelog_play "${UPLOAD_VERSION:-}" "$src" "$dst" "${rows[@]}"
}

# --- the changelog ----------------------------------------------------------
#
# A version is a folder: the stores take the one being shipped, the web renders
# all of them. A single whatsNew field has no history. A repo with no changelog/
# keeps using that field, so adoption is incremental.

# The newest version in the changelog, by sort order rather than by mtime.
metadata_latest_version() {
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

# --- coverage ---------------------------------------------------------------
#
# The check nobody does by hand: every language the manifest declares has every
# field, in every surface. A missing one does not fail an upload — the store
# simply shows the previous release's words, or English, and nobody notices for
# months.
metadata_coverage() {
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
