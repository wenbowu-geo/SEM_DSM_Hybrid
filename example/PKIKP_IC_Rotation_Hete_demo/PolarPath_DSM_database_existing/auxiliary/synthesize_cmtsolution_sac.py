#!/usr/bin/env python3
"""
Build CMTSOLUTION synthetics from DSM moment-component SAC files.

The component SAC files are assumed to be computed for unit basis moments
with the exponent used in run.cmd. The default basis moment is 1.e7 dyn*cm
(1 N*m), matching the current run.cmd basis setup.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import re
import shutil
import struct
from array import array
from pathlib import Path


COMPONENT_DIRS = ("Mzz", "Mrr", "Mtt", "Mzr", "Mzt", "Mrt")
SAC_EXTENSIONS = (".bhz", ".bhr", ".bht")
SAC_HEADER_BYTES = 632


def read_key_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            values[key.strip()] = value.strip().split()[0]
    return values


def read_cmtsolution(path: Path) -> dict[str, float]:
    raw = read_key_values(path)
    required = ("latitude", "longitude", "depth", "Mrr", "Mtt", "Mpp", "Mrt", "Mrp", "Mtp")
    missing = [key for key in required if key not in raw]
    if missing:
        raise RuntimeError(f"missing CMTSOLUTION fields in {path}: {', '.join(missing)}")
    return {key: float(raw[key]) for key in required}


def read_single_force_enz(path: Path) -> int:
    pattern = re.compile(r"^\s*SINGLE_FORCE_ENZ\s*=\s*([-+]?\d+)")
    for line in path.read_text().splitlines():
        match = pattern.match(line)
        if match:
            return int(match.group(1))
    raise RuntimeError(f"failed to find SINGLE_FORCE_ENZ in {path}")


def read_depths(path: Path) -> list[tuple[float, int]]:
    rows: list[tuple[float, int]] = []
    for iline, line in enumerate(path.read_text().splitlines(), start=1):
        parts = line.split()
        if iline <= 2 or not parts:
            continue
        rows.append((float(parts[0]), int(parts[1])))
    if not rows:
        raise RuntimeError(f"no depths found in {path}")
    return rows


def read_stations(path: Path) -> list[dict[str, float | str]]:
    stations: list[dict[str, float | str]] = []
    seen: set[tuple[str, str, float]] = set()
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) < 5 or parts[0].startswith("#"):
            continue
        key = (parts[0], parts[1], round(float(parts[4]), 8))
        if key in seen:
            continue
        seen.add(key)
        stations.append(
            {
                "net": parts[0],
                "sta": parts[1],
                "lon": float(parts[2]),
                "lat": float(parts[3]),
                "dist": float(parts[4]),
            }
        )
    if not stations:
        raise RuntimeError(f"no stations found in {path}")
    return stations


def azimuth_deg(src_lat: float, src_lon: float, sta_lat: float, sta_lon: float) -> float:
    lat1 = math.radians(src_lat)
    lat2 = math.radians(sta_lat)
    dlon = math.radians(sta_lon - src_lon)
    y = math.sin(dlon) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)
    az = math.degrees(math.atan2(y, x))
    if az < 0.0:
        az += 360.0
    return az


def rotate_cmt_to_zrt(cmt: dict[str, float], az_deg: float) -> dict[str, float]:
    """Rotate CMTSOLUTION tensor from (r, theta, phi) to station-dependent (z, r, t)."""
    az = math.radians(az_deg)
    caz = math.cos(az)
    saz = math.sin(az)

    # Old CMTSOLUTION basis: radial up, theta south, phi east.
    old = (
        (cmt["Mrr"], cmt["Mrt"], cmt["Mrp"]),
        (cmt["Mrt"], cmt["Mtt"], cmt["Mtp"]),
        (cmt["Mrp"], cmt["Mtp"], cmt["Mpp"]),
    )

    # New basis vectors in the old basis.
    # z: vertical/radial up
    # r: horizontal great-circle direction from source to station
    # t: z x r, completing a right-handed z-r-t basis
    basis = (
        (1.0, 0.0, 0.0),
        (0.0, -caz, saz),
        (0.0, -saz, -caz),
    )

    def mt(i: int, j: int) -> float:
        return sum(basis[i][a] * old[a][b] * basis[j][b] for a in range(3) for b in range(3))

    return {
        "Mzz": mt(0, 0),
        "Mrr": mt(1, 1),
        "Mtt": mt(2, 2),
        "Mzr": mt(0, 1),
        "Mzt": mt(0, 2),
        "Mrt": mt(1, 2),
    }


def station_base(zone: int, depth: float, dist: float) -> str:
    return f"L{zone:d}_dep{depth:.2f}_dist{dist:.2f}"


def output_base(station: dict[str, float | str], depth: float) -> str:
    return f"{station['net']}_{station['sta']}_dep{depth:.2f}"


def read_sac(path: Path) -> tuple[bytes, array]:
    data = path.read_bytes()
    if len(data) < SAC_HEADER_BYTES or (len(data) - SAC_HEADER_BYTES) % 4 != 0:
        raise RuntimeError(f"{path} does not look like a SAC binary file")
    header = data[:SAC_HEADER_BYTES]
    trace = array("f")
    trace.frombytes(data[SAC_HEADER_BYTES:])
    return header, trace


def write_sac(path: Path, header: bytes, trace: array) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + trace.tobytes())


def update_sac_depmin_depmax_depmen(header: bytes, trace: array) -> bytes:
    if not trace:
        return header
    values = list(trace)
    depmin = min(values)
    depmax = max(values)
    depmen = sum(values) / len(values)
    patched = bytearray(header)
    # SAC float header indices: depmin=1, depmax=2, depmen=56.
    struct.pack_into("f", patched, 4 * 1, depmin)
    struct.pack_into("f", patched, 4 * 2, depmax)
    struct.pack_into("f", patched, 4 * 56, depmen)
    return bytes(patched)


def combine_for_base(
    root: Path,
    base: str,
    ext: str,
    coefficients: dict[str, float],
    input_subdir: str,
    component_dirs: tuple[str, ...] = COMPONENT_DIRS,
) -> tuple[bytes, array]:
    header: bytes | None = None
    output: array | None = None

    for comp in component_dirs:
        coef = coefficients.get(comp, 0.0)
        if coef == 0.0:
            continue
        sac_path = root / comp / "OUTPUT_FILES" / input_subdir / f"{base}{ext}"
        if not sac_path.exists():
            raise RuntimeError(f"missing component SAC file: {sac_path}")
        this_header, trace = read_sac(sac_path)
        if header is None:
            header = this_header
            output = array("f", [0.0]) * len(trace)
        if output is None or len(output) != len(trace):
            raise RuntimeError(f"inconsistent trace length in {sac_path}")
        for i, value in enumerate(trace):
            output[i] += coef * value

    if header is None or output is None:
        # Use the first requested component as a template for an exactly zero result.
        template_component = component_dirs[0]
        template = root / template_component / "OUTPUT_FILES" / input_subdir / f"{base}{ext}"
        if not template.exists():
            raise RuntimeError(f"missing template SAC file: {template}")
        header, trace = read_sac(template)
        output = array("f", [0.0]) * len(trace)

    return update_sac_depmin_depmax_depmen(header, output), output



def explosion_amplitude_ratio(cmt: dict[str, float], original: list[float]) -> float:
    """Scale original DSM explosion traces, never a previously scaled result."""
    keys = ("Mrr", "Mtt", "Mpp", "Mrt", "Mrp", "Mtp")
    requested = [cmt[key] for key in keys]

    def check_isotropic(values: list[float], label: str) -> None:
        if len(values) != 6 or not all(math.isfinite(value) for value in values):
            raise RuntimeError(f"{label} must contain six finite moment components")
        tolerance = 1.e-6 * max(abs(value) for value in values)
        if (any(abs(value - values[0]) > tolerance for value in values[1:3])
                or any(abs(value) > tolerance for value in values[3:])):
            raise RuntimeError(f"{label} is not isotropic; explosion reuse requires equal diagonal and zero off-diagonal moments")

    check_isotropic(original, "Original DSM explosion")
    check_isotropic(requested, "Requested CMTSOLUTION")
    if original[0] == 0.0:
        raise RuntimeError("Original DSM explosion moment is zero; compute nonzero DSM reference traces first")
    ratio = requested[0] / original[0]
    if not math.isfinite(ratio):
        raise RuntimeError("Explosion amplitude ratio must be finite")
    return ratio


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build CMTSOLUTION time-domain SAC synthetics from DSM moment-basis SAC files."
    )
    parser.add_argument("--cmt", default="DATA/CMTSOLUTION")
    parser.add_argument("--sem-par-file", default="DATA/Par_file_SEM_DSM")
    parser.add_argument("--reference-component", default="Mrr")
    parser.add_argument("--dsm-root", default=None)
    parser.add_argument("--input-subdir", default="disp_solid_time_sac")
    parser.add_argument("--output-dir", default="OUTPUT_FILES/CMTSOLUTION_time_sac")
    parser.add_argument("--basis-moment-dyn-cm", type=float, default=1.0e7)
    parser.add_argument("--clean", action="store_true", help="Remove existing files in output-dir before writing.")
    parser.add_argument("--if-needed", action="store_true", help="Skip when the saved source and synthesis settings match.")
    args = parser.parse_args()

    run_root = Path.cwd()
    configured_root = "WORK/DSM/1D_tele_syn"
    configured_database = ""
    has_root_setting = False
    config = run_root / "DATA/Par_file_SEM_DSM"
    if config.exists():
        for line in config.read_text().splitlines():
            key, sep, value = line.partition("=")
            if sep and key.strip() == "DSM_DATABASE_DIR":
                configured_database = value.split("#", 1)[0].strip()
            if sep and key.strip() == "DSM_1D_SYNTHETICS_DIR":
                has_root_setting = True
                configured_root = value.split("#", 1)[0].strip() or configured_root
    if configured_database and not has_root_setting:
        configured_root = str(Path(configured_database) / "1D_tele_syn")
    dsm_root = (run_root / (args.dsm_root or configured_root)).resolve()
    cmt_path = (run_root / args.cmt).resolve()
    par_path = (run_root / args.sem_par_file).resolve()
    ref_dir = dsm_root / args.reference_component
    depth_path = ref_dir / "DATA" / "depth_solid_list"
    station_path = ref_dir / "DATA" / "station_distances.txt"
    output_dir = Path(args.output_dir)
    if not output_dir.is_absolute():
        output_root = dsm_root if args.dsm_root else run_root / "WORK/DSM/1D_tele_syn"
        output_dir = output_root / output_dir

    cmt_bytes = cmt_path.read_bytes()
    cmt = read_cmtsolution(cmt_path)
    source_mode = read_single_force_enz(par_path)
    if source_mode not in (-1, 0):
        raise RuntimeError(
            f"SINGLE_FORCE_ENZ={source_mode} is not supported here; expected -1 explosion or 0 full moment tensor"
        )
    if source_mode == -1 and args.reference_component == "Mrr":
        ref_dir = dsm_root / "explosion"
        depth_path = ref_dir / "DATA" / "depth_solid_list"
        station_path = ref_dir / "DATA" / "station_distances.txt"
    # Check the actual DSM source geometry, including legacy runs without a snapshot.
    model_lines = (ref_dir / "DATA" / "dsm_model").read_text().splitlines()
    source_index = 4 + 6 * int(model_lines[3].split()[0])
    geometry = [float(v.replace("D", "e").replace("d", "e")) for v in model_lines[source_index].split()[:3]]
    # An explosion in a spherically symmetric 1-D model is invariant under a
    # rigid rotation, so a database generated at another latitude/longitude is
    # reusable.  Its source depth must still match.  Moment-tensor synthesis
    # uses the source/station azimuth and therefore retains the full geometry
    # check.
    geometry_keys = ("depth",) if source_mode == -1 else ("depth", "latitude", "longitude")
    if any(
        not math.isclose(geometry[index], cmt[key], rel_tol=0.0, abs_tol=1.e-6)
        for index, key in enumerate(geometry_keys)
    ):
        changed = "depth" if source_mode == -1 else "location/depth"
        raise RuntimeError(f"Source {changed} changed: rerun Step 6 DSM components before synthesis")
    explosion_ratio = 1.0
    if source_mode == -1:
        moment = [float(v.replace("D", "e").replace("d", "e")) for v in model_lines[source_index + 1].split()[:7]]
        if len(moment) != 7:
            raise RuntimeError("Incomplete original DSM explosion moment vector")
        original = [value * 10.0 ** moment[0] for value in moment[1:]]
        explosion_ratio = explosion_amplitude_ratio(cmt, original)
    snapshot = output_dir / "CMTSOLUTION"
    model_digest = hashlib.sha256((ref_dir / "DATA" / "dsm_model").read_bytes()).hexdigest()
    settings = f"v2 {source_mode} {args.input_subdir} {args.basis_moment_dyn_cm!r} {ref_dir} {model_digest}\n"
    settings_path = output_dir / "synthesis_settings.txt"
    if (args.if_needed and snapshot.exists() and snapshot.read_bytes() == cmt_bytes
            and settings_path.exists() and settings_path.read_text() == settings
            and all(any(output_dir.glob(f"*{ext}")) for ext in SAC_EXTENSIONS)):
        print(f"1-D synthetics already match CMTSOLUTION: {output_dir}")
        return

    depths = read_depths(depth_path)
    stations = read_stations(station_path)

    if args.clean and output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    nout = 0
    nskip = 0
    for depth, zone in depths:
        for station in stations:
            dist = float(station["dist"])
            input_base = station_base(zone, depth, dist)
            out_base = output_base(station, depth)
            template = ref_dir / "OUTPUT_FILES" / args.input_subdir / f"{input_base}{SAC_EXTENSIONS[0]}"
            if not template.exists():
                nskip += 1
                print(f"Skipping station row without converted SAC template: {template}")
                continue

            if source_mode == -1:
                # Step 6 computes the complete explosion moment tensor in one DSM run.
                coefficients = {"explosion": explosion_ratio}
                component_dirs = ("explosion",)
                mode_text = "explosion"
            else:
                az = azimuth_deg(cmt["latitude"], cmt["longitude"], float(station["lat"]), float(station["lon"]))
                rotated = rotate_cmt_to_zrt(cmt, az)
                coefficients = {key: value / args.basis_moment_dyn_cm for key, value in rotated.items()}
                component_dirs = COMPONENT_DIRS
                mode_text = "full moment tensor"

            for ext in SAC_EXTENSIONS:
                header, trace = combine_for_base(dsm_root, input_base, ext, coefficients, args.input_subdir, component_dirs)
                write_sac(output_dir / f"{out_base}{ext}", header, trace)
                nout += 1

    if nout == 0 or nskip:
        raise RuntimeError("Incomplete SAC synthesis; source snapshot was not saved")
    snapshot.write_bytes(cmt_bytes)
    settings_path.write_text(settings)

    print(f"Source mode: {mode_text} (SINGLE_FORCE_ENZ={source_mode})")
    if source_mode == -1:
        print(f"Explosion amplitude ratio (current / original DSM): {explosion_ratio:.12g}")
    else:
        print(f"Basis moment: {args.basis_moment_dyn_cm:.6e} dyn*cm")
    print(f"Wrote {nout} SAC files to {output_dir}")
    if nskip:
        print(f"Skipped {nskip} stale station/depth rows without converted SAC files")


if __name__ == "__main__":
    main()
