# data-source/

Drop **exactly one** IT'IS Material Database SQLite file (`*.db`) here,
then update the bundled `TissueProperties.csv` in two steps:

```bash
# 1. see which IT'IS versions live in the dropped DB
make tissues-list-versions

# 2. regenerate the CSV from the version of your choice
make tissues-update-csv VERSION=4.0
```

The targets refuse to run when `data-source/` contains zero or more than
one `.db` file. To work around this transiently (e.g. evaluate a second
DB without removing the first) override `DB=`:

| variable | default | meaning |
|---|---|---|
| `DB` | the single `*.db` in this folder | input SQLite file |
| `VERSION` | _active version in the DB_ | e.g. `4.0`, `4.2`, `5.0` |
| `OUT_CSV` | `src/csv-to-html-table/data/TissueProperties.csv` | destination |

```bash
# inspect a different file without dropping it in here
make tissues-list-versions DB=/path/to/some_other.db

# export to a custom location
make tissues-update-csv VERSION=4.2 OUT_CSV=/tmp/tissues.csv
```

`.db` files in this folder are git-ignored.

## Notes & caveats

- **Tissue count by version.** The legacy `inputs/TissueProperties.csv`
  contained 109 tissues, which corresponds to IT'IS version `4.0`.
  Newer versions add tissues (`4.2` → 112, `5.0` → 112, `5.0-sasaki`
  → 95). Pass `VERSION=4.0` to reproduce the legacy row set.
- **`LF Electrical Conductivity (S/m)`.** The DB does not store a
  scalar low-frequency conductivity per tissue. The script populates
  this column with σ\_static from the Gabriel 4-pole Cole-Cole fit
  (last value of the `Gabriel Parameters` blob). The legacy CSV used
  values that appear to have been hand-curated from publications and
  do not byte-match σ\_static for several tissues — that is expected.
- **Numeric formatting.** Output uses `;` as field separator, `,` as
  decimal separator, and 10 significant digits — the format the
  bundled `csv-to-html-table` viewer expects.



