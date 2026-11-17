"""Per-session metadata (.photopic_session.json), Master Category Groups, and safe project deletion for Windows."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path
import re
import shutil
import time


GROUP_MARKER_FILENAME = ".photopic_group.json"
SESSION_META_FILENAME = ".photopic_session.json"


@dataclass
class SessionMetadata:
    tags: list[str] = field(default_factory=list)
    timer_started_at_epoch: float | None = None
    timer_ended_at_epoch: float | None = None
    accumulated_seconds: float = 0.0
    first_shot_epoch: float | None = None
    is_timer_running: bool = False
    is_timer_finished: bool = False

    @property
    def has_recorded_time(self) -> bool:
        return self.is_timer_running or self.is_timer_finished or self.accumulated_seconds > 0

    @property
    def has_never_started_timer(self) -> bool:
        return (
            not self.is_timer_running
            and not self.is_timer_finished
            and self.accumulated_seconds == 0
            and self.timer_started_at_epoch is None
        )

    def elapsed_seconds(self, now: float | None = None) -> float:
        current = time.time() if now is None else now
        if self.is_timer_running and self.timer_started_at_epoch is not None:
            return max(0.0, self.accumulated_seconds + max(0.0, current - self.timer_started_at_epoch))
        return max(0.0, self.accumulated_seconds)

    def formatted_duration(self, now: float | None = None) -> str:
        total = int(self.elapsed_seconds(now))
        h = total // 3600
        m = (total % 3600) // 60
        s = total % 60
        return f"{h:02d}:{m:02d}:{s:02d}"

    def start_manual(self, now: float | None = None) -> None:
        if self.is_timer_running:
            return
        current = time.time() if now is None else now
        self.timer_started_at_epoch = current
        self.timer_ended_at_epoch = None
        self.is_timer_running = True
        self.is_timer_finished = False

    def auto_start_from_first_shot(self, captured_at: float, now: float | None = None) -> None:
        if not self.has_never_started_timer:
            return
        current = time.time() if now is None else now
        self.first_shot_epoch = captured_at
        diff = current - captured_at
        anchor = captured_at if (0 <= diff <= 12 * 3600) else current
        self.timer_started_at_epoch = anchor
        self.timer_ended_at_epoch = None
        self.is_timer_running = True
        self.is_timer_finished = False

    def stop_and_finish(self, now: float | None = None) -> None:
        current = time.time() if now is None else now
        if self.is_timer_running and self.timer_started_at_epoch is not None:
            self.accumulated_seconds += max(0.0, current - self.timer_started_at_epoch)
        self.timer_started_at_epoch = None
        self.timer_ended_at_epoch = current
        self.is_timer_running = False
        self.is_timer_finished = True

    def reset_timer(self) -> None:
        self.timer_started_at_epoch = None
        self.timer_ended_at_epoch = None
        self.accumulated_seconds = 0.0
        self.first_shot_epoch = None
        self.is_timer_running = False
        self.is_timer_finished = False

    def add_tag(self, raw_tag: str) -> None:
        clean = raw_tag.strip()
        if clean and all(t.lower() != clean.lower() for t in self.tags):
            self.tags.append(clean)

    def remove_tag(self, tag: str) -> None:
        self.tags = [t for t in self.tags if t.lower() != tag.lower()]

    @staticmethod
    def parse_comma_tags(raw: str) -> list[str]:
        meta = SessionMetadata()
        for part in raw.split(","):
            meta.add_tag(part)
        return meta.tags


class SessionMetadataStore:
    """Reads and writes `.photopic_session.json` compatibly with macOS PhotoPic."""

    @staticmethod
    def load(session_dir: Path) -> SessionMetadata:
        path = session_dir / SESSION_META_FILENAME
        if not path.exists():
            return SessionMetadata()
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return SessionMetadata()

        return SessionMetadata(
            tags=[str(x) for x in raw.get("tags", []) if str(x).strip()],
            timer_started_at_epoch=raw.get("timerStartedAtEpoch"),
            timer_ended_at_epoch=raw.get("timerEndedAtEpoch"),
            accumulated_seconds=float(raw.get("accumulatedSeconds", 0.0) or 0.0),
            first_shot_epoch=raw.get("firstShotEpoch"),
            is_timer_running=bool(raw.get("isTimerRunning", False)),
            is_timer_finished=bool(raw.get("isTimerFinished", False)),
        )

    @staticmethod
    def save(meta: SessionMetadata, session_dir: Path) -> None:
        payload = {
            "accumulatedSeconds": meta.accumulated_seconds,
            "firstShotEpoch": meta.first_shot_epoch,
            "isTimerFinished": meta.is_timer_finished,
            "isTimerRunning": meta.is_timer_running,
            "tags": meta.tags,
            "timerEndedAtEpoch": meta.timer_ended_at_epoch,
            "timerStartedAtEpoch": meta.timer_started_at_epoch,
        }
        (session_dir / SESSION_META_FILENAME).write_text(
            json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True),
            encoding="utf-8",
        )


def sanitize_folder_name(raw_name: str) -> str:
    return re.sub(r'[<>:"/\\|?*]', "-", raw_name).strip()


def load_master_groups(root_dir: Path) -> list[str]:
    if not root_dir.exists():
        return []
    groups: list[str] = []
    for entry in root_dir.iterdir():
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        if (entry / "RAW").is_dir():
            continue
        if (entry / GROUP_MARKER_FILENAME).exists() or any(
            sub.is_dir() and not sub.name.startswith(".") and (sub / "RAW").is_dir()
            for sub in entry.iterdir()
        ):
            groups.append(entry.name)
    return sorted(groups, key=str.casefold)


def create_master_group(raw_name: str, root_dir: Path) -> str:
    sanitized = sanitize_folder_name(raw_name)
    if not sanitized:
        raise ValueError("El nombre de la carpeta máster no es válido.")
    group_dir = root_dir / sanitized
    if (group_dir / "RAW").is_dir():
        idx = 2
        group_dir = root_dir / f"{sanitized}_Grupo"
        while group_dir.exists():
            group_dir = root_dir / f"{sanitized}_Grupo_{idx}"
            idx += 1
    group_dir.mkdir(parents=True, exist_ok=True)
    marker = group_dir / GROUP_MARKER_FILENAME
    if not marker.exists():
        marker.write_text('{"kind":"photopic_master_group"}\n', encoding="utf-8")
    return group_dir.name


def resolve_group_parent(group_name: str | None, root_dir: Path) -> tuple[Path, str | None]:
    trimmed = (group_name or "").strip()
    if not trimmed:
        return root_dir, None
    final_name = create_master_group(trimmed, root_dir)
    return root_dir / final_name, final_name


def permanently_delete_session_dir(session_dir: Path, root_dir: Path) -> None:
    root_resolved = root_dir.resolve()
    target_resolved = session_dir.resolve()
    if target_resolved == root_resolved:
        raise ValueError("Bloqueo de seguridad: no se puede eliminar la Carpeta Raíz Global.")
    try:
        rel = target_resolved.relative_to(root_resolved)
    except ValueError as exc:
        raise ValueError("Bloqueo de seguridad: la carpeta está fuera de la Carpeta Raíz Global.") from exc

    if len(rel.parts) not in (1, 2):
        raise ValueError("Bloqueo de seguridad: profundidad de sesión inválida.")
    if not (target_resolved / "RAW").is_dir():
        raise ValueError("Bloqueo de seguridad: la carpeta no es una sesión válida de PhotoPic (falta RAW/).")

    shutil.rmtree(target_resolved)


def load_all_sessions_with_counts(root_dir: Path, count_fn, unique_dir_fn=None) -> list:
    from .models import PhotoSession

    if not root_dir.exists():
        return []
    sessions: list[PhotoSession] = []
    for entry in root_dir.iterdir():
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        if (entry / "RAW").is_dir():
            sessions.append(build_loaded_session(entry, group_name=None, count_fn=count_fn))
            continue
        for sub in entry.iterdir():
            if sub.is_dir() and not sub.name.startswith(".") and (sub / "RAW").is_dir():
                sessions.append(build_loaded_session(sub, group_name=entry.name, count_fn=count_fn))
    return sorted(sessions, key=lambda s: s.created_at, reverse=True)


def build_loaded_session(entry: Path, group_name: str | None, count_fn):
    from .models import PhotoSession

    meta = SessionMetadataStore.load(entry)
    session = PhotoSession(
        name=entry.name,
        directory=entry,
        created_at=entry.stat().st_mtime,
        group_name=group_name,
        tags=list(meta.tags),
        formatted_duration=meta.formatted_duration() if meta.has_recorded_time else None,
    )
    session.counts = count_fn(session)
    return session


def move_session_dir_to_group(session, group_name: str | None, root_dir: Path, unique_dir_fn, count_fn):
    parent_dir, resolved_group = resolve_group_parent(group_name, root_dir)
    if session.directory.parent.resolve() == parent_dir.resolve():
        return session
    dest_dir = unique_dir_fn(parent_dir, session.directory.name)
    shutil.move(str(session.directory), str(dest_dir))
    return build_loaded_session(dest_dir, group_name=resolved_group, count_fn=count_fn)
