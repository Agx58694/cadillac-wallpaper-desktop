"""Regression checks for the public template and an optional local V7 fixture.

Set CADILLAC_V7_FIXTURE to a locally held, accepted V7 ZIP to exercise the
dynamic structural profile without distributing that wallpaper in this repo.
"""

from __future__ import annotations

import json
import os
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from packager import kzb_identity as identity


TEMPLATE = Path(__file__).resolve().parents[1] / 'templates/BFA3A0F4596C4C57A6BCDC1EB3348932.zip'


class IdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source, cls.pngs, _ = identity.read_source(TEMPLATE)
        cls.parsed = identity.engine.KzbBinary(cls.source)
        cls.old_id = cls.parsed.project_name.removeprefix('cadi_wallpaper_')

    def test_static_daynight_identity_rebuild_is_reversible(self):
        for new_id in ('s7', 'static_daynight_with_a_longer_identity_0123456789abcdef'):
            with self.subTest(new_id=new_id):
                changed, report = identity.rename_kzb(self.source, new_id)
                self.assertNotEqual(len(changed), len(self.source))
                self.assertTrue(report['inverse_rebuild_byte_identical'])
                self.assertTrue(all(item['byte_identical'] for item in report['astc']))
                self.assertEqual(identity.rename_core(changed, self.old_id),
                                 identity.engine.rebuild_kzb(self.source))
                kzb, references, prefab = identity.validate_kzb(changed)
                self.assertEqual(identity.resource_layout_profile(kzb), 'football-static')
                self.assertEqual(prefab['bytes_consumed'], prefab['bytes'])
                self.assertEqual([binding['target'] for binding in prefab['root']['bindings']],
                                 ['Wallpaper.wallpaperState', 'Node.Visible', 'useMask', 'Theme.maskMode'])
                self.assertEqual(len(prefab['root']['components']), 3)
                self.assertEqual(len(prefab['root']['children'][0]['bindings']), 3)
                self.assertTrue(all(ref['target'].startswith('kzb://' + kzb.project_name + '/')
                                    for ref in references))

    def test_identity_is_stable_for_content_and_changes_with_artwork(self):
        original = identity.content_identity('static', self.source, self.pngs)[0]
        self.assertEqual(original, identity.content_identity('static', self.source, self.pngs)[0])
        self.assertNotEqual(original, identity.content_identity('other', self.source, self.pngs)[0])
        revised = dict(self.pngs)
        revised['light_preview_image.png'] += b'content revision'
        self.assertNotEqual(original, identity.content_identity('static', self.source, revised)[0])

    def test_output_is_nine_files_with_new_project_and_original_png_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'out.zip'
            report_path = Path(directory) / 'report.json'
            with self.assertRaisesRegex(ValueError, 'Output ZIP and report paths must differ'):
                identity.build_package(TEMPLATE, 'static', 'v1', output, output)
            self.assertFalse(output.exists())
            report = identity.build_package(TEMPLATE, 'static', 'v1', output, report_path)
            self.assertEqual(report['zip_entries'], 9)
            self.assertEqual(report['template_profile'], 'football-static')
            self.assertTrue(report['inverse_rebuild_byte_identical'])
            self.assertEqual(json.loads(report_path.read_text())['zip_sha256'], report['zip_sha256'])
            kzb, pngs, kzb_path = identity.read_source(output)
            self.assertEqual(pngs, self.pngs)
            self.assertIn(report['new_internal_id'], kzb_path)
            self.assertEqual(identity.engine.KzbBinary(kzb).project_name, report['new_project'])
            with self.assertRaisesRegex(ValueError, 'Report already exists'):
                identity.build_package(TEMPLATE, 'static', 'v1', output, report_path)

    def test_zip_path_traversal_and_unrelated_directory_are_rejected(self):
        root = 'A' * 32 + '/cadi_wallpaper_test/'
        names = [root + name for name in identity.packager.PNG_TARGET_SIZES]
        names += [root + 'ipd/wallpaper/cadi_wallpaper_test.kzb']
        for bad in ('../escape.png', '/absolute.png', 'bad\\separator.png'):
            with self.subTest(bad=bad), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'bad.zip'
                with zipfile.ZipFile(path, 'w') as archive:
                    for name in names[1:]:
                        archive.writestr(name, b'x')
                    archive.writestr(bad, b'x')
                # Windows zipfile normalizes a written backslash to '/'. The
                # resulting entry is still rejected as outside the package.
                expected = ('Unexpected or missing wallpaper file'
                            if os.name == 'nt' and '\\' in bad else 'Unsafe ZIP path')
                with self.assertRaisesRegex(ValueError, expected):
                    identity.read_source(path)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'extra-directory.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                for name in names:
                    archive.writestr(name, b'x')
                archive.writestr('unrelated/', b'')
            with self.assertRaisesRegex(ValueError, 'unrelated directory'):
                identity.read_source(path)

    def test_bad_directory_offsets_and_unknown_resource_layout_are_rejected(self):
        source = bytearray(self.source)
        directory = self.parsed.directory_end - len(self.parsed.entries) * 24
        struct.pack_into('<I', source, directory + 24 + 8, self.parsed.entries[0].offset)
        with self.assertRaisesRegex(ValueError, 'overlap'):
            identity.validate_kzb(bytes(source))
        source = bytearray(self.source)
        offset = source.index(b'/Prefabs/BackGround_') + 1
        source[offset] = ord('Q')
        with self.assertRaisesRegex(ValueError, 'Unsupported KZB resource layout'):
            identity.validate_kzb(bytes(source))

    def test_unresolved_reference_and_unclassified_literal_are_rejected(self):
        values = list(self.parsed.strings())
        index = next(i for i, value in enumerate(values) if value.startswith('kzb://'))
        values[index] = f'kzb://{self.parsed.project_name}/Missing/Resource'
        corrupted = identity.engine.rebuild_kzb(
            self.source, {'/$strings': identity.engine._encode_dictionary(values)})
        with self.assertRaisesRegex(ValueError, 'Dangling resource'):
            identity.validate_kzb(corrupted)
        path = '/Materials/Blur'
        corrupted = identity.engine.rebuild_kzb(
            self.source, {path: self.parsed.resource(path) + self.old_id.encode()})
        with self.assertRaisesRegex(ValueError, 'Unclassified identity'):
            identity.rename_core(corrupted, 'new_theme')

    def test_bad_sized_url_and_daynight_trigger_are_rejected(self):
        path = '/Brushes/DigHole'
        body = bytearray(self.parsed.resource(path))
        position = body.index(b'kzb://')
        struct.pack_into('<I', body, position - 4, 0xffffffff)
        corrupted = identity.engine.rebuild_kzb(self.source, {path: bytes(body)})
        with self.assertRaisesRegex(ValueError, 'URL byte length'):
            identity.validate_kzb(corrupted)
        path = '/Prefabs/BackGround_' + self.old_id
        body = self.parsed.resource(path)
        before, after = b'Background.DayType_Avneir', b'Background.DayType_Avneix'
        self.assertIn(before, body)
        corrupted = identity.engine.rebuild_kzb(self.source, {path: body.replace(before, after, 1)})
        with self.assertRaisesRegex(ValueError, 'Day/night trigger changed'):
            identity.validate_kzb(corrupted)

    def test_optional_local_v7_preserves_animation_and_bindings(self):
        fixture = os.environ.get('CADILLAC_V7_FIXTURE')
        if not fixture:
            self.skipTest('Set CADILLAC_V7_FIXTURE to a locally held accepted V7 ZIP')
        source, _, _ = identity.read_source(Path(fixture))
        changed, report = identity.rename_kzb(source, 'v7_regression_0123456789abcdef')
        self.assertEqual(report['template_profile'], 'winter-v7-dynamic')
        self.assertTrue(report['inverse_rebuild_byte_identical'])
        self.assertTrue(all(item['byte_identical'] for item in report['astc']))
        _, _, prefab = identity.validate_kzb(changed)
        self.assertEqual(prefab['bytes_consumed'], prefab['bytes'])
        self.assertEqual([item['metaclass'] for item in prefab['root']['children'][0]['components']],
                         ['Kanzi.AnimationPlayer'])
        self.assertEqual(len(prefab['root']['bindings']), 4)
        self.assertEqual(len(prefab['root']['components']), 3)


if __name__ == '__main__':
    unittest.main()
