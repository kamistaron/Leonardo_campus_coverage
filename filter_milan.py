#!/usr/bin/env python3
"""Prepare the public OpenCellID extract used by the Leonardo coverage case study.

Input:  data/Italy_towers.csv (OpenCellID-style CSV export)
Output: data/Milan_towers.csv

The script filters invalid coordinates, the Leonardo/Citta Studi study envelope,
minimum observation count, and supported radio technologies. It does not infer
engineering parameters such as antenna height, power, pattern, or downtilt.
"""
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
INPUT = DATA / "Italy_towers.csv"
OUTPUT = DATA / "Milan_towers.csv"

COLUMNS = [
    "radio", "mcc", "net", "area", "cell", "unit", "lon", "lat",
    "range", "samples", "changeable", "created", "updated", "averageSignal",
]
MCC_ITALY = 222
SUPPORTED_RADIOS = {"UMTS", "LTE", "NR"}
MIN_SAMPLES_EXCLUSIVE = 3
# Study bounding box used by the original project, plus an approximately 500 m margin.
MIN_LAT, MAX_LAT = 45.4686500, 45.4836900
MIN_LON, MAX_LON = 9.2178700, 9.2383400
PAD_LAT, PAD_LON = 0.0045, 0.0063


def main() -> None:
    if not INPUT.exists():
        raise FileNotFoundError(f"Missing input file: {INPUT}")

    DATA.mkdir(exist_ok=True)
    df = pd.read_csv(INPUT, names=COLUMNS, header=0, low_memory=False)
    for col in ("mcc", "lat", "lon", "samples"):
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df["radio"] = df["radio"].astype("string").str.upper().str.strip()

    clean = df[
        (df["mcc"] == MCC_ITALY)
        & df["lat"].between(-90, 90)
        & df["lon"].between(-180, 180)
        & df["lat"].ne(0)
        & df["lon"].ne(0)
        & df["lat"].between(MIN_LAT - PAD_LAT, MAX_LAT + PAD_LAT)
        & df["lon"].between(MIN_LON - PAD_LON, MAX_LON + PAD_LON)
        & (df["samples"] > MIN_SAMPLES_EXCLUSIVE)
        & df["radio"].isin(SUPPORTED_RADIOS)
    ].copy()

    clean.sort_values(["radio", "lat", "lon", "net", "cell"], inplace=True)
    clean.to_csv(OUTPUT, index=False)

    print(f"Input rows: {len(df):,}")
    print(f"Output rows: {len(clean):,}")
    print("Radio breakdown:")
    print(clean["radio"].value_counts().to_string())
    print(f"Saved: {OUTPUT}")


if __name__ == "__main__":
    main()
