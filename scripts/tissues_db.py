#!/usr/bin/env python3
"""CLI for the IT'IS Material Database SQLite file.

Subcommands:
  list-versions  show available IT'IS versions and their tissue counts
  convert        export a version to the flat CSV consumed by the
                 tissue-properties viewer

Run via the Make targets `tissues-list-versions` and
`tissues-update-csv`, which build the companion image
(see ``scripts/Dockerfile``) once and reuse it.
"""
from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd
import typer

app = typer.Typer(add_completion=False, no_args_is_help=True, help=__doc__)

# (CSV header, property name in DB) for every column populated from the
# scalar `measurements` table.
SCALAR_COLUMNS: list[tuple[str, str]] = [
    ("Density (kg/m3)",                                                "Mass Density"),
    ("Heat Capacity (J/kg/\u00b0C)",                                   "Specific Heat Capacity"),
    ("Thermal Conductivity (W/m/\u00b0C)",                             "Thermal Conductivity"),
    ("Heat Transfer Rate (ml/min/kg)",                                 "Perfusion Rate (const)"),
    ("Heat Generation Rate (W/kg)",                                    "Heat Generation Rate"),
    # LF Electrical Conductivity comes separately, from Gabriel sigma.
    ("Magnetic Conductivity (S/m)",                                    "Magnetic Conductivity"),
    ("Magnetic Relative Permeability",                                 "Relative Permeability"),
    ("Tissue Speed of Sound (m/s)",                                    "Speed of Sound"),
    ("Tissue Dependent Parameter of the Non Linearity Prameter B/A",   "B/A non-linearity parameter"),
    ("Attenuation Constant - \u03b10 (Np/m/MHz)",                      "Attenuation constant alpha"),
    ("Attenuation Constant - b",                                       "Attenuation constant b"),
]
LF_HEADER = "LF Electrical Conductivity (S/m)"
MRI_FIELD_STRENGTHS = (1.5, 3.0)

CSV_HEADER = (
    ["Tissue Name"]
    + [c for c, _ in SCALAR_COLUMNS[:5]]
    + [LF_HEADER]
    + [c for c, _ in SCALAR_COLUMNS[5:]]
    + [f"{b}T- T{ax} (ms)" for b in ("1.5", "3.0") for ax in (1, 2)]
)


def _decode_blob(blob: object) -> np.ndarray:
    if not isinstance(blob, (bytes, bytearray, memoryview)):
        return np.empty(0, dtype="<f8")
    return np.frombuffer(bytes(blob), dtype="<f8")


def _gabriel_sigma_lf(blob: object) -> float | None:
    """Static ionic conductivity (last value of the Gabriel 4-pole
    Cole-Cole blob: ``[ε_inf, (Δε_i, τ_i, α_i)*4, σ_static]`` = 14
    doubles, or the legacy 16-double layout).

    NOTE: this is the asymptotic low-frequency σ from the Cole-Cole
    fit, which is the most defensible "LF conductivity" the database
    actually carries. The legacy `inputs/TissueProperties.csv` values
    appear to have been hand-curated from publications and do NOT
    match σ_static for several tissues, so a perfect byte-for-byte
    reproduction of the legacy CSV is not possible from the DB.
    """
    arr = _decode_blob(blob)
    return float(arr[-1]) if arr.size in (14, 16) else None


def _pick_version(con: sqlite3.Connection, requested: str | None) -> tuple[str, str]:
    if requested:
        row = con.execute(
            """SELECT v.ver_id, v.string FROM versions v
                 JOIN databases d ON d.db_id = v.db_id
                WHERE d.name = 'IT''IS' AND v.string = ?
                ORDER BY v.priority ASC LIMIT 1""",
            (requested,),
        ).fetchone()
        if row is None:
            available = ", ".join(r[0] for r in con.execute(
                "SELECT DISTINCT v.string FROM versions v JOIN databases d ON d.db_id=v.db_id "
                "WHERE d.name='IT''IS' ORDER BY v.string"))
            raise typer.BadParameter(f"version {requested!r} not found. Available IT'IS versions: {available}")
        return row[0], row[1]

    row = con.execute(
        """SELECT v.ver_id, v.string FROM versions v
             JOIN databases d ON d.db_id = v.db_id
            WHERE d.name = 'IT''IS'
            ORDER BY v.active DESC, v.priority ASC LIMIT 1""",
    ).fetchone()
    if row is None:
        raise typer.BadParameter("no IT'IS database version found in this SQLite file")
    return row[0], row[1]


@app.command("list-versions")
def list_versions(
    db: Path = typer.Argument(..., exists=True, dir_okay=False, readable=True, help="path to the IT'IS Material Database .db file"),
) -> None:
    """List all IT'IS versions in DB and their tissue counts."""
    con = sqlite3.connect(db)
    rows = list(con.execute("""
        SELECT v.string, v.priority, v.active, COUNT(mat.mat_id) AS n
          FROM versions v
          JOIN databases d ON d.db_id = v.db_id
     LEFT JOIN materials mat ON mat.ver_id = v.ver_id
         WHERE d.name = 'IT''IS'
      GROUP BY v.ver_id
      ORDER BY v.priority ASC
    """))
    typer.echo(f"IT'IS versions in {db}:")
    typer.echo(f"  {'version':<14} {'#tissues':>9}  active")
    typer.echo(f"  {'-' * 14} {'-' * 9}  ------")
    for string, _priority, active, n in rows:
        marker = "*" if active else " "
        typer.echo(f"  {string:<14} {n:>9}     {marker}")


@app.command("convert")
def convert(
    db: Path = typer.Argument(..., exists=True, dir_okay=False, readable=True, help="path to the IT'IS Material Database .db file"),
    out: Path = typer.Argument(..., dir_okay=False, help="path to the CSV file to (over)write"),
    version: Optional[str] = typer.Option(None, "--version", "-v", help="IT'IS version string (e.g. '4.0', '4.2', '5.0'). Defaults to the active version in the DB."),
) -> None:
    """Convert DB to TissueProperties CSV (overwrites OUT)."""
    con = sqlite3.connect(db)
    con.row_factory = sqlite3.Row
    ver_id, ver_string = _pick_version(con, version)
    typer.echo(f"[tissues-db] using IT'IS version: {ver_string} ({ver_id})", err=True)

    properties = pd.read_sql_query("SELECT prop_id, name FROM properties", con).set_index("name")["prop_id"]
    required = [n for _, n in SCALAR_COLUMNS] + [
        "Gabriel Parameters", "Magnetic Field Strength", "Relaxation Time 1", "Relaxation Time 2",
    ]
    missing = [n for n in required if n not in properties.index]
    if missing:
        raise typer.BadParameter(f"properties missing from database: {missing}")

    materials = pd.read_sql_query(
        "SELECT mat_id, name FROM materials WHERE ver_id = ? ORDER BY name",
        con, params=(ver_id,),
    )
    typer.echo(f"[tissues-db] exporting {len(materials)} materials", err=True)

    placeholders = ",".join("?" * len(materials))
    measurements = pd.read_sql_query(
        f"""SELECT m.mat_id, p.name AS prop_name, m.value
              FROM measurements m
              JOIN properties p ON p.prop_id = m.prop_id
             WHERE m.mat_id IN ({placeholders})""",
        con, params=tuple(materials["mat_id"]),
    )
    scalars = measurements.pivot(index="mat_id", columns="prop_name", values="value")

    vectors = pd.read_sql_query(
        f"""SELECT v.mat_id, p.name AS prop_name, v.vals
              FROM vectors v
              JOIN properties p ON p.prop_id = v.prop_id
             WHERE v.mat_id IN ({placeholders})""",
        con, params=tuple(materials["mat_id"]),
    )
    blobs = vectors.pivot(index="mat_id", columns="prop_name", values="vals")

    rows = []
    for _, mat in materials.iterrows():
        mid = mat["mat_id"]
        scalar_row = scalars.loc[mid] if mid in scalars.index else pd.Series(dtype=float)
        blob_row = blobs.loc[mid] if mid in blobs.index else pd.Series(dtype=object)

        field_vals = _decode_blob(blob_row.get("Magnetic Field Strength"))
        t1 = dict(zip(field_vals, _decode_blob(blob_row.get("Relaxation Time 1"))))
        t2 = dict(zip(field_vals, _decode_blob(blob_row.get("Relaxation Time 2"))))

        out_row = [mat["name"]]
        out_row += [scalar_row.get(p) for _, p in SCALAR_COLUMNS[:5]]
        out_row += [_gabriel_sigma_lf(blob_row.get("Gabriel Parameters"))]
        out_row += [scalar_row.get(p) for _, p in SCALAR_COLUMNS[5:]]
        for b in MRI_FIELD_STRENGTHS:
            out_row.append(t1.get(b))
            out_row.append(t2.get(b))
        rows.append(out_row)

    df = pd.DataFrame(rows, columns=CSV_HEADER)
    out.parent.mkdir(parents=True, exist_ok=True)
    # Match the legacy CSV format: ; separator, comma decimal point,
    # 10 significant digits.
    df.to_csv(out, sep=";", decimal=",", index=False, float_format="%.10g")
    typer.echo(f"[tissues-db] wrote {out}", err=True)


if __name__ == "__main__":
    app()
