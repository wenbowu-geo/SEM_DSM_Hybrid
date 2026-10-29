#!/usr/bin/env python3
"""Validate shared final 1-D synthetics without writing or recombining traces."""
import argparse
import hashlib
import math
from pathlib import Path
import struct
import sys


def parameters(path):
    result = {}
    for line in path.read_text().splitlines():
        key, sep, value = line.partition('=')
        key = key.strip()
        if sep and not key.startswith('#') and key not in result:
            result[key] = value.split('#', 1)[0].strip()
    return result


def stations(path):
    result = {}
    for line in path.read_text().splitlines():
        p = line.split()
        if len(p) >= 4 and not p[0].startswith('#'):
            result[(p[0], p[1])] = tuple(map(float, p[2:4]))
    if not result:
        raise RuntimeError('No receivers in ' + str(path))
    return result


def validate(case):
    config = parameters(case / 'DATA/Par_file_SEM_DSM')
    if config.get('SINGLE_FORCE_ENZ') != '0':
        raise RuntimeError('This reuse example requires SINGLE_FORCE_ENZ=0')
    database = config.get('DSM_1D_SYNTHETICS_DIR')
    if not database:
        shared = config.get('DSM_DATABASE_DIR')
        if not shared:
            raise RuntimeError('Set DSM_DATABASE_DIR to the existing DSM database')
        database = str(Path(shared) / '1D_tele_syn')
    root = (case / database).resolve()
    reference = root / 'Mrr'
    output = root / 'OUTPUT_FILES/CMTSOLUTION_time_sac'
    # Exact snapshot comparison also covers time shift, duration and event origin.
    if (case / 'DATA/CMTSOLUTION').read_bytes() != (output / 'CMTSOLUTION').read_bytes():
        raise RuntimeError('CMTSOLUTION differs from the shared 1-D source snapshot; reuse is incompatible')
    requested = stations(case / 'DATA/tele_station.txt')
    saved = stations(reference / 'DATA/station_distances.txt')
    if requested.keys() != saved.keys() or any(
        not all(math.isclose(a, b, rel_tol=0.0, abs_tol=1.e-6) for a, b in zip(coords, saved[key]))
        for key, coords in requested.items()
    ):
        raise RuntimeError('Receiver names or coordinates differ from the shared 1-D database')
    signature = (output / 'synthesis_settings.txt').read_text().split()
    expected_digest = hashlib.sha256((reference / 'DATA/dsm_model').read_bytes()).hexdigest()
    if (len(signature) != 6 or signature[:3] != ['v2', '0', 'disp_solid_time_sac']
            or float(signature[3]) != 1.e7 or Path(signature[4]).resolve() != reference
            or signature[5] != expected_digest):
        raise RuntimeError('Shared 1-D synthesis settings/model provenance do not match the DSM database')
    producer = root.parents[2]
    if (case / 'DATA/dsm_model_base').read_bytes() != (producer / 'DATA/dsm_model_base').read_bytes():
        raise RuntimeError('Background DSM model differs from the producing case')
    producer_config = parameters(producer / 'DATA/Par_file_SEM_DSM')
    for key in ('FREQ_RESOLVED', 'ATTENUATION_TARGET_DEPTHS'):
        if config.get(key, '').lower() != producer_config.get(key, '').lower():
            raise RuntimeError('Incompatible 1-D setting: ' + key)
    depths = [float(line.split()[0]) for line in (reference / 'DATA/depth_solid_list').read_text().splitlines()[2:] if line.strip()]
    if not depths:
        raise RuntimeError('Shared DSM receiver-depth list is empty')
    count = 0
    for net, sta in requested:
        for depth in depths:
            grid = None
            for ext in ('bhz', 'bhr', 'bht'):
                path = output / ('%s_%s_dep%.2f.%s' % (net, sta, depth, ext))
                with path.open('rb') as stream:
                    header = stream.read(632)
                    if len(header) != 632:
                        raise RuntimeError('Incomplete SAC header: ' + str(path))
                    endian = next((e for e in ('<', '>') if struct.unpack_from(e+'i', header, 304)[0] in (6, 7)), None)
                    if endian is None:
                        raise RuntimeError('Invalid SAC header: ' + str(path))
                    npts = struct.unpack_from(endian+'i', header, 316)[0]
                    delta = struct.unpack_from(endian+'f', header, 0)[0]
                    begin = struct.unpack_from(endian+'f', header, 20)[0]
                    if npts < 1 or not math.isfinite(delta) or delta <= 0 or not math.isfinite(begin):
                        raise RuntimeError('Invalid SAC sampling: ' + str(path))
                    values = stream.read(npts*4)
                    if len(values) != npts*4 or not all(math.isfinite(v[0]) for v in struct.iter_unpack(endian+'f', values)):
                        raise RuntimeError('Incomplete/nonfinite SAC samples: ' + str(path))
                    current = (npts, delta, begin)
                    if grid is not None and current != grid:
                        raise RuntimeError('Inconsistent component sampling: ' + str(path))
                    grid = current
                count += 1
    return output, count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case-root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--print-path', action='store_true')
    args = parser.parse_args()
    try:
        output, count = validate(args.case_root.resolve())
    except (OSError, ValueError, RuntimeError) as exc:
        parser.exit(1, '1-D reuse compatibility check failed: %s\n' % exc)
    if args.print_path:
        print(output)
    else:
        print('Compatible existing 1-D synthetics: %s (%d SAC files); no recombination performed.' % (output, count))


if __name__ == '__main__':
    main()
