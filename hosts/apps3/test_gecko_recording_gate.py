"""Temporal-policy tests only; passing does not qualify a gecko detector."""

import unittest

from gecko_recording_gate import GeckoRecordingGate


def gecko(t, *, name="a", moving=False, box=(10, 10, 90, 90), **changes):
    return dict(
        {"id": name, "label": "gecko", "false_positive": False, "score": 0.9,
         "frame_time": t, "box": box, "motionless_count": 0 if moving else 1,
         "position_changes": 1 if moving else 0}, **changes,
    )


class GateTests(unittest.TestCase):
    def setUp(self):
        self.gate = GeckoRecordingGate()

    def observe(self, t, **options):
        self.gate.observe(t, [gecko(t, **options)])

    def test_initial_still_object_and_thirty_second_limit(self):
        for t in range(61):
            self.observe(t)
        self.assertTrue(self.gate.allows(0, 30))
        self.assertFalse(self.gate.allows(0, 30.001))
        self.assertFalse(self.gate.allows(31, 35))

    def test_partial_body_relocalization_cannot_restart_quiet_recording(self):
        for t in range(81):
            if t < 40:
                self.observe(t, name="whole", box=(448, 1027, 595, 1086))
            elif t < 60:
                self.observe(t, name="torso", box=(455, 1026, 505, 1075))
            else:
                self.observe(t, name="whole-again", box=(448, 1027, 595, 1086))
        self.assertTrue(self.gate.allows(0, 30))
        self.assertEqual(self.gate.accepted_intervals(30, 81), [])

    def test_tail_requires_actual_subsequent_observations(self):
        self.observe(100, moving=True)
        self.assertFalse(self.gate.allows(100, 105))
        for t in range(101, 106):
            self.observe(t)
        self.assertTrue(self.gate.allows(100, 105))
        self.assertFalse(self.gate.allows(100, 106))

    def test_motion_renews_only_that_geckos_deadline(self):
        for t in range(71):
            self.observe(t, moving=t == 20)
        self.assertTrue(self.gate.allows(0, 50))
        self.assertFalse(self.gate.allows(0, 51))

    def test_renewed_movement_does_not_fill_expired_gap(self):
        for t in range(36):
            self.observe(t, moving=t == 31)
        self.assertTrue(self.gate.allows(0, 30))
        self.assertTrue(self.gate.allows(31, 35))
        self.assertFalse(self.gate.allows(29, 32))

    def test_no_unrelated_labels_or_false_positives(self):
        for t in range(40):
            self.gate.observe(t, [gecko(t, label="person", moving=True),
                                  gecko(t, name="false", false_positive=True)])
        self.assertEqual(self.gate.windows, [])

    def test_unrelated_motion_cannot_extend_a_still_gecko(self):
        for t in range(40):
            self.gate.observe(t, [gecko(t), gecko(t, name="person", label="person", moving=True)])
        self.assertTrue(self.gate.allows(0, 30))
        self.assertFalse(self.gate.allows(30, 35))

    def test_sticky_confirmation_cannot_retain_weak_background_associations(self):
        for t in range(6):
            self.observe(t)
        for t in range(6, 40):
            self.observe(t, score=0.2, moving=True)
        self.assertTrue(self.gate.allows(0, 5))
        self.assertFalse(self.gate.allows(5, 6))
        self.assertFalse(self.gate.allows(30, 35))

    def test_invalid_current_confidence_never_authorizes_video(self):
        for score in (None, True, float('nan'), float('inf'), -1, 1.01):
            gate = GeckoRecordingGate()
            for t in range(5):
                gate.observe(t, [gecko(t, score=score)])
            self.assertEqual(gate.windows, [])

    def test_disappearance_breaks_coverage(self):
        for t in range(6):
            self.observe(t)
        self.gate.observe(6, [])
        self.observe(7)
        self.observe(8)
        self.assertTrue(self.gate.allows(0, 5))
        self.assertTrue(self.gate.allows(7, 8))
        self.assertFalse(self.gate.allows(4, 8))

    def test_slow_or_stalled_capture_does_not_fill_missing_time(self):
        self.observe(0)
        self.observe(5)
        self.observe(6)
        self.assertFalse(self.gate.allows(0, 6))
        self.assertTrue(self.gate.allows(5, 6))
        self.assertFalse(self.gate.allows(6, 100))

    def test_duplicate_and_out_of_order_movement_cannot_renew(self):
        for t in range(41):
            self.observe(t)
            self.observe(t, moving=True)
            self.observe(t - 1, moving=True)
        self.assertFalse(self.gate.allows(30, 35))

    def test_stale_object_cannot_authorize_current_frame(self):
        for t in range(5):
            self.gate.observe(t, [gecko(t - 1)])
        self.assertEqual(self.gate.windows, [])

    def test_stationary_identity_churn_does_not_restart(self):
        for t in range(61):
            self.observe(t, name=str(t), motionless_count=0)
        self.assertTrue(self.gate.allows(0, 30))
        self.assertFalse(self.gate.allows(31, 35))

    def test_multiple_geckos_any_verified_movement_can_keep_recording(self):
        for t in range(61):
            self.gate.observe(t, [gecko(t), gecko(t, name="b", box=(200, 10, 280, 90), moving=t == 20)])
        self.assertTrue(self.gate.allows(0, 50))
        self.assertFalse(self.gate.allows(50, 55))

    def test_staggered_discovery_of_seven_still_geckos_does_not_extend_quiet_tail(self):
        for t in range(71):
            self.gate.observe(t, [
                gecko(t, name=str(i), box=(i * 100, 10, i * 100 + 80, 90))
                for i in range(7) if t >= i * 3
            ])
        self.assertTrue(self.gate.allows(0, 30))
        self.assertFalse(self.gate.allows(30, 31))
        self.assertFalse(self.gate.allows(40, 45))

    def test_new_site_after_expired_quiet_tail_can_start_a_later_recording(self):
        for t in range(81):
            objects = [gecko(t)]
            if t >= 40:
                objects.append(gecko(t, name="new", box=(200, 10, 280, 90)))
            self.gate.observe(t, objects)
        self.assertTrue(self.gate.allows(0, 30))
        self.assertFalse(self.gate.allows(30, 40))
        self.assertTrue(self.gate.allows(40, 70))
        self.assertFalse(self.gate.allows(70, 71))

    def test_new_site_after_observation_outage_does_not_fill_the_outage(self):
        self.observe(0)
        for t in range(100, 141):
            self.gate.observe(t, [gecko(t, name="new", box=(200, 10, 280, 90))])
        self.assertFalse(self.gate.allows(0, 100))
        self.assertTrue(self.gate.allows(100, 130))
        self.assertFalse(self.gate.allows(130, 131))

    def test_segment_boundaries_never_include_pre_or_extra_post_footage(self):
        for t in range(100, 131):
            self.observe(t)
        self.assertFalse(self.gate.allows(98, 103))
        self.assertTrue(self.gate.allows(103, 108))
        self.assertFalse(self.gate.allows(129, 134))

    def test_restart_has_no_historical_authorization(self):
        for t in range(6):
            self.observe(t)
        restarted = GeckoRecordingGate()
        self.assertFalse(restarted.allows(0, 5))

    def test_trim_intervals_preserve_brief_events_and_real_gaps(self):
        for t in range(100, 141):
            self.observe(t, moving=t == 132)
        self.assertEqual(self.gate.accepted_intervals(98, 105), [(100, 105)])
        self.assertEqual(self.gate.accepted_intervals(129, 134), [(129, 130), (132, 134)])
        self.assertEqual(self.gate.accepted_intervals(140, 145), [])
        self.assertEqual(self.gate.accepted_intervals(float("nan"), 145), [])

    def test_old_history_is_bounded(self):
        for t in range(2000):
            self.gate.observe(t, [gecko(t, name=str(t), box=(t * 100, 10, t * 100 + 80, 90))] if t % 2 else [])
        self.assertLessEqual(len(self.gate.windows), 61)
        self.assertLessEqual(len(self.gate.tracks), 64)
        self.assertLessEqual(len(self.gate.identities), 256)
        self.assertFalse(self.gate.allows(1, 2))

    def test_malformed_objects_fail_closed(self):
        for obj in [None, {}, gecko(0, box=(0, 0, 0, 0)), gecko(0, box=(0, 0, float('nan'), 10)),
                    gecko(0, motionless_count=-1), gecko(0, position_changes=True)]:
            gate = GeckoRecordingGate()
            gate.observe(0, [obj])
            self.assertEqual(gate.windows, [])
        self.assertFalse(self.gate.allows(float('nan'), 1))
        self.assertFalse(self.gate.allows(1, float('inf')))
        self.assertFalse(self.gate.allows(5, 1))


if __name__ == "__main__":
    unittest.main()
