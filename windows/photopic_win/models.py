"""Domain models and 36-format classifier shared across Windows tethering & culling."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path


class MediaFormatKind(str, Enum):
    RAW = "raw"
    COMPRESSED = "compressed"


class MediaFormatClassifier:
    RAW_EXTENSIONS: frozenset[str] = frozenset({
        "dng", "cr2", "cr3", "crw",
        "nef", "nrw",
        "arw", "srf", "sr2",
        "raf",
        "orf", "ori",
        "rw2", "raw",
        "pef", "srw",
        "3fr", "fff", "iiq", "rwl", "erf", "mos", "mrw", "dcr", "kdc",
    })

    COMPRESSED_EXTENSIONS: frozenset[str] = frozenset({
        "jpg", "jpeg", "heic", "heif", "hif", "avif", "jxl", "webp", "png", "tif", "tiff",
    })

    @classmethod
    def classify(cls, filename: str) -> MediaFormatKind | None:
        ext = Path(filename).suffix.lstrip(".").lower()
        if ext in cls.RAW_EXTENSIONS:
            return MediaFormatKind.RAW
        if ext in cls.COMPRESSED_EXTENSIONS:
            return MediaFormatKind.COMPRESSED
        return None

    @classmethod
    def is_supported_image(cls, path: Path) -> bool:
        return cls.classify(path.name) is not None

    @staticmethod
    def base_filename(path: Path) -> str:
        return path.stem.lower()


class DeviceCategory(str, Enum):
    DSLR_MIRRORLESS = "dslrMirrorless"
    ANDROID_PTP = "androidPTP"
    IPHONE_IOS = "iPhoneIOS"
    COMPACT_ACTION = "compactAction"

    @property
    def display_title(self) -> str:
        titles = {
            self.DSLR_MIRRORLESS: "Cámara DSLR / Mirrorless",
            self.ANDROID_PTP: "Smartphone Android (PTP / MTP)",
            self.IPHONE_IOS: "iPhone / iPad (iOS)",
            self.COMPACT_ACTION: "Cámara Compacta / Acción",
        }
        return titles[self]

    @property
    def default_allows_jpg_fallback(self) -> bool:
        return self in (self.ANDROID_PTP, self.IPHONE_IOS)


@dataclass
class PhotoExifMetadata:
    camera_make: str | None = None
    camera_model: str | None = None
    lens_model: str | None = None
    iso: int | None = None
    aperture: float | None = None
    shutter_seconds: float | None = None
    focal_length_mm: float | None = None
    pixel_width: int | None = None
    pixel_height: int | None = None

    @property
    def formatted_iso(self) -> str | None:
        return f"ISO {self.iso}" if self.iso else None

    @property
    def formatted_aperture(self) -> str | None:
        if self.aperture and self.aperture > 0:
            return f"f/{self.aperture:.1f}".rstrip("0").rstrip(".")
        return None

    @property
    def formatted_shutter(self) -> str | None:
        if self.shutter_seconds and self.shutter_seconds > 0:
            if self.shutter_seconds >= 1.0:
                return f"{self.shutter_seconds:.1f}s"
            denom = max(1, round(1.0 / self.shutter_seconds))
            return f"1/{denom}s"
        return None

    @property
    def formatted_focal(self) -> str | None:
        return f"{round(self.focal_length_mm)}mm" if self.focal_length_mm and self.focal_length_mm > 0 else None

    @property
    def formatted_dimensions(self) -> str | None:
        if self.pixel_width and self.pixel_height and self.pixel_width > 0 and self.pixel_height > 0:
            mp = (self.pixel_width * self.pixel_height) / 1_000_000.0
            return f"{self.pixel_width}×{self.pixel_height} ({mp:.1f} MP)"
        return None

    @property
    def compact_hud_summary(self) -> str:
        parts = [p for p in (self.formatted_iso, self.formatted_aperture, self.formatted_shutter, self.formatted_focal) if p]
        return " · ".join(parts) if parts else "Sin metadatos EXIF"


@dataclass
class PhotoVisionTags:
    analyzed_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    person_count: int = 0
    face_count: int = 0
    has_closed_eyes_warning: bool = False
    auto_tags: list[str] = field(default_factory=list)
    custom_tags: list[str] = field(default_factory=list)

    @property
    def all_tags(self) -> list[str]:
        seen: set[str] = set()
        merged: list[str] = []
        for tag in self.auto_tags + self.custom_tags:
            clean = tag.strip()
            if clean and clean.lower() not in seen:
                seen.add(clean.lower())
                merged.append(clean)
        return merged

    def add_custom_tag(self, raw_tag: str) -> None:
        clean = raw_tag.strip()
        if clean and all(t.lower() != clean.lower() for t in self.all_tags):
            self.custom_tags.append(clean)


@dataclass
class PhotoItem:
    id: str
    file_path: Path
    paired_compressed_path: Path | None = None
    file_size_bytes: int = 0
    captured_at: float = 0.0
    source_device_alias: str | None = None
    exif: PhotoExifMetadata = field(default_factory=PhotoExifMetadata)
    vision_tags: PhotoVisionTags | None = None

    @property
    def filename(self) -> str:
        return self.file_path.name

    @property
    def format_extension(self) -> str:
        return self.file_path.suffix.lstrip(".").upper()

    @property
    def format_kind(self) -> MediaFormatKind:
        return MediaFormatClassifier.classify(self.filename) or MediaFormatKind.COMPRESSED

    @property
    def base_filename(self) -> str:
        return self.file_path.stem.lower()


@dataclass
class SessionDiskCounts:
    pending: int = 0
    for_editing: int = 0
    archived: int = 0
    companion_jpgs: int = 0

    @property
    def total_all_images(self) -> int:
        return self.pending + self.for_editing + self.archived


@dataclass
class PhotoSession:
    name: str
    directory: Path
    created_at: float = 0.0
    counts: SessionDiskCounts = field(default_factory=SessionDiskCounts)
    group_name: str | None = None
    tags: list[str] = field(default_factory=list)
    formatted_duration: str | None = None

    @property
    def raw_folder(self) -> Path:
        return self.directory / "RAW"

    @property
    def jpg_folder(self) -> Path:
        return self.directory / "JPG"

    @property
    def for_editing_folder(self) -> Path:
        return self.directory / "Para_Edicion"

    @property
    def archived_folder(self) -> Path:
        return self.directory / "Archivadas"

    @property
    def for_editing_raw_folder(self) -> Path:
        return self.for_editing_folder / "RAW"

    @property
    def for_editing_jpg_folder(self) -> Path:
        return self.for_editing_folder / "JPG"

    @property
    def archived_raw_folder(self) -> Path:
        return self.archived_folder / "RAW"

    @property
    def archived_jpg_folder(self) -> Path:
        return self.archived_folder / "JPG"

    def raw_bucket(self, folder_name: str) -> Path:
        if folder_name == "Para_Edicion":
            return self.for_editing_raw_folder
        if folder_name == "Archivadas":
            return self.archived_raw_folder
        return self.raw_folder

    def jpg_bucket(self, folder_name: str) -> Path:
        if folder_name == "Para_Edicion":
            return self.for_editing_jpg_folder
        if folder_name == "Archivadas":
            return self.archived_jpg_folder
        return self.jpg_folder


@dataclass
class KnownDevice:
    fingerprint: str
    display_name: str
    alias: str
    category: DeviceCategory
    auto_connect_on_plug: bool = True
    keep_originals_on_device: bool = True
    allow_jpg_when_no_raw: bool = True
    last_connected_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
