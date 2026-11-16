"""Anti-Old-Gallery shield preventing pre-existing SD/phone roll downloads on Windows."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class TetherBaselineGate:
    connected_at_epoch: float
    is_catalog_complete: bool = False
    baseline_keys: set[str] = field(default_factory=set)
    downloaded_or_in_flight_keys: set[str] = field(default_factory=set)
    baseline_max_item_epoch: float | None = None

    @staticmethod
    def item_key(device_item_id: str, filename: str, file_size: int) -> str:
        return f"id:{device_item_id}|n:{filename.lower()}|s:{file_size}"

    def record_pre_catalog_item(self, key: str, item_epoch: float | None) -> None:
        self.baseline_keys.add(key)
        if item_epoch is not None:
            if self.baseline_max_item_epoch is None or item_epoch > self.baseline_max_item_epoch:
                self.baseline_max_item_epoch = item_epoch

    def mark_catalog_complete(self) -> None:
        self.is_catalog_complete = True

    def should_download_live_item(
        self,
        key: str,
        item_epoch: float | None,
        was_added_after_catalog: bool = False,
    ) -> bool:
        if not self.is_catalog_complete:
            self.record_pre_catalog_item(key, item_epoch)
            return False

        if key in self.baseline_keys or key in self.downloaded_or_in_flight_keys:
            return False

        if was_added_after_catalog:
            self.downloaded_or_in_flight_keys.add(key)
            return True

        skew_tolerance = 2.0
        if item_epoch is not None:
            after_conn = item_epoch >= (self.connected_at_epoch - skew_tolerance)
            after_max = (
                item_epoch >= (self.baseline_max_item_epoch - skew_tolerance)
                if self.baseline_max_item_epoch is not None
                else True
            )
            is_newer = after_conn or after_max
        else:
            is_newer = True

        if is_newer:
            self.downloaded_or_in_flight_keys.add(key)
            return True

        self.baseline_keys.add(key)
        return False
