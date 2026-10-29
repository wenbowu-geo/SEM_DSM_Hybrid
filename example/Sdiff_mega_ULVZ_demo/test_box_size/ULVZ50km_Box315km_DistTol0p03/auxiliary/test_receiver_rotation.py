"""Regression checks against an independent Cartesian great-circle frame."""
import math
from array import array
from contextlib import contextmanager
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import assemble_3d_sem_dsm_synthetics as assembly
import rotate_synthetics_zrt as rotation


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def receiver_frame(lat, lon):
    lat, lon = math.radians(lat), math.radians(lon)
    up = (math.cos(lat)*math.cos(lon), math.cos(lat)*math.sin(lon), math.sin(lat))
    north = (-math.sin(lat)*math.cos(lon), -math.sin(lat)*math.sin(lon), math.cos(lat))
    east = (-math.sin(lon), math.cos(lon), 0.0)
    source = (1.0, 0.0, 0.0)  # Fixture source is at (0, 0).
    radial = tuple(dot(source, up)*u-s for u, s in zip(up, source))
    length = math.sqrt(dot(radial, radial))
    radial = tuple(x/length for x in radial)
    return north, east, radial, cross(up, radial)


@contextmanager
def in_directory(path):
    previous = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(previous)


class ReceiverRotationTests(unittest.TestCase):
    def test_cardinal_polarities_and_receiver_bearing(self):
        self.assertAlmostEqual(assembly.receiver_radial_azimuth_deg(0, 0, 45, 0), 0)
        self.assertAlmostEqual(assembly.receiver_radial_azimuth_deg(0, 0, 0, 45), 90)
        for lat, lon in [(30, 60), (-30, 60), (20, -70)]:
            north, east, radial, transverse = receiver_frame(lat, lon)
            angle = math.radians(assembly.receiver_radial_azimuth_deg(0, 0, lat, lon))
            self.assertAlmostEqual(math.cos(angle), dot(radial, north))
            self.assertAlmostEqual(math.sin(angle), dot(radial, east))
            self.assertAlmostEqual(math.sin(angle), dot(transverse, north))
            self.assertAlmostEqual(-math.cos(angle), dot(transverse, east))

    def test_assembly_and_rotation_samples_and_headers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'DATA').mkdir()
            (root/'DATA/CMTSOLUTION').write_text('latitude: 0\nlongitude: 0\nMrr: 1\nMtt: 1\nMpp: 1\nMrt: 0\nMrp: 0\nMtp: 0\n')
            stations = [(45, 0), (0, 45), (30, 60), (-30, 60)]
            (root/'DATA/tele_station.txt').write_text(''.join(f'XX R{i} {lon} {lat}\n' for i, (lat, lon) in enumerate(stations)))
            (root/'metadata.env').write_text('TIME_START_CUT=0\n')
            one_d = root/'reference'; coupling = root/'coupling'
            one_d.mkdir(); coupling.mkdir()
            signals = {'z': [3., -4., 5.], 'r': [1., 0., 1.], 't': [0., 1., 2.]}
            scatter = {'z': [0.1, 0.2, 0.3], 'n': [0.2, 0.4, 0.6], 'e': [-0.3, -0.6, -0.9]}
            for i in range(len(stations)):
                for target, traces in [(one_d, signals), (coupling, scatter)]:
                    for component, samples in traces.items():
                        header = bytearray(632)
                        assembly.set_sac_float(header, 0, 1)
                        assembly.set_sac_int(header, 6, 6)
                        trace = array('f', samples)
                        assembly.refresh_sac_header(header, trace, 0)
                        suffix = '_dep0' if target == one_d else ''
                        assembly.write_sac(target/f'XX_R{i}{suffix}.bh{component}', header, trace)
            with in_directory(root), patch.object(sys, 'argv', ['assembly', '--one-d-dir', str(one_d), '--coupling-dir', str(coupling), '--metadata', 'metadata.env']):
                assembly.main()
            with patch.object(rotation, 'ROOT', root), patch.object(sys, 'argv', ['rotation']):
                rotation.main()
            for i, (lat, lon) in enumerate(stations):
                north, east, radial, transverse = receiver_frame(lat, lon)
                a = math.degrees(math.atan2(dot(radial, east), dot(radial, north))) % 360
                for component, az in [('z', 0), ('r', a), ('t', (a-90)%360)]:
                    header, trace = assembly.read_sac(root/f'OUTPUT_FILES/3D_SEM_DSM_ZRT/XX_R{i}.bh{component}')
                    self.assertAlmostEqual(assembly.sac_float(header, 57), az, places=4)
                    self.assertEqual(assembly.sac_float(header, 58), 0 if component=='z' else 90)
                    self.assertEqual(header[600:608].decode().strip(), 'BH'+component.upper())
                    self.assertEqual(assembly.sac_float(header, 31), lat)
                    self.assertEqual(assembly.sac_float(header, 32), lon)
                    for j, sample in enumerate(trace):
                        if component=='z':
                            expected = signals['z'][j]+scatter['z'][j]
                        else:
                            axis = radial if component=='r' else transverse
                            expected = signals[component][j]+scatter['n'][j]*dot(axis,north)+scatter['e'][j]*dot(axis,east)
                        self.assertAlmostEqual(sample, expected, places=6)
                    _, reference = assembly.read_sac(root/f'OUTPUT_FILES/1D_DSM_ZRT/XX_R{i}.bh{component}')
                    self.assertEqual(list(reference), signals[component])
                for component, az in [('n', 0), ('e', 90)]:
                    header, _ = assembly.read_sac(root/f'OUTPUT_FILES/3D_SEM_DSM/XX_R{i}.bh{component}')
                    self.assertEqual(assembly.sac_float(header, 57), az)
                    self.assertEqual(assembly.sac_float(header, 58), 90)


if __name__ == '__main__':
    unittest.main()
