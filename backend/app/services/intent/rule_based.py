"""Deterministic rule-based task-intention resolver (baseline, not a trained model).

Scope: *real-world task intentions* ("find my phone", "is there a free seat").
In-app navigation and scan control ("go home", "pause") are handled on the
phone by the Flutter command interpreter and are reported here as UNSUPPORTED
so that the two concerns stay separate.

Algorithm:
  1. Normalise text (lower-case, expand contractions, strip punctuation and
     politeness/filler phrases, collapse whitespace).
  2. Score every intent by summing the weights of matching keyword rules.
  3. Extract an object slot and map it to a detector (COCO) label.
  4. Decide: no score -> UNSUPPORTED; two close high scores or a missing
     required slot -> NEEDS_CLARIFICATION; otherwise RESOLVED.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from app.schemas.common import ComponentInfo
from app.schemas.intent import (
    Intent,
    IntentAlternative,
    IntentRequest,
    IntentResponse,
    IntentSlots,
    ResolutionStatus,
)
from app.services.interfaces import IntentResolver

CONTRACTIONS = {
    "where's": "where is", "what's": "what is", "can't": "can not", "cannot": "can not",
    "i'm": "i am", "there's": "there is", "it's": "it is", "don't": "do not",
    "what're": "what are", "i've": "i have", "whats": "what is", "wheres": "where is",
}
FILLERS = [
    "hey smartsight", "ok smartsight", "okay smartsight", "smartsight", "please", "could you",
    "can you", "would you", "will you", "help me", "i want to", "i would like to", "i'd like to",
    "i need to", "for me", "thank you", "thanks",
]

# Spoken object phrase -> COCO label (None = not a detector class).
OBJECT_VOCAB: dict[str, str | None] = {
    "cell phone": "cell phone", "mobile phone": "cell phone", "smartphone": "cell phone",
    "smart phone": "cell phone", "phone": "cell phone", "mobile": "cell phone", "iphone": "cell phone",
    "handbag": "handbag", "purse": "handbag", "bag": "handbag", "backpack": "backpack",
    "rucksack": "backpack", "school bag": "backpack", "suitcase": "suitcase", "luggage": "suitcase",
    "water bottle": "bottle", "bottle": "bottle", "cup": "cup", "mug": "cup", "glass": "wine glass",
    "laptop": "laptop", "computer": "laptop", "notebook computer": "laptop",
    "tv remote": "remote", "remote control": "remote", "remote": "remote",
    "keyboard": "keyboard", "mouse": "mouse", "book": "book", "umbrella": "umbrella",
    "scissors": "scissors", "clock": "clock", "toothbrush": "toothbrush", "teddy bear": "teddy bear",
    "tv": "tv", "television": "tv", "table": "dining table", "dining table": "dining table",
    "bed": "bed", "toilet": "toilet", "sink": "sink", "fridge": "refrigerator",
    "refrigerator": "refrigerator", "microwave": "microwave", "oven": "oven", "bowl": "bowl",
    "plant": "potted plant", "vase": "vase", "dog": "dog", "cat": "cat", "bicycle": "bicycle",
    "bike": "bicycle", "car": "car", "bus": "bus", "person": "person", "someone": "person",
    "somebody": "person", "people": "person", "traffic light": "traffic light",
    "stop sign": "stop sign", "bench": "bench", "chair": "chair", "sofa": "couch", "couch": "couch",
    # Common personal items that pretrained COCO YOLOv8 cannot detect:
    "keys": None, "key": None, "wallet": None, "glasses": None, "spectacles": None, "sunglasses": None,
    "headphones": None, "earphones": None, "earbuds": None, "watch": None, "cane": None,
    "white cane": None, "medicine": None, "pills": None, "charger": None, "card": None,
    "hat": None, "shoes": None, "jacket": None, "coat": None,
}
SEAT_WORDS = {"chair", "seat", "sofa", "couch", "bench", "stool"}
_VOCAB_BY_LENGTH = sorted(OBJECT_VOCAB, key=len, reverse=True)


@dataclass(frozen=True)
class Rule:
    name: str
    intent: Intent
    pattern: re.Pattern
    weight: float


def _r(name: str, intent: Intent, pattern: str, weight: float) -> Rule:
    return Rule(name, intent, re.compile(pattern), weight)


RULES: list[Rule] = [
    # find exit / door
    _r("exit_word", Intent.FIND_EXIT, r"\b(exit|exits|way out|fire escape)\b", 0.9),
    _r("leave_room", Intent.FIND_EXIT, r"\b(get out|leave (the|this) (room|building)|go outside)\b", 0.7),
    _r("door_word", Intent.FIND_EXIT, r"\b(door|doors|doorway|entrance)\b", 0.7),
    # find seat
    _r("sit_word", Intent.FIND_SEAT, r"\b(sit|sit down|sitting)\b", 0.9),
    _r("seat_word", Intent.FIND_SEAT, r"\b(seat|seats|empty chair|free chair|vacant)\b", 0.8),
    _r("seat_object", Intent.FIND_SEAT, r"\b(chair|chairs|sofa|couch|bench|stool)\b", 0.5),
    # colour
    _r("colour_word", Intent.IDENTIFY_COLOUR, r"\b(colou?r|colou?rs|shade)\b", 1.0),
    _r("colour_names", Intent.IDENTIFY_COLOUR, r"\bis (it|this|that) (red|blue|green|black|white|yellow|grey|gray|brown|pink|purple|orange)\b", 0.8),
    # describe surroundings
    _r("describe", Intent.DESCRIBE_SURROUNDINGS, r"\b(describe|surroundings|around me|look around)\b", 1.0),
    _r("what_see", Intent.DESCRIBE_SURROUNDINGS, r"\bwhat( do| can)?( you)? see\b|\bwhat is (in front of me|here|around)\b", 1.0),
    _r("where_am_i", Intent.DESCRIBE_SURROUNDINGS, r"\b(where am i|what is near me|scan the room|what is ahead)\b", 0.8),
    # signs
    _r("signs", Intent.READ_SIGNS, r"\b(sign|signs|signage)\b", 0.7),
    # find object (needs an object slot)
    _r("find_verb", Intent.FIND_OBJECT, r"\b(find|locate|look for|search for|where is|where are|lost|misplaced|can not find|seen my)\b", 0.6),
]

# Navigation / control phrases handled by the app, not this resolver.
APP_COMMAND = re.compile(
    r"^(go (to )?)?(home|dashboard|settings|back|go back|main menu)$|"
    r"^(open|go to|show) (smart scan|scan|my items|items|colou?r finder|doors( and signs)?|settings|home)$|"
    r"^(start|pause|resume|stop|repeat|continue)( scanning| scan| guidance)?$"
)

CLARIFY_MARGIN = 0.2
EXAMPLES = "find my phone, find the exit, find a place to sit, what colour is this, or describe my surroundings"


def normalise(text: str) -> str:
    t = text.lower().strip()
    t = t.replace("’", "'")
    for k, v in CONTRACTIONS.items():
        t = re.sub(rf"\b{re.escape(k)}(?=\s|$)", v, t)
    t = re.sub(r"[^a-z0-9' ]+", " ", t)
    t = t.replace("'", "")
    for f in FILLERS:
        t = re.sub(rf"\b{re.escape(f)}\b", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def extract_object(text: str) -> tuple[str | None, str | None, bool]:
    """Returns (spoken phrase, COCO label or None, personal?)."""
    for phrase in _VOCAB_BY_LENGTH:
        m = re.search(rf"\b(my |the |a |an |our )?{re.escape(phrase)}\b", text)
        if m:
            personal = (m.group(1) or "").strip() in {"my", "our"}
            return phrase, OBJECT_VOCAB[phrase], personal
    return None, None, False


class RuleBasedIntentResolver(IntentResolver):
    def __init__(self, detector_classes: list[str] | None = None) -> None:
        self.detector_classes = set(detector_classes or [])

    @property
    def info(self) -> ComponentInfo:
        return ComponentInfo(
            name="rule_based_intent",
            version="1.0",
            is_trained_model=False,
            description="Keyword/regex rules with weighted scoring (baseline; not a trained model).",
        )

    def resolve(self, request: IntentRequest) -> IntentResponse:
        text = normalise(request.text)
        slots = IntentSlots()

        if not text:
            return self._response(ResolutionStatus.UNSUPPORTED, None, slots, 0.0, [], [], text,
                                  f"I didn't catch a request. You can say: {EXAMPLES}.")

        if APP_COMMAND.match(text):
            return self._response(
                ResolutionStatus.UNSUPPORTED, None, slots, 0.0, ["app_command"], [], text,
                "That is an app navigation or scan-control command; it is handled on the phone.",
            )

        scores: dict[Intent, float] = {}
        matched: list[str] = []
        for rule in RULES:
            if rule.pattern.search(text):
                scores[rule.intent] = scores.get(rule.intent, 0.0) + rule.weight
                matched.append(rule.name)

        phrase, label, personal = extract_object(text)
        if phrase:
            slots = IntentSlots(
                target_object=phrase, target_label=label, personal=personal,
                target_supported_by_detector=(label is not None and
                                              (not self.detector_classes or label in self.detector_classes)),
            )

        # Contextual adjustments (each is recorded as a matched rule).
        if Intent.FIND_EXIT in scores and Intent.READ_SIGNS in scores:
            # "find the exit sign": the signs assistant serves both; treat as finding the exit.
            scores[Intent.FIND_EXIT] += scores.pop(Intent.READ_SIGNS)
            matched.append("exit_sign_merge")
        object_phrase = phrase is not None and phrase not in SEAT_WORDS
        if Intent.FIND_OBJECT in scores and object_phrase:
            scores[Intent.FIND_OBJECT] += 0.5
            matched.append("object_slot_present")
        elif Intent.FIND_OBJECT in scores and len(scores) > 1:
            # "find the exit" / "find somewhere to sit": the verb supports the other intent.
            verb = scores.pop(Intent.FIND_OBJECT)
            for other in scores:
                scores[other] += verb * 0.3
            matched.append("find_verb_supports_other")
        if phrase and not scores and phrase not in SEAT_WORDS:
            # A bare object name ("my phone?") is most likely a find request.
            scores[Intent.FIND_OBJECT] = 0.5
            matched.append("bare_object_name")
        if Intent.IDENTIFY_COLOUR in scores and Intent.FIND_OBJECT in scores:
            # "what colour is my bag" -> colour of that object, not a search.
            scores[Intent.FIND_OBJECT] -= 0.4
            matched.append("colour_overrides_find")
        if Intent.FIND_SEAT in scores and phrase in SEAT_WORDS and Intent.FIND_OBJECT in scores:
            scores[Intent.FIND_OBJECT] -= 0.4
            matched.append("seat_object_prefers_seat")

        ranked = sorted(((i, s) for i, s in scores.items() if s > 0), key=lambda kv: kv[1], reverse=True)
        alternatives = [IntentAlternative(intent=i, score=round(min(s, 1.0), 2)) for i, s in ranked]

        if not ranked:
            return self._response(ResolutionStatus.UNSUPPORTED, None, slots, 0.0, matched, alternatives, text,
                                  f"Sorry, I didn't understand. You can say: {EXAMPLES}.")

        top, top_score = ranked[0]
        confidence = round(min(top_score, 1.0), 2)

        if len(ranked) > 1 and ranked[1][1] >= 0.5 and top_score - ranked[1][1] < CLARIFY_MARGIN:
            a, b = top.value.replace("_", " "), ranked[1][0].value.replace("_", " ")
            return self._response(
                ResolutionStatus.NEEDS_CLARIFICATION, top, slots, round(confidence * 0.5, 2), matched,
                alternatives, text, f"Did you want to {a} or {b}?", clarification=f"Did you want to {a} or {b}?",
            )

        if top == Intent.FIND_OBJECT:
            if not phrase:
                q = "What would you like me to find?"
                return self._response(ResolutionStatus.NEEDS_CLARIFICATION, top, slots, round(confidence * 0.5, 2),
                                      matched, alternatives, text, q, clarification=q)
            if not slots.target_supported_by_detector:
                return self._response(
                    ResolutionStatus.UNSUPPORTED, top, slots, confidence, matched, alternatives, text,
                    f"I can't recognise {phrase} yet. The current detector knows objects such as "
                    "phones, bags, backpacks, bottles, cups, laptops, books and remotes.",
                )
            what = f"your {phrase}" if personal else f"a {phrase}"
            return self._response(ResolutionStatus.RESOLVED, top, slots, confidence, matched, alternatives,
                                  text, f"Looking for {what}.")

        messages = {
            Intent.FIND_EXIT: "Looking for exit signs and doors.",
            Intent.FIND_SEAT: "Looking for a place to sit.",
            Intent.IDENTIFY_COLOUR: "Point the camera at the object to identify its colour.",
            Intent.DESCRIBE_SURROUNDINGS: "Describing your surroundings.",
            Intent.READ_SIGNS: "Looking for exit signs and doors.",
        }
        return self._response(ResolutionStatus.RESOLVED, top, slots, confidence, matched, alternatives,
                              text, messages[top])

    def _response(self, status, intent, slots, confidence, matched, alternatives, text, message,
                  clarification: str | None = None) -> IntentResponse:
        return IntentResponse(
            status=status, intent=intent, slots=slots, confidence=confidence,
            matched_rules=matched, alternatives=alternatives,
            clarification_question=clarification, message=message,
            normalised_text=text, resolver=self.info,
        )
