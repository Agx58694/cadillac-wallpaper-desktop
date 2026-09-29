#!/usr/bin/env python3
"""Fail-closed layout reader for the audited wallpaper Prefab (KZB 27.0).

This is a project-local verifier/adapter, not a replacement KZB engine. The
serialization order is reconstructed from the user's existing KanziService APK:
libkzcoreui.so PrefabTemplate loader helper 0x64d610, loadBindings 0x371c48,
loadBinding 0x36f240, NodeComponentTemplate::load 0x647354 and TriggerTemplate::load
0x6543ac; libkzui.so ForwardingAction::loadBinding 0x3f76b8. Disassembly and hashes
are retained in build/native-layout-evidence. This supports only the field types
actually present in the original wallpaper and the existing AnimationPlayer.
Unknown classes, variants, opcode kinds, or inline bindings fail explicitly.
It parses every byte; it does not assume the historical 551/1474 offsets.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import zipfile
from pathlib import Path

if __package__:
    from . import kzb_native as engine
else:
    import kzb_native as engine


class LayoutError(ValueError):
    pass


class Reader:
    def __init__(self, data, strings, properties, metaclasses):
        self.data, self.strings, self.properties, self.metaclasses = data, strings, properties, metaclasses
        self.pos = 0
        self.fields = []

    def fail(self, message):
        raise LayoutError(f'Prefab byte {self.pos}: {message}')

    def scalar(self, label, fmt='I'):
        start = self.pos
        if self.pos + 4 > len(self.data):
            self.fail(f'truncated {label}')
        value = struct.unpack_from('<' + fmt, self.data, self.pos)[0]
        self.pos += 4
        self.fields.append({'offset': start, 'end': self.pos, 'field': label, 'value': value})
        return value

    def count(self, label):
        value = self.scalar(label)
        if value > min(4096, (len(self.data) - self.pos) // 4):
            self.fail(f'impossible {label}={value}')
        return value

    def index(self, label, dictionary):
        value = self.scalar(label)
        if value >= len(dictionary):
            self.fail(f'{label} index {value} outside dictionary of {len(dictionary)} entries')
        self.fields[-1]['resolved'] = dictionary[value]
        return dictionary[value]

    def string_ref(self, label):
        return self.index(label, self.strings)

    def prop_ref(self, label):
        return self.index(label, self.properties)

    def sized_string(self, label):
        size = self.scalar(label + '.bytes')
        start = self.pos
        if self.pos + size > len(self.data):
            self.fail(f'truncated {label}')
        try:
            value = self.data[self.pos:self.pos + size].decode('utf-8')
        except UnicodeDecodeError:
            self.fail(f'invalid UTF-8 in {label}')
        self.pos += size
        self.fields.append({'offset': start, 'end': self.pos, 'field': label, 'value': value})
        return value

    def zero(self, label):
        if self.scalar(label) != 0:
            self.fail(f'unsupported nonzero {label}')

    def props(self, label):
        count_offset = self.pos
        values = []
        count = self.count(label + '.count')
        for i in range(count):
            start = self.pos
            prop = self.prop_ref(f'{label}[{i}].property')
            if prop in {'Node.StateManager', 'Node2D.ForegroundBrush', 'OnPropertyChangedTrigger.SourceNode',
                        'OnPropertyChangedTrigger.SourcePropertyType', 'MessageArgument.SetPropertyAction.TargetObjectPath',
                        'AnimationPlayer.Timeline'}:
                value = self.sized_string(f'{label}[{i}].value')
            elif prop in {'Node.Width', 'Node.Height', 'Node.Opacity', 'AnimationPlayer.DurationScale', 'Action.Delay'}:
                value = self.scalar(f'{label}[{i}].value', 'f')
            elif prop in {'OnPropertyChangedTrigger.IgnoreIdenticalValue', 'OnPropertyChangedTrigger.IgnoreInitialValue',
                          'AnimationPlayer.AutoplayEnabled', 'AnimationPlayer.PlaybackMode',
                          'AnimationPlayer.RelativePlayback', 'AnimationPlayer.RepeatCount',
                          'AnimationPlayer.RestoreOriginalValuesAfterPlayback'}:
                value = self.scalar(f'{label}[{i}].value')
            else:
                self.fail(f'unsupported property type {prop!r}')
            values.append({'property': prop, 'value': value, 'start': start, 'end': self.pos})
        end_values = self.pos
        # All three KzbMemoryParser::loadProperties overloads consume this word.
        self.zero(label + '.inline_resource_binding_count')
        return {'count_offset': count_offset, 'values': values, 'values_end': end_values, 'end': self.pos}

    def binding(self, label):
        start = self.pos
        scope = self.scalar(label + '.scope')
        target_kind = self.scalar(label + '.target_kind')
        precedence = self.scalar(label + '.precedence')
        if scope != 1 or target_kind != 0 or precedence not in (1, 2):
            self.fail('unsupported expression binding target profile')
        target = self.prop_ref(label + '.target_property')
        self.zero(label + '.target_field')
        sources = []
        for i in range(self.count(label + '.property_source_count')):
            path = self.string_ref(f'{label}.source[{i}].path')
            prop = self.prop_ref(f'{label}.source[{i}].property')
            field = self.scalar(f'{label}.source[{i}].field')
            sources.append({'path': path, 'property': prop, 'field': field})
        self.zero(label + '.data_source_count')
        constants = []
        for i in range(self.count(label + '.constant_count')):
            kind = self.scalar(f'{label}.constant[{i}].kind')
            if kind != 1:
                self.fail(f'unsupported serialized constant kind {kind}')
            constants.append(self.scalar(f'{label}.constant[{i}].int', 'i'))
        opcodes = []
        for i in range(self.count(label + '.opcode_count')):
            self.zero(f'{label}.opcode[{i}].kind')
            # loadBinding 0x36f8d4..0x36f980 reads nine additional u32 words.
            words = [self.scalar(f'{label}.opcode[{i}].{name}') for name in
                     ('operation', 'arg0_type', 'arg0_field', 'arg1_type', 'arg1_field',
                      'arg2_type', 'arg2_field', 'destination', 'destination_field')]
            if words[0] not in (0, 3, 14, 15):
                self.fail(f'unsupported expression operation {words[0]}')
            opcodes.append(words)
        return {'start': start, 'end': self.pos, 'target': target, 'sources': sources,
                'constants': constants, 'opcodes': opcodes,
                'sha256': hashlib.sha256(self.data[start:self.pos]).hexdigest()}

    def action(self, label):
        start = self.pos
        kind = self.index(label + '.metaclass', self.metaclasses)
        if kind != 'Kanzi.SetPropertyAction':
            self.fail(f'unsupported action {kind}')
        props = self.props(label + '.properties')
        bindings = []
        for i in range(self.count(label + '.forward_binding_count')):
            target = self.prop_ref(f'{label}.forward[{i}].target_property')
            target_field = self.scalar(f'{label}.forward[{i}].target_field')
            source_kind = self.scalar(f'{label}.forward[{i}].kind')
            if source_kind != 2:
                self.fail(f'unsupported forwarding source kind {source_kind}')
            source_path = self.string_ref(f'{label}.forward[{i}].source_path')
            source_property = self.prop_ref(f'{label}.forward[{i}].source_property')
            source_field = self.scalar(f'{label}.forward[{i}].source_field')
            bindings.append({'target': target, 'target_field': target_field, 'source_path': source_path,
                             'source_property': source_property, 'source_field': source_field})
        return {'start': start, 'end': self.pos, 'metaclass': kind, 'properties': props, 'bindings': bindings}

    def component(self, label):
        start = self.pos
        kind = self.index(label + '.metaclass', self.metaclasses)
        if kind not in ('Kanzi.AnimationPlayer', 'Kanzi.OnPropertyChangedTrigger'):
            self.fail(f'unsupported node component {kind}')
        name = self.string_ref(label + '.name')
        props = self.props(label + '.properties')
        actions = []
        if kind == 'Kanzi.OnPropertyChangedTrigger':
            actions = [self.action(f'{label}.action[{i}]') for i in range(self.count(label + '.action_count'))]
            self.zero(label + '.condition_count')
            # TriggerTemplate::load 0x654644 advances over this reserved u32.
            self.zero(label + '.reserved')
        return {'start': start, 'end': self.pos, 'metaclass': kind, 'name': name,
                'properties': props, 'actions': actions}

    def node(self, label, depth=0):
        if depth > 16:
            self.fail('excessive node nesting')
        start = self.pos
        name = self.string_ref(label + '.name')
        template = self.string_ref(label + '.base_template')
        if template:
            self.fail('inherited Prefab templates are outside this verifier profile')
        kind = self.index(label + '.metaclass', self.metaclasses)
        if kind not in ('Kanzi.EmptyNode2D', 'Kanzi.Image2D'):
            self.fail(f'unsupported node type {kind}')
        props = self.props(label + '.properties')
        children = [self.node(f'{label}.child[{i}]', depth+1) for i in range(self.count(label + '.child_count'))]
        binding_count_offset = self.pos
        bindings = [self.binding(f'{label}.binding[{i}]') for i in range(self.count(label + '.binding_count'))]
        component_count_offset = self.pos
        components = [self.component(f'{label}.component[{i}]') for i in range(self.count(label + '.component_count'))]
        resource_dictionary_offset = self.pos
        resources = self.string_ref(label + '.resource_dictionary')
        return {'start': start, 'end': self.pos, 'name': name, 'metaclass': kind, 'properties': props,
                'children': children, 'binding_count_offset': binding_count_offset, 'bindings': bindings,
                'component_count_offset': component_count_offset, 'components': components,
                'resource_dictionary_offset': resource_dictionary_offset, 'resource_dictionary': resources}

    def parse(self):
        self.zero('resource.version')
        node = self.node('root')
        if self.pos != len(self.data):
            self.fail(f'{len(self.data)-self.pos} unconsumed bytes')
        return {'bytes': len(self.data), 'bytes_consumed': self.pos, 'root': node, 'fields': self.fields}


def parse_prefab(kzb, data=None, *, strings=None, properties=None, metaclasses=None):
    if (kzb.version_major, kzb.version_minor) != (27, 0):
        raise LayoutError('Only the audited KZB 27.0 is supported')
    if data is None:
        paths = [path for path in kzb.paths if path.startswith('/Prefabs/')]
        if len(paths) != 1:
            raise LayoutError(f'Expected one Prefab, found {len(paths)}')
        data = kzb.resource(paths[0])
    return Reader(data,
                  kzb.strings() if strings is None else strings,
                  engine._decode_dictionary(kzb.resource('/$property_dictionary')) if properties is None else properties,
                  engine._decode_dictionary(kzb.resource('/$metaclass_dictionary')) if metaclasses is None else metaclasses).parse()


def attach_component(kzb, data, node_name, component, *, component_has_inline_count=False, **dictionaries):
    """Add to the parsed node's real component list, preserving all existing bytes.

    Existing engine._build_animation_player_component returns properties without
    their terminal inline-resource-binding count. Add that zero exactly once.
    Caller supplies a kzb containing any newly appended dictionary entries.
    """
    parsed = parse_prefab(kzb, data, **dictionaries)
    def visit(node):
        return [node] + [desc for child in node['children'] for desc in visit(child)]
    matches = [node for node in visit(parsed['root']) if node['name'] == node_name]
    if len(matches) != 1:
        raise LayoutError(f'Expected exactly one {node_name!r} node, got {len(matches)}')
    node = matches[0]
    offset = node['component_count_offset']
    insertion = node['resource_dictionary_offset']
    body = component if component_has_inline_count else component + struct.pack('<I', 0)
    result = (data[:offset] + struct.pack('<I', len(node['components'])+1) + data[offset+4:insertion]
              + body + data[insertion:])
    checked = parse_prefab(kzb, result, **dictionaries)
    restored = result[:offset] + struct.pack('<I', len(node['components'])) + result[offset+4:insertion] + result[insertion+len(body):]
    if restored != data:
        raise LayoutError('Component insertion did not restore exact original bytes')
    return result, {'source_component_count_offset': offset, 'source_insertion_offset': insertion,
                    'component_bytes_including_inline_count': len(body), 'parsed': checked}


def load_package(path):
    path = Path(path)
    if path.suffix == '.zip':
        with zipfile.ZipFile(path) as archive:
            names = [name for name in archive.namelist() if name.endswith('.kzb')]
            if len(names) != 1:
                raise LayoutError('Expected one KZB in wallpaper ZIP')
            data = archive.read(names[0])
    else:
        data = path.read_bytes()
    return engine.KzbBinary(data)


if __name__ == '__main__':
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('package')
    cli.add_argument('--output', type=Path)
    args = cli.parse_args()
    report = parse_prefab(load_package(args.package))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    root = report['root']
    print(json.dumps({'bytes': report['bytes'], 'bytes_consumed': report['bytes_consumed'],
                      'root_components': len(root['components']), 'root_bindings': len(root['bindings']),
                      'children': [{'name': n['name'], 'component_count_offset': n['component_count_offset'],
                                    'components': len(n['components']), 'bindings': len(n['bindings'])}
                                   for n in root['children']]}, ensure_ascii=False))
