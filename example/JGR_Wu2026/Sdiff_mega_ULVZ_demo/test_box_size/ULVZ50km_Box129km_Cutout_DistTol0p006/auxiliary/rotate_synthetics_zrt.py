#!/usr/bin/env python3
"""Write station-aligned Z/R/T SAC traces for the 1-D and 3-D synthetics."""

from __future__ import annotations

import argparse
import math
from array import array
from pathlib import Path

from assemble_3d_sem_dsm_synthetics import (
    receiver_radial_azimuth_deg, read_cmtsolution, read_sac, read_stations,
    refresh_sac_header, sac_float, set_component_orientation, set_station_geometry, write_sac,
)

ROOT = Path(__file__).resolve().parent.parent
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", default="OUTPUT_FILES")
    args = parser.parse_args()
    output = (ROOT / args.output_root).resolve()

    cmt = read_cmtsolution(ROOT / "DATA/CMTSOLUTION")
    stations = read_stations(ROOT / "DATA/tele_station.txt")
    source_1d, source_3d = output / "1D_DSM", output / "3D_SEM_DSM"
    target_1d, target_3d = output / "1D_DSM_ZRT", output / "3D_SEM_DSM_ZRT"

    for station in stations:
        name = str(station["name"])
        required = (
            *(source_1d / f"{name}.bh{component}" for component in "zrt"),
            *(source_3d / f"{name}.bh{component}" for component in "zne"),
        )
        for path in required:
            if not path.is_file():
                raise RuntimeError(f"missing input SAC file: {path}")

    for station in stations:
        name = str(station["name"])
        azimuth = receiver_radial_azimuth_deg(cmt["latitude"], cmt["longitude"],
                              float(station["lat"]), float(station["lon"]))
        for component in "ZRT":
            header, trace = read_sac(source_1d / f"{name}.bh{component.lower()}")
            set_station_geometry(header, cmt, station)
            set_component_orientation(header, component, azimuth)
            write_sac(target_1d / f"{name}.bh{component.lower()}", header, trace)

        header_z, trace_z = read_sac(source_3d / f"{name}.bhz")
        header_n, trace_n = read_sac(source_3d / f"{name}.bhn")
        header_e, trace_e = read_sac(source_3d / f"{name}.bhe")
        if len(trace_z) != len(trace_n) or len(trace_n) != len(trace_e):
            raise RuntimeError(f"3-D component lengths differ for {name}")
        for label, header in (("N", header_n), ("E", header_e)):
            if not math.isclose(sac_float(header, 0), sac_float(header_z, 0), rel_tol=1e-6) or not math.isclose(
                sac_float(header, 5), sac_float(header_z, 5), abs_tol=1e-4
            ):
                raise RuntimeError(f"3-D {label} sample grid differs from Z for {name}")

        radians = math.radians(azimuth)
        cosine, sine = math.cos(radians), math.sin(radians)
        trace_r = array("f", (north * cosine + east * sine for north, east in zip(trace_n, trace_e)))
        # Right-handed Z-R-T convention: Z is up, R points from source to
        # receiver, and T = Z x R.  Thus a northward R has westward T.
        trace_t = array("f", (north * sine - east * cosine for north, east in zip(trace_n, trace_e)))
        for component, header, trace in (
            ("Z", header_z, trace_z),
            ("R", header_n, trace_r),
            ("T", header_e, trace_t),
        ):
            set_station_geometry(header, cmt, station)
            set_component_orientation(header, component, azimuth)
            refresh_sac_header(header, trace, sac_float(header, 5))
            write_sac(target_3d / f"{name}.bh{component.lower()}", header, trace)

    count = 3 * len(stations)
    print(f"Wrote {count} 1-D ZRT SAC files to {target_1d}")
    print(f"Wrote {count} 3-D ZRT SAC files to {target_3d}")


if __name__ == "__main__":
    main()
