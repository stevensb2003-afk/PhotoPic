"""Pure sensor RAW decoding via LibRaw (`rawpy`) plus Pillow/HEIF fallback for Windows."""

from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ExifTags

from .models import MediaFormatKind, PhotoExifMetadata, PhotoItem

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
except ImportError:
    pass


@dataclass
class RenderedWinPayload:
    rgb_bytes: bytes
    width: int
    height: int
    is_full_sensor: bool


class RawImageRendererWin:
    def __init__(self, max_cached: int = 24) -> None:
        self._cache: OrderedDict[str, RenderedWinPayload] = OrderedDict()
        self._max_cached = max_cached

    def render_image(self, item: PhotoItem, max_dimension: int = 2200, full_sensor: bool = False) -> RenderedWinPayload | None:
        key = f"{item.file_path}|{'full' if full_sensor else max_dimension}"
        if key in self._cache:
            self._cache.move_to_end(key)
            return self._cache[key]

        payload = (
            self._decode_raw_libraw(item.file_path, max_dimension, full_sensor)
            if item.format_kind == MediaFormatKind.RAW
            else self._decode_compressed(item.file_path, max_dimension, full_sensor)
        )
        if payload is not None:
            self._cache[key] = payload
            while len(self._cache) > self._max_cached:
                self._cache.popitem(last=False)
        return payload

    @staticmethod
    def read_exif(path: Path, companion_path: Path | None = None) -> PhotoExifMetadata:
        meta = RawImageRendererWin._read_exif_single(path)
        if companion_path and meta.iso is None:
            comp = RawImageRendererWin._read_exif_single(companion_path)
            meta.iso = meta.iso or comp.iso
            meta.aperture = meta.aperture or comp.aperture
            meta.shutter_seconds = meta.shutter_seconds or comp.shutter_seconds
            meta.focal_length_mm = meta.focal_length_mm or comp.focal_length_mm
            meta.camera_model = meta.camera_model or comp.camera_model
        return meta

    @staticmethod
    def _read_exif_single(path: Path) -> PhotoExifMetadata:
        meta = PhotoExifMetadata()
        try:
            with Image.open(path) as img:
                meta.pixel_width, meta.pixel_height = img.size
                exif = img.getexif()
                if not exif:
                    return meta
                tag_map = {ExifTags.TAGS.get(k, k): v for k, v in exif.items()}
                meta.camera_make = str(tag_map.get("Make", "")).strip() or None
                meta.camera_model = str(tag_map.get("Model", "")).strip() or None
                if "ISOSpeedRatings" in tag_map:
                    val = tag_map["ISOSpeedRatings"]
                    meta.iso = int(val[0] if isinstance(val, (tuple, list)) else val)
                if "FNumber" in tag_map:
                    meta.aperture = float(tag_map["FNumber"])
                if "ExposureTime" in tag_map:
                    meta.shutter_seconds = float(tag_map["ExposureTime"])
                if "FocalLength" in tag_map:
                    meta.focal_length_mm = float(tag_map["FocalLength"])
        except Exception:
            pass
        return meta

    @staticmethod
    def _decode_raw_libraw(path: Path, max_dimension: int, full_sensor: bool) -> RenderedWinPayload | None:
        try:
            import rawpy
        except ImportError:
            return None

        try:
            with rawpy.imread(str(path)) as raw:
                rgb = raw.postprocess(
                    use_camera_wb=True,
                    no_auto_bright=False,
                    half_size=not full_sensor,
                    output_bps=8,
                )
            pil_img = Image.fromarray(rgb, mode="RGB")
            if not full_sensor and max(pil_img.size) > max_dimension:
                pil_img.thumbnail((max_dimension, max_dimension), Image.Resampling.LANCZOS)
            return RenderedWinPayload(
                rgb_bytes=pil_img.tobytes("raw", "RGB"),
                width=pil_img.width,
                height=pil_img.height,
                is_full_sensor=full_sensor,
            )
        except Exception:
            return None

    @staticmethod
    def _decode_compressed(path: Path, max_dimension: int, full_sensor: bool) -> RenderedWinPayload | None:
        try:
            with Image.open(path) as img:
                rgb_img = img.convert("RGB")
                if not full_sensor and max(rgb_img.size) > max_dimension:
                    rgb_img.thumbnail((max_dimension, max_dimension), Image.Resampling.LANCZOS)
                return RenderedWinPayload(
                    rgb_bytes=rgb_img.tobytes("raw", "RGB"),
                    width=rgb_img.width,
                    height=rgb_img.height,
                    is_full_sensor=full_sensor,
                )
        except Exception:
            return None
