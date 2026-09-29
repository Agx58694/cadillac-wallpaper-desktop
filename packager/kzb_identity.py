#!/usr/bin/env python3
"""Namespace an existing, complete wallpaper; never regenerate its artwork.

This is a post-build step for the audited KZBF 27.0 profile. It uses the existing
KzbBinary/rebuild_kzb engine and the native Prefab field reader. Unsupported
literal encodings fail closed. Shared engine and installer sources stay intact.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import stat
import struct
import zipfile
from pathlib import Path

if __package__:
    from . import cadillac_wallpaper_packager as packager
    from . import kzb_astc_patcher as astc
    from . import kzb_native as engine
    from . import native_prefab_layout as layout
else:
    import cadillac_wallpaper_packager as packager
    import kzb_astc_patcher as astc
    import kzb_native as engine
    import native_prefab_layout as layout
from PIL import Image

MAX_BYTES = 512 * 1024 * 1024
THEME_DICTIONARIES = {'/Themes/Theme/DefaultValues', '/Themes/Theme/theme_dark', '/Themes/Theme/theme_light'}
URL_PROPERTIES = {
    '/Brushes/': {'MaterialBrush.Material'},
    '/Materials/': {'maskTex', 'Texture'},
    '/State Managers/': {'maskTex'},
    '/Render Pass Prefabs/': {'BlitRenderPass.Material'},
    '/Themes/Theme': {'ResourceDictionarySelector.SelectedDictionary'},
}
# Ordered resource names and type indexes, with the project-specific suffix
# normalized, from the bundled football template and the vehicle-accepted V7
# structural profile (V8 has the same layout). Artwork bytes may vary.
SUPPORTED_RESOURCE_LAYOUTS = {
    '0a9f1fdd265ddad822df52cecc57672446860769ab21f42c4bc18b067756a1c8': 'football-static',
    '0fd4b4e5218fc4931e7eeb759c228a0b87f027b225a4607588c6092bfd0afd90': 'winter-v7-dynamic',
}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def resource_layout_profile(kzb):
    identity = kzb.project_name.removeprefix('cadi_wallpaper_')
    ordered = [(entry.path.replace(identity, '<id>'), entry.path_index, entry.parent_index)
               for entry in kzb.entries]
    fingerprint = sha(json.dumps(ordered, separators=(',', ':')).encode())
    require(fingerprint in SUPPORTED_RESOURCE_LAYOUTS,
            f'Unsupported KZB resource layout: {fingerprint}')
    return SUPPORTED_RESOURCE_LAYOUTS[fingerprint]


def validate_compatibility_structure(kzb, prefab, profile):
    """Check the host-facing layout preserved by the two audited profiles."""
    identity = kzb.project_name.removeprefix('cadi_wallpaper_')
    root = prefab['root']
    require(root['metaclass'] == 'Kanzi.EmptyNode2D' and len(root['children']) == 1,
            'Unsupported wallpaper scene tree')
    bg = root['children'][0]
    require(root['name'] == f'BackGround_{identity}' and bg['name'] == 'bg' and
            bg['metaclass'] == 'Kanzi.Image2D' and not bg['children'],
            'Unsupported background node layout')
    root_props = {item['property']: item['value'] for item in root['properties']['values']}
    bg_props = {item['property']: item['value'] for item in bg['properties']['values']}
    require((root_props.get('Node.Width'), root_props.get('Node.Height')) == (8960.0, 1320.0),
            'Native full-canvas root changed or unsupported')
    require('Node.Width' not in bg_props and 'Node.Height' not in bg_props,
            'Background must keep native automatic layout')
    require([item['target'] for item in root['bindings']] ==
            ['Wallpaper.wallpaperState', 'Node.Visible', 'useMask', 'Theme.maskMode'],
            'Wallpaper state or mask bindings changed')
    require([item['target'] for item in bg['bindings']] == ['Texture', 'useMask', 'Theme.maskMode'],
            'Background texture or mask bindings changed')
    expected_sources = ('BackgroundEV.DayType_EV', 'Background.DayType', 'Background.DayType_Avneir')
    require(len(root['components']) == 3, 'Expected three day/night triggers')
    for trigger, source in zip(root['components'], expected_sources):
        props = {item['property']: item['value'] for item in trigger['properties']['values']}
        actions = trigger['actions']
        require(trigger['metaclass'] == 'Kanzi.OnPropertyChangedTrigger' and
                props.get('OnPropertyChangedTrigger.SourceNode') == '..' and
                props.get('OnPropertyChangedTrigger.SourcePropertyType') == source and
                props.get('OnPropertyChangedTrigger.IgnoreInitialValue') == 0 and
                props.get('OnPropertyChangedTrigger.IgnoreIdenticalValue') == 0 and
                len(actions) == 1 and actions[0]['metaclass'] == 'Kanzi.SetPropertyAction' and
                len(actions[0]['bindings']) == 1 and
                actions[0]['bindings'][0]['target'] == 'BackgroundEV.DayType_EV' and
                actions[0]['bindings'][0]['source_property'] == source,
                f'Day/night trigger changed: {source}')
    if profile == 'football-static':
        require(not bg['components'], 'Static template unexpectedly contains an animation')
    else:
        require(len(bg['components']) == 1 and bg['components'][0]['metaclass'] == 'Kanzi.AnimationPlayer',
                'Dynamic template AnimationPlayer missing')
        props = {item['property']: item['value'] for item in bg['components'][0]['properties']['values']}
        require(props.get('AnimationPlayer.AutoplayEnabled') == 1 and
                props.get('AnimationPlayer.RepeatCount') == 0 and
                props.get('AnimationPlayer.Timeline', '').startswith('kzb://' + kzb.project_name + '/'),
                'Dynamic template playback configuration changed')
    dictionaries = {}
    for path in THEME_DICTIONARIES:
        fields = theme_fields(kzb.resource(path))
        dictionary = dict(zip((item['text'] for item in fields[::2]),
                              (item['text'] for item in fields[1::2])))
        require(set(dictionary) == {'KzMotion_PrefabUrl', 'wallpaperTwo_full',
                                    'wallpaperTwo_blur', 'wallpaperTwo_dic'},
                f'Theme dictionary keys changed: {path}')
        require(dictionary['KzMotion_PrefabUrl'] ==
                f'kzb://{kzb.project_name}/Prefabs/BackGround_{identity}',
                f'Theme entry Prefab changed: {path}')
        dictionaries[path] = dictionary
    require(dictionaries['/Themes/Theme/DefaultValues'] == dictionaries['/Themes/Theme/theme_dark'],
            'Default and dark theme mappings differ')
    require(all(dictionaries['/Themes/Theme/theme_light'][key] !=
                dictionaries['/Themes/Theme/theme_dark'][key]
                for key in ('wallpaperTwo_full', 'wallpaperTwo_blur', 'wallpaperTwo_dic')),
            'Day/night textures are not distinct')


def theme_fields(data):
    """Version/properties/bindings prefix, then counted NUL key/value pairs."""
    require(len(data) >= 20 and data[:16] == bytes(16), 'Unsupported theme dictionary prefix')
    count = struct.unpack_from('<I', data, 16)[0]
    require(count <= (len(data) - 20) // 2, 'Truncated theme dictionary')
    fields, pos = [], 20
    for i in range(count * 2):
        end = data.find(b'\0', pos)
        require(end >= 0, 'Unterminated theme dictionary string')
        fields.append({'start': pos, 'end': end + 1, 'text': data[pos:end].decode('utf-8'),
                       'encoding': 'nul', 'field': f'pair[{i // 2}].' + ('key' if i % 2 == 0 else 'value')})
        pos = end + 1
    require(pos == len(data), 'Unexpected theme dictionary tail')
    keys = [f['text'] for f in fields[::2]]
    require(len(keys) == len(set(keys)), 'Duplicate theme dictionary key')
    return fields


def literal_fields(kzb, path):
    """Read string-bearing fields without searching/replacing arbitrary bytes.

    The two NUL dictionary formats and complete Prefab use structured parsers.
    Remaining literal URLs use the observed property-index/u32-byte-length
    encoding. Accept only known property types and exact in-package URLs; the
    inverse rebuild below proves every other byte is preserved.
    """
    data = kzb.resource(path)
    if path.startswith('/Resource Files/Images/'):
        # ASTC/PNG payload is opaque; incidental byte sequences are not URLs.
        return []
    if path == '/$strings':
        fields, pos = [], 4
        for i, value in enumerate(kzb.strings()):
            end = pos + len(value.encode('utf-8')) + 1
            fields.append({'start': pos, 'end': end, 'text': value, 'encoding': 'nul', 'field': f'string[{i}]'})
            pos = end
        return fields
    if path in THEME_DICTIONARIES:
        return theme_fields(data)
    if path.startswith('/Prefabs/'):
        parsed = layout.parse_prefab(kzb, data)
        return [{'start': f['offset'] - 4, 'end': f['end'], 'text': f['value'], 'encoding': 'sized', 'field': f['field']}
                for f in parsed['fields'] if isinstance(f['value'], str)]
    properties = engine._decode_dictionary(kzb.resource('/$property_dictionary'))
    fields, pos = [], 0
    while (pos := data.find(b'kzb://', pos)) >= 0:
        require(pos >= 8, f'Missing literal URL header: {path}')
        prop_index, length = struct.unpack_from('<II', data, pos - 8)
        require(prop_index < len(properties), f'Invalid property index: {path}')
        prop = properties[prop_index]
        allowed = set().union(*(v for k, v in URL_PROPERTIES.items() if path.startswith(k)))
        require(prop in allowed, f'Unsupported literal URL property {path}: {prop}')
        require(6 < length <= 4096 and pos + length <= len(data), f'Invalid URL byte length: {path}')
        value = data[pos:pos + length].decode('utf-8')
        require('\0' not in value and value.startswith('kzb://'), f'Invalid sized URL: {path}')
        fields.append({'start': pos - 4, 'end': pos + length, 'text': value, 'encoding': 'sized', 'field': prop})
        pos += length
    return fields


def rewrite_payload(kzb, path, old_id, new_id):
    data = kzb.resource(path)
    output, cursor = bytearray(), 0
    for field in literal_fields(kzb, path):
        require(field['start'] >= cursor, 'Overlapping string fields')
        output.extend(data[cursor:field['start']])
        text = field['text'].replace(old_id, new_id).encode('utf-8')
        if field['encoding'] == 'nul':
            output.extend(text + b'\0')
        else:
            output.extend(struct.pack('<I', len(text)) + text)
        cursor = field['end']
    output.extend(data[cursor:])
    if not path.startswith('/Resource Files/Images/'):
        require(old_id.encode() not in output, f'Unclassified identity literal in {path}')
    return bytes(output)


def validate_kzb(data):
    kzb = engine.KzbBinary(data)
    require((kzb.version_major, kzb.version_minor) == (27, 0), 'Only audited KZBF 27.0 is supported')
    require(re.fullmatch(r'cadi_wallpaper_[A-Za-z0-9_-]+', kzb.project_name), 'Unsupported project name')
    require(len(kzb.paths) == len(set(kzb.paths)), 'Duplicate resource path')
    profile = resource_layout_profile(kzb)
    end = kzb.directory_end
    for entry in kzb.entries:
        require(entry.offset == (end + 3) & ~3, f'Invalid alignment or resource overlap: {entry.path}')
        require(not any(data[end:entry.offset]), 'Nonzero resource alignment padding')
        require(entry.compression == 0 and entry.raw_size == entry.size, 'Unsupported compressed resource')
        require(entry.offset + entry.size <= len(data), 'Truncated resource')
        end = entry.offset + entry.size
    require(end == len(data), 'Unexpected trailing KZB bytes')
    strings = kzb.strings()
    references = []
    prefix = f'kzb://{kzb.project_name}'
    for path in kzb.paths:
        for field in literal_fields(kzb, path):
            value = field['text']
            if 'kzb://' in value:
                require(value.startswith(prefix + '/'), f'Foreign/malformed KZB reference: {value}')
                target = value[len(prefix):]
                require(target in kzb.paths, f'Dangling resource reference: {value}')
                references.append({'resource': path, 'field': field['field'], 'offset': field['start'], 'target': value})
        if path.startswith('/Textures/'):
            resource = kzb.resource(path)
            require(len(resource) == 36 and struct.unpack_from('<8I', resource) == (0, 0, 0, 1, 1, 0, 2, 1),
                    f'Unsupported texture descriptor: {path}')
            index = struct.unpack_from('<I', resource, 32)[0]
            require(index < len(strings) and strings[index].startswith(prefix + '/Resource Files/Images/'),
                    f'Invalid texture image index: {path}')
        if path.startswith('/Materials/'):
            require(kzb.material_type_url(path).startswith(prefix + '/Material Types/'), 'Invalid material type reference')
        if path.startswith('/Material Types/'):
            kzb.material_type(path)
    identity = kzb.project_name.removeprefix('cadi_wallpaper_')
    prefab_path = f'/Prefabs/BackGround_{identity}'
    parsed = layout.parse_prefab(kzb, kzb.resource(prefab_path))
    validate_compatibility_structure(kzb, parsed, profile)
    require(references, 'Empty resource reference graph')
    return kzb, references, parsed


def rename_core(data, new_id):
    require(re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,95}', new_id), 'Invalid internal ID')
    source = engine.KzbBinary(data)
    old_id = source.project_name.removeprefix('cadi_wallpaper_')
    require(old_id != new_id and new_id not in source.project_name, 'Internal ID must change')
    paths = tuple(path.replace(old_id, new_id) for path in source.paths)
    require(len(paths) == len(set(paths)), 'Renaming would collide with another resource')
    replacements = {path: rewrite_payload(source, path, old_id, new_id) for path in source.paths}
    # Existing engine updates every resource size and offset after string growth.
    rebuilt = engine.KzbBinary(engine.rebuild_kzb(data, replacements))
    project = f'cadi_wallpaper_{new_id}'.encode('utf-8')
    header = bytearray(b'KZBF' + struct.pack('<II', rebuilt.version_major, len(project)) + project)
    header.extend(struct.pack('<II', rebuilt.version_minor, len(paths)))
    for path in paths:
        header.extend(path.encode('utf-8') + b'\0')
    header.extend(struct.pack('<I', len(paths)))
    # Only the namespace envelope is new. Shift the rebuilt payload as one block,
    # retaining its four-byte alignment and resource/string table index order.
    new_start = (len(header) + len(paths) * 24 + 3) & ~3
    old_start = rebuilt.entries[0].offset
    shift = new_start - old_start
    for entry in rebuilt.entries:
        header.extend(struct.pack('<6I', entry.path_index, entry.parent_index, entry.offset + shift,
                                  entry.size, entry.compression, entry.raw_size))
    header.extend(bytes(new_start - len(header)))
    result = bytes(header) + rebuilt.data[old_start:]
    require(all(old_id not in p for p in paths), 'Old identity remains in resource names')
    return result


def rename_kzb(data, new_id):
    source, old_refs, old_prefab = validate_kzb(data)
    old_id = source.project_name.removeprefix('cadi_wallpaper_')
    result = rename_core(data, new_id)
    renamed, refs, prefab = validate_kzb(result)
    require(len(source.entries) == len(renamed.entries), 'Resource count changed')
    require(tuple(s.replace(old_id, new_id) for s in source.strings()) == renamed.strings(), 'String index order changed')
    require(rename_core(result, old_id) == engine.rebuild_kzb(data), 'Inverse namespace rebuild changed original data')
    mapping = []
    for before, after in zip(source.entries, renamed.entries):
        require(before.path.replace(old_id, new_id) == after.path, 'Resource order changed')
        require((before.path_index, before.parent_index, before.compression) ==
                (after.path_index, after.parent_index, after.compression), 'Resource indices/type changed')
        a, b = source.resource(before.path), renamed.resource(after.path)
        if before.path.startswith(('/Resource Files/Images/', '/Textures/', '/Material Types/', '/Animation')):
            require(a == b, f'Artwork/shader/animation bytes changed: {before.path}')
        mapping.append({'old_path': before.path, 'new_path': after.path, 'path_index': after.path_index,
                        'type_index': after.parent_index, 'old_offset': before.offset, 'new_offset': after.offset,
                        'old_bytes': len(a), 'new_bytes': len(b), 'old_sha256': sha(a), 'new_sha256': sha(b),
                        'byte_identical': a == b})
    old_records, new_records = astc.find_texture_records(data), astc.find_texture_records(result)
    require(len(old_records) == len(new_records) == 7, 'Expected seven native ASTC image records')
    textures = []
    for a, b in zip(old_records, new_records):
        original, changed = data[a.header_offset:a.payload_end], result[b.header_offset:b.payload_end]
        require(original == changed, 'ASTC header or image payload changed')
        textures.append({'index': a.index, 'size': [8960, 1320], 'header_and_payload_sha256': sha(changed),
                         'payload_sha256': sha(result[b.payload_start:b.payload_end]), 'byte_identical': True})
    require(len(old_refs) == len(refs), 'Reference count changed')
    require([r['target'].replace(old_id, new_id) for r in old_refs] == [r['target'] for r in refs], 'Reference graph changed')
    root_props = {p['property']: p['value'] for p in prefab['root']['properties']['values']}
    require((root_props.get('Node.Width'), root_props.get('Node.Height')) == (8960.0, 1320.0),
            'Native full-canvas root changed or unsupported')
    return result, {'old_project': source.project_name, 'new_project': renamed.project_name,
                    'old_internal_id': old_id, 'new_internal_id': new_id,
                    'template_profile': resource_layout_profile(renamed),
                    'old_kzb_sha256': sha(data), 'new_kzb_sha256': sha(result),
                    'resource_count': len(mapping), 'string_count': len(renamed.strings()),
                    'reference_count': len(refs), 'unique_reference_count': len({r['target'] for r in refs}),
                    'references': refs, 'resources': mapping, 'astc': textures,
                    'inverse_rebuild_byte_identical': True, 'no_old_identity_remaining': True,
                    'prefab_bytes_consumed': prefab['bytes_consumed'],
                    'old_prefab_bytes_consumed': old_prefab['bytes_consumed'],
                    'native_canvas': [8960, 1320], 'join_x': 5010}


def read_source(path):
    path = Path(path)
    require(path.is_file() and path.stat().st_size <= MAX_BYTES, 'Source ZIP missing or exceeds 512 MiB')
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names = [i.filename for i in infos]
        require(len(infos) <= 128 and len(set(names)) == len(infos), 'Duplicate or excessive ZIP entries')
        require(sum(i.file_size for i in infos) <= MAX_BYTES, 'Expanded source exceeds 512 MiB')
        for info in infos:
            name = info.filename
            require(name and not name.startswith('/') and '\\' not in name and ':' not in name and
                    all(part not in ('', '.', '..') for part in name.rstrip('/').split('/')),
                    f'Unsafe ZIP path: {name}')
            require(not (info.flag_bits & 1), f'Encrypted ZIP entry: {name}')
            require(not stat.S_ISLNK((info.external_attr >> 16) & 0xffff), f'Symlink ZIP entry: {name}')
            require(info.file_size >= 0 and info.file_size <= MAX_BYTES,
                    f'Invalid ZIP entry size: {name}')
        files = [i.filename for i in infos if not i.is_dir()]
        require(len(files) == 9, f'Expected exactly nine wallpaper files, found {len(files)}')
        previews = [name for name in files if name.endswith('/light_preview_image.png')]
        require(len(previews) == 1, 'Expected one wallpaper')
        root = previews[0].removesuffix('light_preview_image.png')
        require(re.fullmatch(r'[A-Fa-f0-9]{32}/cadi_wallpaper[A-Za-z0-9_-]*/', root), 'Unsupported source root')
        kzb_paths = [name for name in files if name.endswith('.kzb')]
        require(len(kzb_paths) == 1 and re.fullmatch(root + r'ipd/wallpaper/cadi_wallpaper_[A-Za-z0-9_-]+\.kzb',
                                                      kzb_paths[0]), 'Expected one IPD KZB')
        expected = {root + name for name in packager.PNG_TARGET_SIZES} | set(kzb_paths)
        require(set(files) == expected, 'Unexpected or missing wallpaper file')
        require(all(any(file.startswith(name) for file in files) for name in names if name.endswith('/')),
                'ZIP contains unrelated directory')
        pngs = {name: archive.read(root + name) for name in packager.PNG_TARGET_SIZES}
        for name, data in pngs.items():
            with Image.open(io.BytesIO(data)) as image:
                image.load()
                require(image.format == 'PNG' and image.size == packager.PNG_TARGET_SIZES[name], f'Wrong PNG dimensions: {name}')
        kzb = archive.read(kzb_paths[0])
        require(archive.testzip() is None, 'Source ZIP CRC failed')
        return kzb, pngs, kzb_paths[0]


def content_identity(theme_key, kzb, pngs):
    require(re.fullmatch(r'[a-z][a-z0-9_]{0,31}', theme_key), 'Invalid theme key')
    hashes = {'kzb': sha(kzb), **{name: sha(data) for name, data in sorted(pngs.items())}}
    manifest = {'identity_schema': 1, 'theme': theme_key, 'resources': hashes}
    digest = sha(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode())
    return f'{theme_key}_{digest[:24]}', digest, hashes


def build_package(source, theme_key, version, output, report_path):
    require(re.fullmatch(r'[A-Za-z0-9_-]+', version), 'Invalid wallpaper version')
    source = source.resolve()
    require(source != output.resolve(), 'Do not overwrite source wallpaper')
    require(source.stat().st_size <= MAX_BYTES, 'Source ZIP exceeds 512 MiB')
    source_hash = sha(source.read_bytes())
    original, pngs, original_kzb_name = read_source(source)
    new_id, content_sha, content_hashes = content_identity(theme_key, original, pngs)
    renamed, report = rename_kzb(original, new_id)
    outer_id = sha(('cadillac-ota-identity-v1:' + new_id).encode())[:32].upper()
    folder = 'cadi_wallpaper_' + version
    root = outer_id + '/' + folder + '/'
    kzb_name = 'ipd/wallpaper/cadi_wallpaper_' + new_id + '.kzb'
    members = {**pngs, kzb_name: renamed}
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, payload in members.items():
            path = root + name
            require(len(path) <= 240 and re.fullmatch(r'[A-Za-z0-9_./-]+', path), 'Invalid output path')
            info = zipfile.ZipInfo(path, (2026, 9, 22, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system, info.external_attr = 3, 0o100644 << 16
            archive.writestr(info, payload, compresslevel=9)
    raw = buffer.getvalue()
    require(len(raw) <= MAX_BYTES and sum(map(len, members.values())) <= MAX_BYTES, 'Output exceeds 512 MiB')
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        require(archive.testzip() is None and len(archive.infolist()) == 9, 'Invalid output ZIP')
        actual = archive.read(root + kzb_name)
        validate_kzb(actual)
        require(actual == renamed, 'Written KZB differs')
        png_report = []
        for name, before in pngs.items():
            after = archive.read(root + name)
            require(after == before, 'PNG bytes changed')
            with Image.open(io.BytesIO(after)) as image:
                pixels = image.convert('RGBA').tobytes()
                png_report.append({'path': name, 'size': list(image.size), 'file_sha256': sha(after),
                                   'rgba_sha256': sha(pixels), 'byte_identical': True})
    report.update({'source': source.name, 'source_zip_sha256': source_hash,
                   'source_kzb_path': original_kzb_name, 'output': output.name,
                   'zip_sha256': sha(raw), 'zip_bytes': len(raw), 'expanded_bytes': sum(map(len, members.values())),
                   'zip_entries': len(members), 'outer_id': outer_id, 'folder': folder,
                   'kzb_path': root + kzb_name, 'content_sha256': content_sha, 'content_hashes': content_hashes,
                   'pngs': png_report, 'vehicle_no_restart_verified': False,
                   'actual_importer_verified': False, 'artwork_effect_daynight_mask_preserved': True})
    require(not output.exists() or output.read_bytes() == raw, 'Refusing to overwrite a different release')
    require(not report_path.exists(), 'Report already exists; use a new report path')
    output.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    if not output.exists():
        with output.open('xb') as stream:
            stream.write(raw)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--input', type=Path, required=True)
    cli.add_argument('--theme-key', required=True)
    cli.add_argument('--version', required=True)
    cli.add_argument('--output', type=Path, required=True)
    cli.add_argument('--report', type=Path, required=True)
    args = cli.parse_args()
    report = build_package(args.input, args.theme_key, args.version, args.output, args.report)
    print(json.dumps({k: report[k] for k in ('output', 'new_internal_id', 'zip_sha256', 'zip_bytes',
                                           'resource_count', 'reference_count')}, indent=2))
