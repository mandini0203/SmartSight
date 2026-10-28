"""Deterministic rule-based context reasoner (baseline, not a trained model).

Inputs are detections (normally real YOLOv8 output). Every relationship, seat
assessment and guidance sentence carries the evidence that produced it and a
heuristic confidence. Confidences are rule scores, not calibrated
probabilities.
"""

from __future__ import annotations

from collections import Counter

from app.schemas.common import BoundingBox, ComponentInfo, FrameInfo
from app.schemas.context import (
    AnalysedObject,
    ContextRequest,
    ContextResponse,
    Guidance,
    Relationship,
    RelationshipType,
    SeatAssessment,
    SeatStatus,
    TaskType,
)
from app.services.distance import spoken_distance
from app.services.interfaces import ContextReasoner, DistanceEstimator
from app.services.spatial import horizontal_overlap, intersection_area, relative_position

DISCLAIMER = (
    "SmartSight gives assistive information from a single camera image. Results are "
    "estimates and can be wrong or incomplete. Keep using your cane, guide dog or other "
    "mobility aid, and confirm important information before relying on it."
)

SEAT_LABELS = {"chair", "couch", "bench"}
MULTI_SEAT_LABELS = {"couch", "bench"}
SURFACE_LABELS = {"dining table", "bed", "couch", "chair", "bench", "toilet", "sink", "refrigerator"}
PORTABLE_LABELS = {
    "cell phone", "cup", "bottle", "wine glass", "book", "laptop", "remote", "keyboard",
    "mouse", "backpack", "handbag", "suitcase", "umbrella", "bowl", "scissors", "clock",
    "vase", "teddy bear", "toothbrush", "banana", "apple", "orange", "sandwich", "pizza",
    "donut", "cake", "fork", "knife", "spoon", "tie", "sports ball",
}
BELONGING_LABELS = {"backpack", "handbag", "suitcase", "laptop", "book", "umbrella", "cell phone"}
EXIT_LABELS = {"exit sign", "door"}

# Rule thresholds (fixed, documented in docs/CONTEXT_RULES.md).
OCCUPY_SEAT_COVER = 0.30      # person box covers >=30 % of the seat box
OCCUPY_PARTIAL_COVER = 0.08   # 8-30 %: someone near/behind the seat
ON_TOP_H_OVERLAP = 0.60       # >=60 % of the item's width lies over the surface
NEXT_TO_GAP = 0.5             # horizontal gap < 0.5 x the wider box width
NEXT_TO_BASELINE = 0.10       # bottoms within 10 % of frame height
MAX_DESCRIBED = 5


def _plural(label: str, n: int) -> str:
    if n == 1:
        article = "an" if label[0] in "aeiou" else "a"
        return f"{article} {label}"
    irregular = {"person": "people", "couch": "couches", "bench": "benches", "knife": "knives",
                 "sandwich": "sandwiches", "bus": "buses", "wine glass": "wine glasses",
                 "glass": "glasses", "mouse": "mice"}
    return f"{n} {irregular.get(label, label + 's')}"


def _join(parts: list[str]) -> str:
    if len(parts) <= 1:
        return "".join(parts)
    return ", ".join(parts[:-1]) + " and " + parts[-1]


class RuleBasedContextReasoner(ContextReasoner):
    def __init__(self, distance: DistanceEstimator | None, default_fov: float = 66.0,
                 detector_classes: list[str] | None = None) -> None:
        self.distance = distance
        self.default_fov = default_fov
        self.detector_classes = set(detector_classes or [])

    @property
    def info(self) -> ComponentInfo:
        return ComponentInfo(
            name="rule_based_context",
            version="1.0",
            is_trained_model=False,
            description="Deterministic geometric rules over detector output (baseline; not a trained model).",
        )

    # ------------------------------------------------------------------
    def analyse(self, request: ContextRequest, fov_degrees: float | None = None) -> ContextResponse:
        frame = request.frame
        fov = fov_degrees or self.default_fov
        objects = self._objects(request, frame, fov)
        relationships = self._relationships(objects, frame)
        seats = self._seats(objects)

        task = request.task
        if task == TaskType.FIND_OBJECT:
            relevant, guidance = self._guide_find_object(objects, relationships, request.target_label)
        elif task == TaskType.FIND_SEAT:
            relevant, guidance = self._guide_find_seat(seats, objects)
        elif task == TaskType.FIND_EXIT:
            relevant, guidance = self._guide_find_exit(objects)
        elif task == TaskType.IDENTIFY_COLOUR:
            relevant, guidance = self._guide_colour(objects, request.target_label)
        else:
            relevant, guidance = self._guide_describe(objects, seats)

        # Report only relationships that involve task-relevant objects when a task focuses on them.
        if task != TaskType.DESCRIBE_SURROUNDINGS and relevant:
            rel_set = set(relevant)
            relationships = [r for r in relationships if r.subject_id in rel_set or r.object_id in rel_set]

        return ContextResponse(
            task=task,
            frame=frame,
            objects=objects,
            relevant_object_ids=relevant,
            relationships=relationships,
            seats=seats,
            guidance=guidance,
            reasoner=self.info,
            disclaimer=DISCLAIMER,
        )

    # -- object preparation -------------------------------------------------
    def _objects(self, request: ContextRequest, frame: FrameInfo, fov: float) -> list[AnalysedObject]:
        objs: list[AnalysedObject] = []
        used_ids: set[int] = set()
        for i, d in enumerate(request.detections):
            oid = d.id if d.id is not None and d.id not in used_ids else i
            while oid in used_ids:
                oid += 1000
            used_ids.add(oid)
            bbox = BoundingBox(
                x1=min(d.bbox.x1, frame.width - 1), y1=min(d.bbox.y1, frame.height - 1),
                x2=min(d.bbox.x2, frame.width), y2=min(d.bbox.y2, frame.height),
            )
            dist = self.distance.estimate(d.label, bbox, frame, fov) if self.distance else None
            objs.append(AnalysedObject(
                id=oid, label=d.label, confidence=d.confidence, bbox=bbox,
                position=relative_position(bbox, frame, fov), distance=dist,
            ))
        return objs

    # -- relationships ------------------------------------------------------
    def _relationships(self, objs: list[AnalysedObject], frame: FrameInfo) -> list[Relationship]:
        rels: list[Relationship] = []
        for a in objs:
            for b in objs:
                if a.id == b.id:
                    continue
                r = self._on_top_of(a, b)
                if r:
                    rels.append(r)
        # next_to: only between portable items / seats, once per unordered pair.
        for i, a in enumerate(objs):
            for b in objs[i + 1:]:
                r = self._next_to(a, b, frame)
                if r:
                    rels.append(r)
        rels.sort(key=lambda r: r.confidence, reverse=True)
        return rels[:40]

    def _on_top_of(self, item: AnalysedObject, surface: AnalysedObject) -> Relationship | None:
        if item.label not in PORTABLE_LABELS or surface.label not in SURFACE_LABELS:
            return None
        ib, sb = item.bbox, surface.bbox
        if ib.area >= sb.area:
            return None
        h_ov = horizontal_overlap(ib, sb)
        bottom_in_upper = sb.y1 - 0.1 * sb.height <= ib.y2 <= sb.y1 + 0.6 * sb.height
        if h_ov < ON_TOP_H_OVERLAP or not bottom_in_upper:
            return None
        geometry = min(1.0, 0.5 + 0.5 * h_ov)
        conf = round(geometry * min(item.confidence, surface.confidence) * 0.9, 2)
        return Relationship(
            type=RelationshipType.ON_TOP_OF,
            subject_id=item.id, subject_label=item.label,
            object_id=surface.id, object_label=surface.label,
            confidence=conf,
            evidence=[
                f"{h_ov:.0%} of the {item.label}'s width lies over the {surface.label}",
                f"the {item.label}'s bottom edge is within the upper part of the {surface.label}'s box",
                "2-D image overlap only; depth is not measured, so this is a candidate relationship",
            ],
        )

    def _next_to(self, a: AnalysedObject, b: AnalysedObject, frame: FrameInfo) -> Relationship | None:
        if a.label == "person" or b.label == "person":
            return None
        ab, bb = a.bbox, b.bbox
        if intersection_area(ab, bb) > 0.2 * min(ab.area, bb.area):
            return None
        gap = max(bb.x1 - ab.x2, ab.x1 - bb.x2, 0.0)
        if gap > NEXT_TO_GAP * max(ab.width, bb.width):
            return None
        if abs(ab.y2 - bb.y2) > NEXT_TO_BASELINE * frame.height:
            return None
        left, right = (a, b) if ab.centre[0] < bb.centre[0] else (b, a)
        conf = round(0.6 * min(a.confidence, b.confidence), 2)
        return Relationship(
            type=RelationshipType.LEFT_OF,
            subject_id=left.id, subject_label=left.label,
            object_id=right.id, object_label=right.label,
            confidence=conf,
            evidence=[
                f"boxes are {gap:.0f} px apart horizontally with similar bottom edges",
                f"the {left.label} is to the left of the {right.label} in the image",
                "similar image height suggests, but does not prove, similar depth",
            ],
        )

    # -- seats --------------------------------------------------------------
    def _seats(self, objs: list[AnalysedObject]) -> list[SeatAssessment]:
        people = [o for o in objs if o.label == "person"]
        belongings = [o for o in objs if o.label in BELONGING_LABELS]
        out: list[SeatAssessment] = []
        for seat in (o for o in objs if o.label in SEAT_LABELS):
            out.append(self._assess_seat(seat, people, belongings))
        out.sort(key=lambda s: ({SeatStatus.POTENTIALLY_UNOCCUPIED: 0, SeatStatus.UNCERTAIN: 1,
                                 SeatStatus.LIKELY_OCCUPIED: 2}[s.status], -s.confidence))
        return out

    def _assess_seat(self, seat: AnalysedObject, people: list[AnalysedObject],
                     belongings: list[AnalysedObject]) -> SeatAssessment:
        sb = seat.bbox
        evidence: list[str] = [f"{seat.label} detected with confidence {seat.confidence:.2f}"]
        best_cover, best_person = 0.0, None
        for p in people:
            cover = intersection_area(p.bbox, sb) / max(sb.area, 1e-6)
            if cover > best_cover:
                best_cover, best_person = cover, p

        sitting_geometry = False
        if best_person is not None:
            pb = best_person.bbox
            cx = pb.centre[0]
            # A seated person's box ends inside or just below the seat box and is centred over it.
            sitting_geometry = sb.x1 <= cx <= sb.x2 and pb.y2 >= sb.y1 + 0.3 * sb.height

        if best_person is not None and best_cover >= OCCUPY_SEAT_COVER and sitting_geometry:
            evidence.append(f"a person's box covers {best_cover:.0%} of the {seat.label}")
            evidence.append("the person is centred over the seat and extends into its lower part")
            status = SeatStatus.LIKELY_OCCUPIED
            conf = min(0.9, 0.5 + 0.5 * best_cover) * min(seat.confidence, best_person.confidence) ** 0.5
            if seat.label in MULTI_SEAT_LABELS and best_cover < 0.5:
                status = SeatStatus.UNCERTAIN
                evidence.append(f"a {seat.label} can seat several people; part of it may still be free")
                conf *= 0.8
        elif best_person is not None and best_cover >= OCCUPY_PARTIAL_COVER:
            status = SeatStatus.UNCERTAIN
            evidence.append(f"a person's box overlaps {best_cover:.0%} of the {seat.label}; "
                            "they may be sitting, standing next to it or behind it")
            conf = 0.5 * seat.confidence
        else:
            items_on_seat = [
                b for b in belongings
                if intersection_area(b.bbox, sb) >= 0.5 * b.bbox.area and b.bbox.area < sb.area
            ]
            if items_on_seat:
                status = SeatStatus.UNCERTAIN
                evidence.append(
                    f"{_join([_plural(b.label, 1) for b in items_on_seat])} appear on the {seat.label}; "
                    "it may be in use or reserved"
                )
                conf = 0.5 * seat.confidence
            elif seat.confidence < 0.5:
                status = SeatStatus.UNCERTAIN
                evidence.append("seat detection confidence is low")
                conf = 0.4 * seat.confidence
            else:
                status = SeatStatus.POTENTIALLY_UNOCCUPIED
                evidence.append(f"no person detected overlapping the {seat.label}")
                conf = 0.75 * seat.confidence
        evidence.append("a person or object hidden from the camera cannot be ruled out")
        return SeatAssessment(
            detection_id=seat.id, label=seat.label, status=status,
            confidence=round(min(conf, 0.9), 2), evidence=evidence, position=seat.position,
        )

    # -- guidance -----------------------------------------------------------
    @staticmethod
    def _where(o: AnalysedObject) -> str:
        text = o.position.description.split(",")[0]
        text += f", at {o.position.clock_label}"
        if o.distance:
            text += f", {spoken_distance(o.distance)}"
        return text

    def _guide_describe(self, objs: list[AnalysedObject], seats: list[SeatAssessment]):
        if not objs:
            return [], Guidance(
                message="I did not detect any recognisable objects. Try pointing the camera at a different area.",
                confidence=0.3,
                evidence=["no detections above the confidence threshold"],
            )
        counts = Counter(o.label for o in objs)
        ordered = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
        summary = _join([_plural(lbl, n) for lbl, n in ordered[:MAX_DESCRIBED]])
        if len(ordered) > MAX_DESCRIBED:
            summary += f", and {len(ordered) - MAX_DESCRIBED} other kinds of object"
        # Most prominent = largest apparent area weighted by confidence.
        prominent = sorted(objs, key=lambda o: o.position.area_ratio * o.confidence, reverse=True)
        top = prominent[0]
        details = [f"{o.label}: {self._where(o)}" for o in prominent[:MAX_DESCRIBED]]
        free = [s for s in seats if s.status == SeatStatus.POTENTIALLY_UNOCCUPIED]
        message = f"I can see {summary}. The most prominent is a {top.label} {self._where(top)}."
        if free:
            message += f" A {free[0].label} may be free."
        return [o.id for o in prominent[:MAX_DESCRIBED]], Guidance(
            message=message,
            details=details,
            confidence=round(sum(o.confidence for o in objs) / len(objs), 2),
            evidence=[f"{len(objs)} detections above threshold", "prominence = box area x confidence"],
            target_ids=[top.id],
        )

    def _guide_find_object(self, objs, rels, target: str | None):
        if not target:
            return [], Guidance(
                message="Which object should I look for?",
                confidence=0.0,
                evidence=["no target object was given"],
            )
        if self.detector_classes and target not in self.detector_classes:
            return [], Guidance(
                message=f"The current detector cannot recognise a {target}.",
                confidence=0.0,
                evidence=[f"'{target}' is not one of the detector's supported classes"],
            )
        matches = sorted((o for o in objs if o.label == target), key=lambda o: o.confidence, reverse=True)
        if not matches:
            return [], Guidance(
                message=f"I can't see a {target} in this view. Move the camera slowly and try again.",
                confidence=0.4,
                evidence=[f"no '{target}' detection above the confidence threshold in this frame"],
            )
        best = matches[0]
        message = f"{target.capitalize()} {self._where(best)}."
        evidence = [f"'{target}' detected with confidence {best.confidence:.2f}"]
        on = next((r for r in rels if r.type == RelationshipType.ON_TOP_OF and r.subject_id == best.id), None)
        if on:
            message = f"{target.capitalize()} {self._where(best)}, possibly on the {on.object_label}."
            evidence.append(f"candidate relationship: on top of {on.object_label} ({on.confidence:.2f})")
        if len(matches) > 1:
            message += f" I see {len(matches)} in total."
        return [o.id for o in matches], Guidance(
            message=message,
            details=[f"{o.label} ({o.confidence:.0%}): {self._where(o)}" for o in matches[:MAX_DESCRIBED]],
            confidence=round(best.confidence, 2),
            evidence=evidence,
            target_ids=[best.id],
        )

    def _guide_find_seat(self, seats: list[SeatAssessment], objs: list[AnalysedObject]):
        by_id = {o.id: o for o in objs}
        if not seats:
            return [], Guidance(
                message="I can't see a chair, sofa or bench in this view.",
                confidence=0.4,
                evidence=["no seat-class detections (chair, couch, bench)"],
            )
        best = seats[0]
        obj = by_id[best.detection_id]
        if best.status == SeatStatus.POTENTIALLY_UNOCCUPIED:
            msg = f"A {obj.label} that may be free is {self._where(obj)}. Check by touch before sitting."
        elif best.status == SeatStatus.UNCERTAIN:
            msg = f"There is a {obj.label} {self._where(obj)}, but I can't tell if it is free."
        else:
            msg = f"The {obj.label}s I can see appear to be occupied." if len(seats) > 1 else \
                f"The {obj.label} {self._where(obj)} appears to be occupied."
        return [s.detection_id for s in seats], Guidance(
            message=msg,
            details=[f"{s.label}: {s.status.value} ({s.confidence:.2f})" for s in seats],
            confidence=best.confidence,
            evidence=best.evidence,
            target_ids=[best.detection_id],
        )

    def _guide_find_exit(self, objs: list[AnalysedObject]):
        exits = sorted((o for o in objs if o.label in EXIT_LABELS),
                       key=lambda o: (o.label != "exit sign", -o.confidence))
        if not exits:
            return [], Guidance(
                message="I can't see an exit sign or a door in this view. Turn slowly and scan again.",
                confidence=0.3,
                evidence=["no 'exit sign' or 'door' candidates were supplied for this frame"],
            )
        best = exits[0]
        noun = "An exit sign" if best.label == "exit sign" else "A door"
        caution = "This is a weak candidate" if best.confidence < 0.35 else "This is a candidate"
        return [o.id for o in exits], Guidance(
            message=f"{noun} may be {self._where(best)}. {caution}; please confirm it.",
            details=[f"{o.label} ({o.confidence:.0%}): {self._where(o)}" for o in exits[:MAX_DESCRIBED]],
            confidence=round(best.confidence, 2),
            evidence=[f"'{best.label}' candidate with confidence {best.confidence:.2f}"],
            target_ids=[best.id],
        )

    def _guide_colour(self, objs: list[AnalysedObject], target: str | None):
        pool = [o for o in objs if o.label == target] if target else []
        if not pool:
            # Prefer objects straight ahead, then larger and more confident boxes.
            pool = sorted(objs, key=lambda o: (abs(o.position.clock_direction - 12),
                                                -(o.position.area_ratio * o.confidence)))
        if not pool:
            return [], Guidance(
                message="No object detected. I will identify the colour at the centre of the view.",
                confidence=0.3,
                evidence=["no detections; colour finder falls back to the centre region"],
            )
        best = pool[0]
        return [best.id], Guidance(
            message=f"Selected the {best.label} {self._where(best)} for colour identification.",
            confidence=round(best.confidence, 2),
            evidence=["selected the matching or most prominent detected object"],
            target_ids=[best.id],
        )
