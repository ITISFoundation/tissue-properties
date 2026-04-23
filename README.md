# tissue-properties

An o²S²PARC dynamic service that displays the IT'IS Foundation
[tissue properties database](https://itis.swiss/database) as an interactive,
searchable HTML table and publishes the underlying CSV as `output_1` for
downstream pipeline nodes.

## Develop

Edit the viewer in `src/` and run the dev image with hot-reload:

```bash
make run-devel
```

Open http://localhost:8080/ — changes to files under `src/` reload automatically.

## Validate the production build

When done, validate the final image (the same one shipped to oSPARC) locally:

```bash
make run
```

This regenerates `docker-compose.yml` from `.osparc/`, builds the production
image with all oSPARC labels, and runs it with a sidecar-style mount at
`./validation/outputs/`. After it boots you should find the published CSV at
`./validation/outputs/output_1/TissueProperties.csv`.

## Test in a local osparc-simcore deployment

With a local [osparc-simcore](https://github.com/ITISFoundation/osparc-simcore)
stack running (which exposes a throw-away registry at `registry:5000`), push
the freshly-built production image so the platform can pull it:

```bash
make build         # builds simcore/services/dynamic/tissue-properties:<version>
make publish-local # tags + pushes it to registry:5000
```

Then open the oSPARC web UI, refresh the service catalog, and add
`tissue-properties` to a study to test it end-to-end.

## Update the tissue-properties dataset

When a new IT'IS Material Database release comes out, drop the new
`*.db` file into [data-source/](data-source/) and run:

```bash
make tissues-list-versions                 # see the versions in the DB
make tissues-update-csv VERSION=<version>  # regenerate the CSV + bump version_display
```

This rewrites `src/csv-to-html-table/data/TissueProperties.csv`, updates
the `version_display` field in `.osparc/tissue-properties/metadata.yml`.

See [data-source/README.md](data-source/README.md) for the full procedure,
required/optional variables.

## All other targets

```bash
make
```

…lists everything (build, publish, version bump, etc).
