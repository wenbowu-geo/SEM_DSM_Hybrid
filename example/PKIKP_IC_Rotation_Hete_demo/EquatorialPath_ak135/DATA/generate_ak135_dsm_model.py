#!/usr/bin/env python3
"""Convert SPECFEM's bundled ak135 table to the polynomial DSM format."""

from __future__ import annotations

import re
from pathlib import Path


HERE = Path(__file__).resolve().parent
CASE_ROOT = HERE.parent
REPO_ROOT = CASE_ROOT.parents[2]
AK135_SOURCE = (
    REPO_ROOT
    / "src/SPECFEM3D/utils/small_SEM_solvers_in_Fortran_and_C_without_MPI_to_learn"
    / "mesher_for_serial/model_ak135.f90"
)
OUTPUT = HERE / "dsm_model_base"
EARTH_RADIUS_KM = 6371.0
FIELDS = ("radius", "density", "vp", "vs", "Qkappa", "Qmu")


def read_table() -> dict[str, list[float]]:
    values: dict[str, dict[int, float]] = {name: {} for name in FIELDS}
    assignment = re.compile(
        r"Mak135_V%(radius|density|vp|vs|Qkappa|Qmu)_ak135\(\s*(\d+)\)\s*=\s*"
        r"([-+0-9.EeDd]+)",
        re.IGNORECASE,
    )
    canonical = {name.lower(): name for name in FIELDS}
    for match in assignment.finditer(AK135_SOURCE.read_text()):
        field = canonical[match.group(1).lower()]
        values[field][int(match.group(2))] = float(
            match.group(3).replace("D", "E").replace("d", "e")
        )

    count = len(values["radius"])
    if count == 0 or any(set(table) != set(range(1, count + 1)) for table in values.values()):
        raise RuntimeError(f"Incomplete ak135 arrays in {AK135_SOURCE}")
    return {name: [values[name][i] for i in range(1, count + 1)] for name in FIELDS}


def linear_coefficients(r0_km: float, r1_km: float, y0: float, y1: float) -> tuple[float, float]:
    x0, x1 = r0_km / EARTH_RADIUS_KM, r1_km / EARTH_RADIUS_KM
    slope = (y1 - y0) / (x1 - x0)
    return y0 - slope * x0, slope


def main() -> None:
    table = read_table()
    radii = [radius_m / 1000.0 for radius_m in table["radius"]]
    intervals = [(i, i + 1) for i in range(len(radii) - 1) if radii[i + 1] > radii[i]]

    old_lines = OUTPUT.read_text().splitlines()
    old_zone_count = int(old_lines[3].split()[0])
    tail_start = 4 + 6 * old_zone_count
    tail = old_lines[tail_start:]

    lines = [
        old_lines[0],
        old_lines[1],
        old_lines[2],
        f"  {len(intervals):d}   # n_structure_zone; ak135 piecewise-linear intervals",
    ]
    for i0, i1 in intervals:
        r0, r1 = radii[i0], radii[i1]
        coefficients = []
        for field in ("density", "vp", "vp", "vs", "vs"):
            coefficients.append(linear_coefficients(r0, r1, table[field][i0], table[field][i1]))

        a, b = coefficients[0]
        lines.append(f"{r0:10.3f} {r1:10.3f} {a:15.8f} {b:15.8f}  0.0  0.0")
        for a, b in coefficients[1:]:
            lines.append(f"{'':21s}{a:15.8f} {b:15.8f}  0.0  0.0")

        # DSM accepts one Q value per zone.  The midpoint value preserves the
        # mean of SPECFEM's linear interpolation over each ak135 interval.
        qmu = 0.5 * (table["Qmu"][i0] + table["Qmu"][i1])
        qkappa = 0.5 * (table["Qkappa"][i0] + table["Qkappa"][i1])
        lines.append(f"{'':21s}1.0  0.0  0.0  0.0 {qmu:12.5f} {qkappa:12.5f}")

    lines.extend(tail)
    OUTPUT.write_text("\n".join(lines) + "\n")
    print(f"Wrote {OUTPUT} with {len(intervals)} ak135 zones from {AK135_SOURCE}")


if __name__ == "__main__":
    main()
