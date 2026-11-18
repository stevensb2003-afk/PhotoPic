"""Lossless persistent 90-degree clockwise image rotation on disk for Windows (RAW + JPG + XMP)."""

from __future__ import annotations

import os
from pathlib import Path
import re
import struct
import uuid

from .models import MediaFormatClassifier, MediaFormatKind, PhotoItem
from .tag_store import PhotoTagStore


_CLOCKWISE_MAP = {
    1: 6,
    6: 3,
    3: 8,
    8: 1,
    2: 7,
    7: 4,
    4: 5,
    5: 2,
}

_CANON_META_UUID = bytes([
    0x85, 0xC0, 0xB6, 0x87, 0x82, 0x0F, 0x11, 0xE0,
    0x81, 0x11, 0xF4, 0xCE, 0x46, 0x2B, 0x6A, 0x48,
])


class PhotoOrientationService:
    """Persists EXIF Orientation (`0x0112`) directly into TIFF-based RAWs (`.CR2/.DNG/.NEF/.ARW/...`),
    Canon `.CR3` `CMT1` boxes, compressed images (`.JPG/.HEIC/.PNG/.TIFF`), paired `.JPG` companions,
    and `.xmp` sidecars so Windows Explorer, Photos, Preview, and Lightroom show the rotated photo."""

    @staticmethod
    def next_clockwise_orientation(current: int) -> int:
        return _CLOCKWISE_MAP.get(current, 6)

    @classmethod
    def read_orientation(cls, path: Path) -> int:
        ext = path.suffix.lstrip(".").lower()
        if ext == "cr3":
            val = cls._read_cr3_orientation(path)
            if val is not None:
                return val

        kind = MediaFormatClassifier.classify(path.name)
        if kind == MediaFormatKind.RAW or ext in ("tif", "tiff"):
            val = cls._read_tiff_orientation(path, base_offset=0)
            if val is not None:
                return val

        try:
            from PIL import Image

            with Image.open(path) as img:
                exif = img.getexif()
                val = int(exif.get(0x0112, 1)) if exif else 1
                return val if 1 <= val <= 8 else 1
        except Exception:
            return 1

    @classmethod
    def rotate_clockwise_90(cls, item: PhotoItem) -> int:
        current = cls.read_orientation(item.file_path)
        target = cls.next_clockwise_orientation(current)

        cls.persist_orientation(target, item.file_path)

        if item.paired_compressed_path is not None and item.paired_compressed_path.exists():
            try:
                cls.persist_orientation(target, item.paired_compressed_path)
            except Exception:
                pass

        cls._update_xmp_orientation_if_present(item.file_path, target)
        return target

    @classmethod
    def persist_orientation(cls, orientation: int, path: Path) -> None:
        ext = path.suffix.lstrip(".").lower()
        if ext == "cr3":
            if cls._patch_cr3_orientation(path, orientation) > 0:
                return
            raise ValueError(f"No se pudo guardar la orientación en {path.name}.")

        kind = MediaFormatClassifier.classify(path.name)
        if kind == MediaFormatKind.RAW or ext in ("tif", "tiff"):
            if cls._patch_tiff_orientation(path, base_offset=0, orientation=orientation) > 0:
                return
            if kind == MediaFormatKind.RAW:
                raise ValueError(f"Este formato RAW no permite actualizar la orientación inline en {path.name}.")

        cls._rewrite_compressed_orientation(path, orientation)

    # MARK: - Lossless In-Place TIFF IFD `0x0112` Patcher

    @classmethod
    def _read_tiff_orientation(cls, path: Path, base_offset: int) -> int | None:
        try:
            with path.open("rb") as fh:
                fh.seek(0, os.SEEK_END)
                file_size = fh.tell()
                if base_offset + 8 > file_size:
                    return None
                fh.seek(base_offset)
                header = fh.read(8)
                endian = cls._parse_tiff_endian(header)
                if endian is None:
                    return None
                first_ifd = struct.unpack(f"{endian}I", header[4:8])[0]
                if base_offset + first_ifd + 2 > file_size:
                    return None
                fh.seek(base_offset + first_ifd)
                count = struct.unpack(f"{endian}H", fh.read(2))[0]
                if not (0 < count < 512):
                    return None
                table = fh.read(count * 12)
                for i in range(count):
                    off = i * 12
                    tag, typ, cnt = struct.unpack(f"{endian}HHI", table[off : off + 8])
                    if tag == 0x0112 and typ == 3 and cnt == 1:
                        val = struct.unpack(f"{endian}H", table[off + 8 : off + 10])[0]
                        return val if 1 <= val <= 8 else 1
        except OSError:
            return None
        return None

    @classmethod
    def _patch_tiff_orientation(cls, path: Path, base_offset: int, orientation: int) -> int:
        patched = 0
        with path.open("r+b") as fh:
            fh.seek(0, os.SEEK_END)
            file_size = fh.tell()
            if base_offset + 8 > file_size:
                return 0
            fh.seek(base_offset)
            header = fh.read(8)
            endian = cls._parse_tiff_endian(header)
            if endian is None:
                return 0

            first_ifd = struct.unpack(f"{endian}I", header[4:8])[0]
            pending = [first_ifd]
            visited: set[int] = set()

            while pending and len(visited) < 12:
                rel_ifd = pending.pop(0)
                if rel_ifd < 8 or rel_ifd in visited:
                    continue
                visited.add(rel_ifd)
                abs_ifd = base_offset + rel_ifd
                if abs_ifd + 2 > file_size:
                    continue
                fh.seek(abs_ifd)
                count_bytes = fh.read(2)
                if len(count_bytes) < 2:
                    continue
                entry_count = struct.unpack(f"{endian}H", count_bytes)[0]
                if not (0 < entry_count < 512):
                    continue
                table_len = entry_count * 12 + 4
                if abs_ifd + 2 + table_len > file_size:
                    continue
                table = fh.read(table_len)
                if len(table) < table_len:
                    continue

                for i in range(entry_count):
                    off = i * 12
                    tag, typ, cnt = struct.unpack(f"{endian}HHI", table[off : off + 8])
                    if tag == 0x0112 and typ == 3 and cnt == 1:
                        fh.seek(abs_ifd + 2 + off + 8)
                        fh.write(struct.pack(f"{endian}H", orientation))
                        patched += 1
                    elif tag == 0x014A and typ in (4, 13) and 1 <= cnt <= 4:
                        if cnt == 1:
                            pending.append(struct.unpack(f"{endian}I", table[off + 8 : off + 12])[0])
                        else:
                            arr_rel = struct.unpack(f"{endian}I", table[off + 8 : off + 12])[0]
                            arr_abs = base_offset + arr_rel
                            if arr_abs + cnt * 4 <= file_size:
                                fh.seek(arr_abs)
                                arr = fh.read(cnt * 4)
                                for s in range(cnt):
                                    pending.append(struct.unpack(f"{endian}I", arr[s * 4 : (s + 1) * 4])[0])

                next_ifd = struct.unpack(f"{endian}I", table[entry_count * 12 : entry_count * 12 + 4])[0]
                if next_ifd > 0:
                    pending.append(next_ifd)

            if patched > 0:
                fh.flush()
        return patched

    @staticmethod
    def _parse_tiff_endian(header: bytes) -> str | None:
        if len(header) < 8:
            return None
        if header[0:2] == b"II":
            endian = "<"
        elif header[0:2] == b"MM":
            endian = ">"
        else:
            return None
        magic = struct.unpack(f"{endian}H", header[2:4])[0]
        if magic not in (42, 0x4F52, 0x5352, 0x0055):
            return None
        return endian

    # MARK: - Canon CR3 `CMT1` Box Patcher

    @classmethod
    def _find_cr3_cmt1_offset(cls, path: Path) -> int | None:
        try:
            with path.open("rb") as fh:
                fh.seek(0, os.SEEK_END)
                file_size = fh.tell()
                moov = cls._find_box(fh, b"moov", 0, file_size)
                if moov is None:
                    return None
                cursor = moov[0]
                while cursor + 8 <= moov[1]:
                    box = cls._read_box(fh, cursor, moov[1])
                    if box is None:
                        break
                    btype, payload_start, end = box
                    if btype == b"uuid" and payload_start + 16 <= end:
                        fh.seek(payload_start)
                        if fh.read(16) == _CANON_META_UUID:
                            cmt1 = cls._find_box(fh, b"CMT1", payload_start + 16, end)
                            if cmt1 is not None:
                                return cmt1[0]
                    cursor = end
        except OSError:
            return None
        return None

    @classmethod
    def _read_cr3_orientation(cls, path: Path) -> int | None:
        cmt1_offset = cls._find_cr3_cmt1_offset(path)
        if cmt1_offset is None:
            return None
        return cls._read_tiff_orientation(path, base_offset=cmt1_offset)

    @classmethod
    def _patch_cr3_orientation(cls, path: Path, orientation: int) -> int:
        cmt1_offset = cls._find_cr3_cmt1_offset(path)
        if cmt1_offset is None:
            return 0
        return cls._patch_tiff_orientation(path, base_offset=cmt1_offset, orientation=orientation)

    @classmethod
    def _find_box(cls, fh, target: bytes, start: int, end: int) -> tuple[int, int] | None:
        cursor = start
        while cursor + 8 <= end:
            box = cls._read_box(fh, cursor, end)
            if box is None:
                return None
            btype, payload_start, box_end = box
            if btype == target:
                return payload_start, box_end
            cursor = box_end
        return None

    @staticmethod
    def _read_box(fh, offset: int, limit: int) -> tuple[bytes, int, int] | None:
        if offset + 8 > limit:
            return None
        fh.seek(offset)
        hdr = fh.read(8)
        if len(hdr) < 8:
            return None
        size32 = struct.unpack(">I", hdr[0:4])[0]
        btype = hdr[4:8]
        payload_start = offset + 8
        box_size = size32
        if size32 == 1:
            if offset + 16 > limit:
                return None
            box_size = struct.unpack(">Q", fh.read(8))[0]
            payload_start = offset + 16
        elif size32 == 0:
            box_size = limit - offset
        if box_size < (payload_start - offset) or offset + box_size > limit:
            return None
        return btype, payload_start, offset + box_size

    # MARK: - Compressed Image Orientation Writer (Pillow)

    @staticmethod
    def _rewrite_compressed_orientation(path: Path, orientation: int) -> None:
        from PIL import Image, ImageOps

        stat = path.stat()
        ext = path.suffix.lstrip(".").lower()
        temp_path = path.parent / f".photopic_rot_{uuid.uuid4().hex}{path.suffix}"

        try:
            with Image.open(path) as img:
                fmt = img.format
                if ext in ("jpg", "jpeg", "heic", "heif", "tif", "tiff"):
                    exif = img.getexif()
                    exif[0x0112] = orientation
                    save_kwargs: dict = {"exif": exif.tobytes()}
                    if ext in ("jpg", "jpeg"):
                        save_kwargs["quality"] = 96
                        save_kwargs["subsampling"] = 0
                    img.save(temp_path, format=fmt, **save_kwargs)
                else:
                    oriented = ImageOps.exif_transpose(img)
                    rotated = oriented.rotate(-90, expand=True)
                    rotated.save(temp_path, format=fmt)
            temp_path.replace(path)
            os.utime(path, (stat.st_atime, stat.st_mtime))
        finally:
            if temp_path.exists():
                temp_path.unlink(missing_ok=True)

    @staticmethod
    def _update_xmp_orientation_if_present(image_path: Path, orientation: int) -> None:
        xmp_path = PhotoTagStore.xmp_sidecar_path(image_path)
        if not xmp_path.exists():
            return
        try:
            content = xmp_path.read_text(encoding="utf-8")
        except OSError:
            return
        if re.search(r"<tiff:Orientation>\d+</tiff:Orientation>", content):
            content = re.sub(
                r"<tiff:Orientation>\d+</tiff:Orientation>",
                f"<tiff:Orientation>{orientation}</tiff:Orientation>",
                content,
            )
        elif 'xmlns:dc="http://purl.org/dc/elements/1.1/"' in content:
            content = content.replace(
                'xmlns:dc="http://purl.org/dc/elements/1.1/"',
                'xmlns:dc="http://purl.org/dc/elements/1.1/"\n        xmlns:tiff="http://ns.adobe.com/tiff/1.0/"',
                1,
            )
            content = content.replace(
                "</rdf:Description>",
                f"      <tiff:Orientation>{orientation}</tiff:Orientation>\n    </rdf:Description>",
                1,
            )
        try:
            xmp_path.write_text(content, encoding="utf-8")
        except OSError:
            pass
