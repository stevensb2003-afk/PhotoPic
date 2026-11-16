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
        with mp_face.FaceDetection(model_selection=1, min_detection_confidence=0.45) as det:
            res = det.process(rgb_array)
            if res.detections:
                for d in res.detections:
                    bb = d.location_data.relative_bounding_box
                    face_boxes.append((bb.xmin, bb.ymin, bb.width, bb.height))

        has_closed_eyes = False
        eye_verified_open = False
        with mp_mesh.FaceMesh(static_image_mode=True, max_num_faces=6, refine_landmarks=True) as mesh:
            mesh_res = mesh.process(rgb_array)
            if mesh_res.multi_face_landmarks:
                for lm in mesh_res.multi_face_landmarks:
                    ear = self._compute_face_ear(lm.landmark)
                    if ear < 0.17:
                        has_closed_eyes = True
                    else:
                        eye_verified_open = True

        pose_tags: list[str] = []
        pose_detected = False
        if include_body_pose:
            with mp_pose.Pose(static_image_mode=True, model_complexity=1, min_detection_confidence=0.45) as pose:
                p_res = pose.process(rgb_array)
                if p_res.pose_landmarks:
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
        faces = cascade.detectMultiScale(gray, scaleFactor=1.15, minNeighbors=5, minSize=(28, 28))
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
    def _compute_face_ear(lm: Any) -> float:
        # MediaPipe FaceMesh eye vertical vs horizontal landmarks (top-left origin)
        left_ear = abs(lm[159].y - lm[145].y) / max(0.0001, abs(lm[33].x - lm[133].x))
        right_ear = abs(lm[386].y - lm[374].y) / max(0.0001, abs(lm[362].x - lm[263].x))
        return (left_ear + right_ear) * 0.5

    @staticmethod
    def _classify_pose_landmarks(lm: Any) -> list[str]:
        tags: list[str] = []
        # MediaPipe Y grows downward (0 = top edge)
        if lm[15].y < lm[11].y - 0.04 or lm[16].y < lm[12].y - 0.04:
            tags.append("Brazos arriba")

        left_near_hip = math.hypot(lm[15].x - lm[23].x, lm[15].y - lm[23].y) < 0.11
        right_near_hip = math.hypot(lm[16].x - lm[24].x, lm[16].y - lm[24].y) < 0.11
        if left_near_hip and right_near_hip:
            tags.append("Manos en cintura")

        shoulder_y = (lm[11].y + lm[12].y) * 0.5
        hip_y = (lm[23].y + lm[24].y) * 0.5
        knee_y = (lm[25].y + lm[26].y) * 0.5
        torso = max(0.05, hip_y - shoulder_y)
        thigh = knee_y - hip_y
        tags.append("Sentado" if thigh < torso * 0.52 else "De pie")
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
