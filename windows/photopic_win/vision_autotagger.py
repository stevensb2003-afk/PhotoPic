"""100% offline AI auto-tagger for Windows (MediaPipe Pose/FaceMesh + OpenCV fallback)."""

from __future__ import annotations

import math
from typing import Any

from .models import PhotoVisionTags


class VisionAutoTaggerWin:
    """Detects faces, eye openness (EAR), framing, people count, and body poses offline."""

    def __init__(self) -> None:
        self._mp: Any = None
        self._cv2: Any = None
        self._np: Any = None
        try:
            import cv2
            import numpy as np
            self._cv2 = cv2
            self._np = np
        except ImportError:
            pass
        try:
            import mediapipe as mp
            self._mp = mp
        except ImportError:
            pass

    def analyze_rgb_bytes(
        self,
        rgb_bytes: bytes,
        width: int,
        height: int,
        include_body_pose: bool = True,
    ) -> PhotoVisionTags:
        if self._np is None or self._cv2 is None or not rgb_bytes:
            return PhotoVisionTags(person_count=0, face_count=0, auto_tags=["Sin análisis IA"])

        arr = self._np.frombuffer(rgb_bytes, dtype=self._np.uint8).reshape((height, width, 3))
        if self._mp is not None and hasattr(self._mp, "solutions"):
            return self._analyze_with_mediapipe(arr, include_body_pose=include_body_pose)
        return self._analyze_with_opencv_fallback(arr)

    def _analyze_with_mediapipe(self, rgb_array: Any, include_body_pose: bool = True) -> PhotoVisionTags:
        mp_face = self._mp.solutions.face_detection
        mp_mesh = self._mp.solutions.face_mesh
        mp_pose = self._mp.solutions.pose

        face_boxes: list[tuple[float, float, float, float]] = []
        with mp_face.FaceDetection(model_selection=1, min_detection_confidence=0.65) as det:
            res = det.process(rgb_array)
            if res.detections:
                for d in res.detections:
                    bb = d.location_data.relative_bounding_box
                    if bb.width >= 0.025 and bb.height >= 0.025 and (bb.width * bb.height) >= 0.0008:
                        face_boxes.append((bb.xmin, bb.ymin, bb.width, bb.height))
        face_boxes = self._dedupe_boxes(face_boxes)

        has_closed_eyes = False
        eye_verified_open = False
        with mp_mesh.FaceMesh(
            static_image_mode=True,
            max_num_faces=6,
            refine_landmarks=True,
            min_detection_confidence=0.65,
        ) as mesh:
            mesh_res = mesh.process(rgb_array)
            if mesh_res.multi_face_landmarks:
                for lm in mesh_res.multi_face_landmarks:
                    eyes = self._compute_face_ears(lm.landmark)
                    if eyes is None:
                        continue
                    left_ear, right_ear = eyes
                    if left_ear < 0.16 and right_ear < 0.16 and ((left_ear + right_ear) * 0.5) < 0.155:
                        has_closed_eyes = True
                    elif left_ear >= 0.185 or right_ear >= 0.185:
                        eye_verified_open = True

        pose_tags: list[str] = []
        pose_detected = False
        if include_body_pose:
            with mp_pose.Pose(static_image_mode=True, model_complexity=1, min_detection_confidence=0.65) as pose:
                p_res = pose.process(rgb_array)
                if p_res.pose_landmarks:
                    visible_joints = sum(
                        1 for pt in p_res.pose_landmarks.landmark if getattr(pt, "visibility", 1.0) >= 0.55
                    )
                    if visible_joints >= 6:
                        pose_detected = True
                        pose_tags = self._classify_pose_landmarks(p_res.pose_landmarks.landmark)

        person_count = max(len(face_boxes), 1 if pose_detected else 0)
        tags = self._compose_people_tags(person_count)
        if person_count == 0:
            return PhotoVisionTags(person_count=0, face_count=0, auto_tags=tags)

        max_face_h = max((b[3] for b in face_boxes), default=0.0)
        if max_face_h >= 0.25:
            tags.append("Primer plano")
        elif max_face_h >= 0.10:
            tags.append("Plano medio")
        elif pose_detected:
            tags.append("Cuerpo entero")
        elif face_boxes:
            tags.append("Retrato")

        if has_closed_eyes:
            tags.append("Ojos cerrados")
        elif eye_verified_open:
            tags.append("Ojos abiertos")

        tags.extend(pose_tags)
        return PhotoVisionTags(
            person_count=person_count,
            face_count=len(face_boxes),
            has_closed_eyes_warning=has_closed_eyes,
            auto_tags=self._dedupe(tags),
        )

    def _analyze_with_opencv_fallback(self, rgb_array: Any) -> PhotoVisionTags:
        gray = self._cv2.cvtColor(rgb_array, self._cv2.COLOR_RGB2GRAY)
        cascade_path = self._cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
        cascade = self._cv2.CascadeClassifier(cascade_path)
        faces = cascade.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=7, minSize=(40, 40))
        face_count = len(faces)
        tags = self._compose_people_tags(face_count)
        if face_count > 0:
            max_h_ratio = max(h / max(1, rgb_array.shape[0]) for (_, _, _, h) in faces)
            tags.append("Primer plano" if max_h_ratio >= 0.25 else "Plano medio")
        return PhotoVisionTags(person_count=face_count, face_count=face_count, auto_tags=self._dedupe(tags))

    @staticmethod
    def _compose_people_tags(count: int) -> list[str]:
        if count <= 0:
            return ["Sin personas"]
        if count == 1:
            return ["1 persona", "Individual"]
        if count == 2:
            return ["2 personas", "Pareja"]
        if count <= 5:
            return [f"{count} personas", "Grupo"]
        return [f"{count} personas", "Grupo grande"]

    @staticmethod
    def _compute_face_ears(lm: Any) -> tuple[float, float] | None:
        # Reject tiny distant faces and steep side profiles to avoid false "Ojos cerrados".
        face_h = abs(lm[152].y - lm[10].y)
        if face_h < 0.055:
            return None
        left_cheek = abs(lm[1].x - lm[33].x)
        right_cheek = abs(lm[263].x - lm[1].x)
        if left_cheek < 0.005 or right_cheek < 0.005:
            return None
        yaw_ratio = left_cheek / right_cheek
        if yaw_ratio < 0.35 or yaw_ratio > 2.8:
            return None

        left_w = abs(lm[33].x - lm[133].x)
        right_w = abs(lm[362].x - lm[263].x)
        if left_w < 0.008 or right_w < 0.008:
            return None
        left_ear = abs(lm[159].y - lm[145].y) / left_w
        right_ear = abs(lm[386].y - lm[374].y) / right_w
        return (left_ear, right_ear)

    @staticmethod
    def _compute_face_ear(lm: Any) -> float:
        ears = VisionAutoTaggerWin._compute_face_ears(lm)
        if ears is None:
            return 0.25
        return (ears[0] + ears[1]) * 0.5

    @staticmethod
    def _dedupe_boxes(boxes: list[tuple[float, float, float, float]]) -> list[tuple[float, float, float, float]]:
        kept: list[tuple[float, float, float, float]] = []
        for box in boxes:
            bx, by, bw, bh = box
            overlaps = False
            for kx, ky, kw, kh in kept:
                ix1, iy1 = max(bx, kx), max(by, ky)
                ix2, iy2 = min(bx + bw, kx + kw), min(by + bh, ky + kh)
                if ix2 > ix1 and iy2 > iy1:
                    inter = (ix2 - ix1) * (iy2 - iy1)
                    union = (bw * bh) + (kw * kh) - inter
                    if union > 0 and (inter / union) > 0.45:
                        overlaps = True
                        break
            if not overlaps:
                kept.append(box)
        return kept

    @staticmethod
    def _classify_pose_landmarks(lm: Any) -> list[str]:
        tags: list[str] = []

        def visible(idx: int, min_vis: float = 0.55) -> bool:
            return getattr(lm[idx], "visibility", 1.0) >= min_vis

        # MediaPipe Y grows downward (0 = top edge)
        if (visible(15) and visible(13) and visible(11) and lm[15].y < lm[11].y - 0.06) or (
            visible(16) and visible(14) and visible(12) and lm[16].y < lm[12].y - 0.06
        ):
            tags.append("Brazos arriba")

        if visible(15) and visible(16) and visible(13) and visible(14) and visible(23) and visible(24):
            hip_span = max(0.08, math.hypot(lm[24].x - lm[23].x, lm[24].y - lm[23].y))
            hip_radius = min(0.14, max(0.06, hip_span * 0.65))
            left_near_hip = math.hypot(lm[15].x - lm[23].x, lm[15].y - lm[23].y) < hip_radius
            right_near_hip = math.hypot(lm[16].x - lm[24].x, lm[16].y - lm[24].y) < hip_radius
            if left_near_hip and right_near_hip:
                tags.append("Manos en cintura")

        if visible(11) and visible(12) and visible(23) and visible(24) and visible(25) and visible(26):
            shoulder_y = (lm[11].y + lm[12].y) * 0.5
            hip_y = (lm[23].y + lm[24].y) * 0.5
            knee_y = (lm[25].y + lm[26].y) * 0.5
            torso = max(0.06, hip_y - shoulder_y)
            thigh = knee_y - hip_y
            tags.append("Sentado" if thigh < torso * 0.50 else "De pie")
        return tags

    @staticmethod
    def _dedupe(items: list[str]) -> list[str]:
        seen: set[str] = set()
        out: list[str] = []
        for item in items:
            if item not in seen:
                seen.add(item)
                out.append(item)
        return out
