"""Experimental overlapping search regions; not enabled in production.

Periodic scans discover small or stationary geckos independently of motion.
Existing tracks still require fresh inference and separate model qualification.
"""

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

    def next(self):
        result = [
            self.regions[(self.cursor + i) % len(self.regions)]
            for i in range(self.per_frame)
        ]
        self.cursor = (self.cursor + self.per_frame) % len(self.regions)
        return result
