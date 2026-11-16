"""JSON tag store and Adobe/Lightroom .xmp sidecar persistence for Windows."""

from __future__ import annotations

import json
from pathlib import Path
from xml.sax.saxutils import escape

from .models import PhotoItem, PhotoSession, PhotoVisionTags


class PhotoTagStore:
    STORE_FILENAME = ".photopic_tags.json"

    @classmethod
    def load_all(cls, session: PhotoSession) -> dict[str, PhotoVisionTags]:
        store_path = session.directory / cls.STORE_FILENAME
        if not store_path.exists():
            return {}
        try:
            raw = json.loads(store_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}

        parsed: dict[str, PhotoVisionTags] = {}
        for key, payload in raw.items():
            if isinstance(payload, dict):
                parsed[key] = PhotoVisionTags(
                    analyzed_at=str(payload.get("analyzedAt", payload.get("analyzed_at", ""))),
                    person_count=int(payload.get("personCount", payload.get("person_count", 0))),
                    face_count=int(payload.get("faceCount", payload.get("face_count", 0))),
                    has_closed_eyes_warning=bool(
                        payload.get("hasClosedEyesWarning", payload.get("has_closed_eyes_warning", False))
                    ),
                    auto_tags=list(payload.get("autoTags", payload.get("auto_tags", []))),
                    custom_tags=list(payload.get("customTags", payload.get("custom_tags", []))),
                )
        return parsed

    @classmethod
    def save(cls, tags: PhotoVisionTags, item: PhotoItem, session: PhotoSession, write_xmp: bool = True) -> None:
        tag_map = cls.load_all(session)
        tag_map[item.base_filename] = tags
        serialized = {
            k: {
                "analyzedAt": v.analyzed_at,
                "personCount": v.person_count,
                "faceCount": v.face_count,
                "hasClosedEyesWarning": v.has_closed_eyes_warning,
                "autoTags": v.auto_tags,
                "customTags": v.custom_tags,
            }
            for k, v in tag_map.items()
        }
        store_path = session.directory / cls.STORE_FILENAME
        tmp_path = store_path.with_suffix(".json.tmp")
        tmp_path.write_text(json.dumps(serialized, indent=2, ensure_ascii=False), encoding="utf-8")
        tmp_path.replace(store_path)

        if write_xmp:
            cls.write_xmp_sidecar(tags, item.file_path)

    @staticmethod
    def xmp_sidecar_path(image_path: Path) -> Path:
        return image_path.with_suffix(".xmp")

    @classmethod
    def relocate_sidecar_if_present(cls, old_image: Path, new_image: Path) -> None:
        old_xmp = cls.xmp_sidecar_path(old_image)
        if not old_xmp.exists():
            return
        new_xmp = cls.xmp_sidecar_path(new_image)
        if new_xmp.exists():
            new_xmp.unlink()
        old_xmp.replace(new_xmp)

    @classmethod
    def write_xmp_sidecar(cls, tags: PhotoVisionTags, image_path: Path) -> None:
        xmp_path = cls.xmp_sidecar_path(image_path)
        items_xml = "\n".join(f"          <rdf:li>{escape(tag)}</rdf:li>" for tag in tags.all_tags)
        xmp = (
            '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>\n'
            '<x:xmpmeta xmlns:x="adobe:ns:meta/">\n'
            '  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n'
            '    <rdf:Description rdf:about=""\n'
            '        xmlns:dc="http://purl.org/dc/elements/1.1/"\n'
            '        xmlns:photopic="https://github.com/stevensb2003-afk/PhotoPic/ns/1.0/">\n'
            f"      <photopic:PersonCount>{tags.person_count}</photopic:PersonCount>\n"
            f"      <photopic:FaceCount>{tags.face_count}</photopic:FaceCount>\n"
            f'      <photopic:ClosedEyesWarning>{"true" if tags.has_closed_eyes_warning else "false"}</photopic:ClosedEyesWarning>\n'
            "      <dc:subject>\n"
            "        <rdf:Bag>\n"
            f"{items_xml}\n"
            "        </rdf:Bag>\n"
            "      </dc:subject>\n"
            "    </rdf:Description>\n"
            "  </rdf:RDF>\n"
            "</x:xmpmeta>\n"
            '<?xpacket end="w"?>\n'
        )
        xmp_path.write_text(xmp, encoding="utf-8")
