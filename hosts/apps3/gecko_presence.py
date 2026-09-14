"""Experimental visual evidence of departure before a return to the same position.

Detector dropouts and ID changes alone must not renew a stationary recording.
This helper requires both missing observations and a changed, stabilized image
patch. It is a component heuristic requiring real-footage qualification.
"""
import cv2
import numpy as np


def overlap(a, b):
    intersection = max(0, min(a[2], b[2])-max(a[0], b[0])) * max(0, min(a[3], b[3])-max(a[1], b[1]))
    return intersection / ((a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-intersection)


class GeckoPresence:
    def __init__(self):
        self.states = []
        self.identities = {}

    @staticmethod
    def patch(frame, box):
        x, y, right, bottom = box
        # The inner body patch reduces unrelated background at box edges.
        dx, dy = (right-x)//8, (bottom-y)//8
        x, y = max(0, x+dx), max(0, y+dy)
        right, bottom = min(frame.shape[1], right-dx), min(frame.shape[0], bottom-dy)
        if right <= x or bottom <= y:
            return None
        patch = cv2.resize(frame[y:bottom, x:right], (32, 32)).astype(np.float32)
        patch -= patch.mean()
        norm = np.linalg.norm(patch)
        return patch/norm if norm > 96 else None

    def begin(self, frame, timestamp, uncertain):
        self.frame, self.timestamp = frame, timestamp
        self.states = [state for state in self.states if timestamp-state['seen'] <= 120]
        self.identities = {key: state for key, state in self.identities.items() if any(state is active for active in self.states)}
        for state in self.states:
            if uncertain:
                state.update(reference=None, changed_since=None, departed=False)
                continue
            if timestamp-state['seen'] <= 1 or state['reference'] is None:
                continue
            patch = self.patch(frame, state['box'])
            changed = patch is not None and float(np.sum(patch*state['reference'])) < .90
            if changed:
                if state['changed_since'] is None:
                    state['changed_since'] = timestamp
                elif timestamp-state['changed_since'] >= .6:
                    state['departed'] = True
            else:
                state['changed_since'] = None

    def confirm(self, identity, box):
        state = self.identities.get(identity)
        if state is None:
            matches = [s for s in self.states if overlap(box, s['box']) >= .5]
            if len(matches) > 1:
                return False
            state = matches[0] if matches else None
        if state is None:
            if len(self.states) >= 64 or len(self.identities) >= 256:
                return False
            state = dict(box=box, seen=self.timestamp, reference=None, changed_since=None, departed=False)
            self.states.append(state)
        returned = state['departed']
        state.update(box=box, seen=self.timestamp, reference=self.patch(self.frame, box), changed_since=None, departed=False)
        if len(self.identities) < 256:
            self.identities[identity] = state
        return returned
