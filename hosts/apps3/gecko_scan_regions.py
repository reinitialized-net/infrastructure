"""Overlapping search regions for the reviewed gecko enclosure.

Periodic scans discover small or stationary geckos independently of motion.
Existing tracks still require fresh inference and separate model qualification.
"""


def has_crop_context(box, region, frame_width, frame_height):
    """Require context at artificial crop edges, preserving camera-frame edges.

    A two-pixel margin covers integer box rounding. Overlapping search regions
    provide another view of objects crossing a crop boundary; a truncated
    texture prediction must not become an independently confirmed gecko.
    """
    left, top, right, bottom = (int(value) for value in box)
    return not (
        (region[0] > 0 and left <= region[0] + 2)
        or (region[1] > 0 and top <= region[1] + 2)
        or (region[2] < frame_width and right >= region[2] - 2)
        or (region[3] < frame_height and bottom >= region[3] - 2)
    )


class GeckoScanRegions:
    @classmethod
    def enclosure(cls, width, height):
        # Reviewed camera_13_37 framing: the enclosure ends above row 1200.
        # Refuse another geometry instead of silently masking a different view.
        if (width, height) != (1080, 1920):
            raise ValueError('Gecko enclosure scan requires the reviewed portrait view')
        return cls(width, 1200, per_frame=4)

    def __init__(self, width, height, side=320, overlap=128, per_frame=6):
        if min(width, height) < side or side % 4 or not 0 < overlap < side:
            raise ValueError('Unsupported scan geometry')
        if not 1 <= per_frame <= 8:
            raise ValueError('Invalid per-frame inference bound')
        stride = (side - overlap) // 4 * 4
        if stride == 0:
            raise ValueError('Invalid scan stride')

        def starts(length):
            result = list(range(0, length - side + 1, stride))
            # Pad the final edge through Frigate's normal region extraction.
            last = ((length - side + 3) // 4) * 4
            if result[-1] != last:
                result.append(last)
            return result

        self.regions = [
            (x, y, x + side, y + side)
            for y in starts(height) for x in starts(width)
        ]
        self.per_frame = min(per_frame, len(self.regions))
        self.cursor = 0
        self.width, self.height, self.side = width, height, side

    def next(self):
        result = [
            self.regions[(self.cursor + i) % len(self.regions)]
            for i in range(self.per_frame)
        ]
        self.cursor = (self.cursor + self.per_frame) % len(self.regions)
        return result

    def for_tracks(self, boxes):
        """Recheck tracks only in native grid crops, plus the discovery sweep.

        Generic motion clusters can cover the whole enclosure and shrink small
        textures into shapes the native-resolution model was never qualified on.
        Use two overlapping views per track to preserve context during movement.
        Near grid boundaries, center one native-size crop on the track instead
        of repeatedly presenting a clipped body to both overlapping grid views.
        Even duplicate or oversized track boxes cannot introduce another scale.
        """
        selected = []
        for left, top, right, bottom in boxes:
            candidates = []
            for region in self.regions:
                x, y, z, t = region
                overlap = max(0, min(right, z) - max(left, x)) * max(
                    0, min(bottom, t) - max(top, y)
                )
                if overlap <= 0:
                    continue
                margin = min(left - x, top - y, z - right, t - bottom)
                candidates.append((margin, overlap, region))
            candidates.sort(reverse=True)
            if candidates:
                selected.append(candidates[0][2])
                if candidates[0][0] < 16:
                    x = max(0, min(self.width - self.side,
                                   round((left + right - self.side) / 8) * 4))
                    y = max(0, min(self.height - self.side,
                                   round((top + bottom - self.side) / 8) * 4))
                    selected.append((x, y, x + self.side, y + self.side))
                elif len(candidates) > 1:
                    selected.append(candidates[1][2])
        return list(dict.fromkeys([*selected, *self.next()]))
