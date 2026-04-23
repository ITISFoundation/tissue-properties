# data-source/

Drop **exactly one** IT'IS Material Database SQLite file (`*.db`) here,
then update the bundled `TissueProperties.csv` in two steps:

```bash
# 1. see which IT'IS versions live in the dropped DB
make tissues-list-versions

# 2. regenerate the CSV from the version of your choice
make tissues-update-csv VERSION=4.0
```

`VERSION=` is **required** and must match one of the strings reported by
`tissues-list-versions` (e.g. `4.0`, `4.2`, `5.0`, `5.0-sasaki`). In
addition to (over)writing `OUT_CSV`, `tissues-update-csv` also rewrites
the `version_display` field in `.osparc/tissue-properties/metadata.yml`
with the same string and re-runs `compose-spec` so the generated
`docker-compose.yml` carries the new `io.simcore.version_display` label.

The targets refuse to run when `data-source/` contains zero or more than
one `.db` file. To work around this transiently (e.g. evaluate a second
DB without removing the first) override `DB=`:

| variable | default | meaning |
|---|---|---|
| `DB` | the single `*.db` in this folder | input SQLite file |
| `VERSION` | _required_ | e.g. `4.0`, `4.2`, `5.0` |
| `OUT_CSV` | `src/csv-to-html-table/data/TissueProperties.csv` | destination |

```bash
# inspect a different file without dropping it in here
make tissues-list-versions DB=/path/to/some_other.db

# export to a custom location
make tissues-update-csv VERSION=4.2 OUT_CSV=/tmp/tissues.csv
```

`.db` files in this folder are git-ignored.
