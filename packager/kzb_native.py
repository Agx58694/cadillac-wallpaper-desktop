"""Small, self-contained reader/rebuilder for the audited KZBF 27.0 profile.

This module contains only the serialization operations needed by the desktop
packager's identity step. It does not infer new Kanzi resource types.
"""

from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass
from typing import Iterable


KZB_MAGIC = b"KZBF"
SUPPORTED_VERSION = (27, 0)
UNIFORM_RECORD_SIZE = 7 * 4


@dataclass(frozen=True)
class KzbEntry:
    path: str
    path_index: int
    parent_index: int
    offset: int
    size: int
    compression: int
    raw_size: int


@dataclass(frozen=True)
class ShaderStage:
    kind: int
    source: bytes


@dataclass(frozen=True)
class MaterialType:
    prefix: bytes
    stages: tuple[ShaderStage, ...]
    tail: bytes
    uniform_names: tuple[str, ...]
    uniform_descriptors: tuple[tuple[int, ...], ...]


class KzbBinary:
    def __init__(self, data: bytes):
        self.data = data
        self.version_major = 0
        self.version_minor = 0
        self.project_name = ""
        self.paths: tuple[str, ...] = ()
        self.entries: tuple[KzbEntry, ...] = ()
        self.directory_end = 0
        self._parse()

    @staticmethod
    def _u32(data: bytes, offset: int) -> int:
        if offset < 0 or offset + 4 > len(data):
            raise ValueError("Unexpected end of KZB data")
        return struct.unpack_from("<I", data, offset)[0]

    def _parse(self) -> None:
        if len(self.data) < 20 or self.data[:4] != KZB_MAGIC:
            raise ValueError("Not a KZB binary")
        self.version_major = self._u32(self.data, 4)
        position = 8
        name_length = self._u32(self.data, position)
        position += 4
        if name_length > 256 or position + name_length > len(self.data):
            raise ValueError("Invalid KZB project name length")
        self.project_name = self.data[position:position + name_length].decode("utf-8")
        position += name_length
        self.version_minor = self._u32(self.data, position)
        path_count = self._u32(self.data, position + 4)
        position += 8
        if path_count == 0 or path_count > 4096:
            raise ValueError("Unsupported KZB path count")
        paths: list[str] = []
        for _ in range(path_count):
            terminator = self.data.find(b"\0", position)
            if terminator < 0 or terminator - position > 4096:
                raise ValueError("Unterminated or oversized KZB resource path")
            paths.append(self.data[position:terminator].decode("utf-8"))
            position = terminator + 1
        entry_count = self._u32(self.data, position)
        position += 4
        if entry_count != path_count:
            raise ValueError("KZB path and directory entry counts differ")
        entries: list[KzbEntry] = []
        for entry_index in range(entry_count):
            if position + 24 > len(self.data):
                raise ValueError("Truncated KZB directory")
            path_index, parent_index, offset, size, compression, raw_size = struct.unpack_from(
                "<6I", self.data, position
            )
            position += 24
            if path_index != entry_index:
                raise ValueError("Unsupported non-canonical KZB directory order")
            if offset + size > len(self.data):
                raise ValueError("KZB resource extends beyond the file")
            entries.append(KzbEntry(paths[path_index], path_index, parent_index,
                                    offset, size, compression, raw_size))
        self.paths = tuple(paths)
        self.entries = tuple(entries)
        self.directory_end = position

    def entry(self, path: str) -> KzbEntry:
        matches = [entry for entry in self.entries if entry.path == path]
        if len(matches) != 1:
            raise ValueError(f"Expected one KZB resource {path}, found {len(matches)}")
        return matches[0]

    def resource(self, path: str) -> bytes:
        entry = self.entry(path)
        if entry.compression != 0 or entry.raw_size != entry.size:
            raise ValueError(f"Compressed KZB resource is unsupported: {path}")
        return self.data[entry.offset:entry.offset + entry.size]

    def strings(self) -> tuple[str, ...]:
        return _decode_dictionary(self.resource("/$strings"))

    def material_type_url(self, material_path: str) -> str:
        data = self.resource(material_path)
        if len(data) < 8 or self._u32(data, 0) != 0:
            raise ValueError(f"Unsupported material resource: {material_path}")
        string_index = self._u32(data, 4)
        strings = self.strings()
        if string_index >= len(strings):
            raise ValueError("Material type string index is out of range")
        return strings[string_index]

    def material_type(self, path: str) -> MaterialType:
        data = self.resource(path)
        if len(data) < 12:
            raise ValueError(f"Truncated material type: {path}")
        stage_count = self._u32(data, 8)
        if stage_count > 8:
            raise ValueError(f"Unsupported material stage count: {path}")
        position = 12
        stages: list[ShaderStage] = []
        for _ in range(stage_count):
            kind = self._u32(data, position)
            position += 4
            terminator = data.find(b"\0", position)
            if terminator < 0:
                raise ValueError(f"Unterminated shader source in {path}")
            stages.append(ShaderStage(kind, data[position:terminator]))
            position = terminator + 1
        tail = data[position:]
        if len(tail) < 16:
            raise ValueError(f"Truncated material metadata in {path}")
        uniform_count = self._u32(tail, 8)
        descriptors_end = 12 + uniform_count * UNIFORM_RECORD_SIZE
        if descriptors_end + 4 > len(tail):
            raise ValueError(f"Invalid uniform table in {path}")
        strings = self.strings()
        names: list[str] = []
        descriptors: list[tuple[int, ...]] = []
        for offset in range(12, descriptors_end, UNIFORM_RECORD_SIZE):
            descriptor = struct.unpack_from("<7I", tail, offset)
            if descriptor[0] >= len(strings):
                raise ValueError(f"Invalid uniform string index in {path}")
            names.append(strings[descriptor[0]])
            descriptors.append(descriptor)
        return MaterialType(data[:12], tuple(stages), tail, tuple(names), tuple(descriptors))


def _decode_dictionary(data: bytes) -> tuple[str, ...]:
    count = KzbBinary._u32(data, 0)
    if count > len(data) - 4:
        raise ValueError("Impossible KZB dictionary count")
    position = 4
    values: list[str] = []
    for _ in range(count):
        terminator = data.find(b"\0", position)
        if terminator < 0:
            raise ValueError("Unterminated KZB dictionary entry")
        values.append(data[position:terminator].decode("utf-8"))
        position = terminator + 1
    if position != len(data):
        raise ValueError("Unexpected bytes after KZB dictionary")
    return tuple(values)


def _encode_dictionary(values: Iterable[str]) -> bytes:
    entries = tuple(values)
    result = bytearray(struct.pack("<I", len(entries)))
    for value in entries:
        result.extend(value.encode("utf-8"))
        result.append(0)
    return bytes(result)


def rebuild_kzb(source_data: bytes, replacements: dict[str, bytes] | None = None) -> bytes:
    """Rebuild resources in their original order with fresh sizes and offsets."""
    source = KzbBinary(source_data)
    replacements = replacements or {}
    unknown = set(replacements).difference(source.paths)
    if unknown:
        raise ValueError("Replacement paths are not present in KZB: " + ", ".join(sorted(unknown)))
    resources: list[tuple[int, bytes, int, int]] = []
    for entry in source.entries:
        payload = replacements.get(entry.path, source.resource(entry.path))
        if entry.path in replacements and entry.compression != 0:
            raise ValueError(f"Cannot replace compressed KZB resource: {entry.path}")
        raw_size = len(payload) if entry.path in replacements else entry.raw_size
        resources.append((entry.parent_index, payload, entry.compression, raw_size))
    project = source.project_name.encode("utf-8")
    header = bytearray(KZB_MAGIC + struct.pack("<II", source.version_major, len(project)) + project)
    header.extend(struct.pack("<II", source.version_minor, len(resources)))
    for path in source.paths:
        header.extend(path.encode("utf-8") + b"\0")
    header.extend(struct.pack("<I", len(resources)))
    payload_position = len(header) + 24 * len(resources)
    directory, payloads = bytearray(), bytearray()
    for index, (parent_index, payload, compression, raw_size) in enumerate(resources):
        aligned = (payload_position + 3) & ~3
        payloads.extend(bytes(aligned - payload_position))
        payload_position = aligned
        directory.extend(struct.pack("<6I", index, parent_index, payload_position,
                                     len(payload), compression, raw_size))
        payloads.extend(payload)
        payload_position += len(payload)
    result = bytes(header + directory + payloads)
    if len(KzbBinary(result).entries) != len(resources):
        raise ValueError("Rebuilt KZB resource count mismatch")
    return result
