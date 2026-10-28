// Dart mirrors of the backend's Pydantic schemas (see docs/API.md).
//
// Parsing is tolerant of extra fields so the backend can add data without
// breaking older app versions, but strict about required fields.

double _d(Object? v) => (v as num).toDouble();
double? _dn(Object? v) => v == null ? null : (v as num).toDouble();
List<String> _strings(Object? v) => (v as List? ?? const []).map((e) => e.toString()).toList();

class BoundingBox {
  const BoundingBox(this.x1, this.y1, this.x2, this.y2);

  factory BoundingBox.fromJson(Map<String, dynamic> j) =>
      BoundingBox(_d(j['x1']), _d(j['y1']), _d(j['x2']), _d(j['y2']));

  final double x1, y1, x2, y2;
  double get width => x2 - x1;
  double get height => y2 - y1;

  Map<String, dynamic> toJson() => {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2};
}

class FrameInfo {
  const FrameInfo({required this.width, required this.height, this.frameId});

  factory FrameInfo.fromJson(Map<String, dynamic> j) =>
      FrameInfo(width: j['width'] as int, height: j['height'] as int, frameId: j['frame_id'] as String?);

  final int width, height;
  final String? frameId;
}

class RelativePosition {
  const RelativePosition({
    required this.horizontal,
    required this.vertical,
    required this.clockLabel,
    required this.apparentSize,
    required this.description,
  });

  factory RelativePosition.fromJson(Map<String, dynamic> j) => RelativePosition(
        horizontal: j['horizontal'] as String,
        vertical: j['vertical'] as String,
        clockLabel: j['clock_label'] as String,
        apparentSize: j['apparent_size'] as String,
        description: j['description'] as String,
      );

  final String horizontal, vertical, clockLabel, apparentSize, description;
}

class DistanceEstimate {
  const DistanceEstimate({
    required this.metres,
    required this.lowMetres,
    required this.highMetres,
    required this.confidence,
    required this.method,
  });

  factory DistanceEstimate.fromJson(Map<String, dynamic> j) => DistanceEstimate(
        metres: _d(j['metres']),
        lowMetres: _d(j['low_metres']),
        highMetres: _d(j['high_metres']),
        confidence: _d(j['confidence']),
        method: j['method'] as String,
      );

  final double metres, lowMetres, highMetres, confidence;
  final String method;

  String get label => 'about ${metres.toStringAsFixed(1)} m '
      '(${lowMetres.toStringAsFixed(1)}–${highMetres.toStringAsFixed(1)} m)';
}

class ComponentInfo {
  const ComponentInfo({required this.name, required this.isTrainedModel, required this.description});

  factory ComponentInfo.fromJson(Map<String, dynamic> j) => ComponentInfo(
        name: j['name'] as String,
        isTrainedModel: j['is_trained_model'] as bool,
        description: j['description'] as String? ?? '',
      );

  final String name;
  final bool isTrainedModel;
  final String description;
}

class Detection {
  const Detection({
    required this.id,
    required this.label,
    required this.confidence,
    required this.bbox,
    required this.bboxNormalised,
    this.position,
    this.distance,
  });

  factory Detection.fromJson(Map<String, dynamic> j) => Detection(
        id: j['id'] as int,
        label: j['label'] as String,
        confidence: _d(j['confidence']),
        bbox: BoundingBox.fromJson(j['bbox'] as Map<String, dynamic>),
        bboxNormalised: BoundingBox.fromJson(j['bbox_normalised'] as Map<String, dynamic>),
        position: j['position'] == null ? null : RelativePosition.fromJson(j['position'] as Map<String, dynamic>),
        distance: j['distance'] == null ? null : DistanceEstimate.fromJson(j['distance'] as Map<String, dynamic>),
      );

  final int id;
  final String label;
  final double confidence;
  final BoundingBox bbox, bboxNormalised;
  final RelativePosition? position;
  final DistanceEstimate? distance;
}

class DetectionResult {
  const DetectionResult({
    required this.frame,
    required this.timestamp,
    required this.detections,
    required this.modelName,
    required this.modelFile,
    required this.totalMs,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> j) {
    final model = j['model'] as Map<String, dynamic>;
    return DetectionResult(
      frame: FrameInfo.fromJson(j['frame'] as Map<String, dynamic>),
      timestamp: DateTime.parse(j['timestamp'] as String),
      detections: (j['detections'] as List).map((e) => Detection.fromJson(e as Map<String, dynamic>)).toList(),
      modelName: model['name'] as String,
      modelFile: model['model_file'] as String,
      totalMs: _d((j['processing'] as Map<String, dynamic>)['total_ms']),
    );
  }

  final FrameInfo frame;
  final DateTime timestamp;
  final List<Detection> detections;
  final String modelName, modelFile;
  final double totalMs;
}

class Guidance {
  const Guidance({required this.message, required this.details, required this.confidence, required this.evidence});

  factory Guidance.fromJson(Map<String, dynamic> j) => Guidance(
        message: j['message'] as String,
        details: _strings(j['details']),
        confidence: _d(j['confidence']),
        evidence: _strings(j['evidence']),
      );

  final String message;
  final List<String> details;
  final double confidence;
  final List<String> evidence;
}

enum SeatStatus { likelyOccupied, potentiallyUnoccupied, uncertain }

SeatStatus _seatStatus(String s) => switch (s) {
      'LIKELY_OCCUPIED' => SeatStatus.likelyOccupied,
      'POTENTIALLY_UNOCCUPIED' => SeatStatus.potentiallyUnoccupied,
      _ => SeatStatus.uncertain,
    };

extension SeatStatusText on SeatStatus {
  String get label => switch (this) {
        SeatStatus.likelyOccupied => 'Likely occupied',
        SeatStatus.potentiallyUnoccupied => 'Possibly free',
        SeatStatus.uncertain => 'Uncertain',
      };
}

class SeatAssessment {
  const SeatAssessment({
    required this.detectionId,
    required this.label,
    required this.status,
    required this.confidence,
    required this.evidence,
    required this.position,
  });

  factory SeatAssessment.fromJson(Map<String, dynamic> j) => SeatAssessment(
        detectionId: j['detection_id'] as int,
        label: j['label'] as String,
        status: _seatStatus(j['status'] as String),
        confidence: _d(j['confidence']),
        evidence: _strings(j['evidence']),
        position: RelativePosition.fromJson(j['position'] as Map<String, dynamic>),
      );

  final int detectionId;
  final String label;
  final SeatStatus status;
  final double confidence;
  final List<String> evidence;
  final RelativePosition position;
}

class Relationship {
  const Relationship({
    required this.type,
    required this.subjectLabel,
    required this.objectLabel,
    required this.confidence,
    required this.evidence,
  });

  factory Relationship.fromJson(Map<String, dynamic> j) => Relationship(
        type: j['type'] as String,
        subjectLabel: j['subject_label'] as String,
        objectLabel: j['object_label'] as String,
        confidence: _d(j['confidence']),
        evidence: _strings(j['evidence']),
      );

  final String type, subjectLabel, objectLabel;
  final double confidence;
  final List<String> evidence;

  String get sentence => '$subjectLabel ${type.replaceAll('_', ' ')} $objectLabel';
}

class ContextResult {
  const ContextResult({
    required this.task,
    required this.guidance,
    required this.seats,
    required this.relationships,
    required this.relevantObjectIds,
    required this.reasoner,
    required this.disclaimer,
  });

  factory ContextResult.fromJson(Map<String, dynamic> j) => ContextResult(
        task: j['task'] as String,
        guidance: Guidance.fromJson(j['guidance'] as Map<String, dynamic>),
        seats: (j['seats'] as List).map((e) => SeatAssessment.fromJson(e as Map<String, dynamic>)).toList(),
        relationships:
            (j['relationships'] as List).map((e) => Relationship.fromJson(e as Map<String, dynamic>)).toList(),
        relevantObjectIds: (j['relevant_object_ids'] as List).cast<int>(),
        reasoner: ComponentInfo.fromJson(j['reasoner'] as Map<String, dynamic>),
        disclaimer: j['disclaimer'] as String,
      );

  final String task;
  final Guidance guidance;
  final List<SeatAssessment> seats;
  final List<Relationship> relationships;
  final List<int> relevantObjectIds;
  final ComponentInfo reasoner;
  final String disclaimer;
}

class SignCandidate {
  const SignCandidate({
    required this.kind,
    required this.confidence,
    required this.bboxPx,
    required this.position,
    required this.evidence,
    this.distance,
  });

  factory SignCandidate.fromJson(Map<String, dynamic> j) => SignCandidate(
        kind: j['kind'] as String,
        confidence: _d(j['confidence']),
        bboxPx: BoundingBox.fromJson(j['bbox'] as Map<String, dynamic>),
        position: RelativePosition.fromJson(j['position'] as Map<String, dynamic>),
        evidence: _strings(j['evidence']),
        distance: j['distance'] == null ? null : DistanceEstimate.fromJson(j['distance'] as Map<String, dynamic>),
      );

  final String kind;
  final double confidence;
  final BoundingBox bboxPx;
  final RelativePosition position;
  final List<String> evidence;
  final DistanceEstimate? distance;

  String get kindLabel => kind == 'exit_sign' ? 'Exit sign' : 'Door';
}

class SignsResult {
  const SignsResult({required this.frame, required this.candidates, required this.message, required this.detector});

  factory SignsResult.fromJson(Map<String, dynamic> j) => SignsResult(
        frame: FrameInfo.fromJson(j['frame'] as Map<String, dynamic>),
        candidates: (j['candidates'] as List).map((e) => SignCandidate.fromJson(e as Map<String, dynamic>)).toList(),
        message: j['message'] as String,
        detector: ComponentInfo.fromJson(j['detector'] as Map<String, dynamic>),
      );

  final FrameInfo frame;
  final List<SignCandidate> candidates;
  final String message;
  final ComponentInfo detector;
}

class ScanResult {
  const ScanResult({required this.detection, required this.context, this.signs});

  factory ScanResult.fromJson(Map<String, dynamic> j) => ScanResult(
        detection: DetectionResult.fromJson(j['detection'] as Map<String, dynamic>),
        context: ContextResult.fromJson(j['context'] as Map<String, dynamic>),
        signs: j['signs'] == null ? null : SignsResult.fromJson(j['signs'] as Map<String, dynamic>),
      );

  final DetectionResult detection;
  final ContextResult context;
  final SignsResult? signs;
}

enum IntentStatus { resolved, needsClarification, unsupported }

class IntentResult {
  const IntentResult({
    required this.status,
    required this.intent,
    required this.targetObject,
    required this.targetLabel,
    required this.personal,
    required this.confidence,
    required this.message,
    this.clarificationQuestion,
  });

  factory IntentResult.fromJson(Map<String, dynamic> j) {
    final slots = j['slots'] as Map<String, dynamic>;
    return IntentResult(
      status: switch (j['status'] as String) {
        'RESOLVED' => IntentStatus.resolved,
        'NEEDS_CLARIFICATION' => IntentStatus.needsClarification,
        _ => IntentStatus.unsupported,
      },
      intent: j['intent'] as String?,
      targetObject: slots['target_object'] as String?,
      targetLabel: slots['target_label'] as String?,
      personal: slots['personal'] as bool? ?? false,
      confidence: _d(j['confidence']),
      message: j['message'] as String,
      clarificationQuestion: j['clarification_question'] as String?,
    );
  }

  final IntentStatus status;
  final String? intent;
  final String? targetObject, targetLabel;
  final bool personal;
  final double confidence;
  final String message;
  final String? clarificationQuestion;
}

class ColourSwatch {
  const ColourSwatch({required this.name, required this.family, required this.hex, required this.fraction});

  factory ColourSwatch.fromJson(Map<String, dynamic> j) => ColourSwatch(
        name: j['name'] as String,
        family: j['family'] as String,
        hex: j['hex'] as String,
        fraction: _d(j['fraction']),
      );

  final String name, family, hex;
  final double fraction;

  int get argb => 0xFF000000 | int.parse(hex.substring(1), radix: 16);
}

class ColourResult {
  const ColourResult({
    required this.primary,
    required this.colours,
    required this.confidence,
    required this.message,
    required this.regionSource,
    required this.caveats,
  });

  factory ColourResult.fromJson(Map<String, dynamic> j) => ColourResult(
        primary: ColourSwatch.fromJson(j['primary'] as Map<String, dynamic>),
        colours: (j['colours'] as List).map((e) => ColourSwatch.fromJson(e as Map<String, dynamic>)).toList(),
        confidence: _d(j['confidence']),
        message: j['message'] as String,
        regionSource: j['region_source'] as String,
        caveats: _strings(j['caveats']),
      );

  final ColourSwatch primary;
  final List<ColourSwatch> colours;
  final double confidence;
  final String message, regionSource;
  final List<String> caveats;
}

enum MatchStatus { found, possiblyFound, notFound, noCandidates }

class ItemMatchResult {
  const ItemMatchResult({
    required this.status,
    required this.message,
    required this.bestSimilarity,
    required this.bestPosition,
    required this.candidateCount,
    required this.matcher,
  });

  factory ItemMatchResult.fromJson(Map<String, dynamic> j) {
    final best = j['best'] as Map<String, dynamic>?;
    return ItemMatchResult(
      status: switch (j['status'] as String) {
        'FOUND' => MatchStatus.found,
        'POSSIBLY_FOUND' => MatchStatus.possiblyFound,
        'NOT_FOUND' => MatchStatus.notFound,
        _ => MatchStatus.noCandidates,
      },
      message: j['message'] as String,
      bestSimilarity: _dn(best?['similarity']),
      bestPosition: best == null ? null : RelativePosition.fromJson(best['position'] as Map<String, dynamic>),
      candidateCount: (j['candidates'] as List).length,
      matcher: ComponentInfo.fromJson(j['matcher'] as Map<String, dynamic>),
    );
  }

  final MatchStatus status;
  final String message;
  final double? bestSimilarity;
  final RelativePosition? bestPosition;
  final int candidateCount;
  final ComponentInfo matcher;
}

class ReferenceCheck {
  const ReferenceCheck({required this.accepted, required this.detected, required this.issues, required this.message});

  factory ReferenceCheck.fromJson(Map<String, dynamic> j) => ReferenceCheck(
        accepted: j['accepted'] as bool,
        detected: j['detected'] as bool,
        issues: _strings(j['issues']),
        message: j['message'] as String,
      );

  final bool accepted, detected;
  final List<String> issues;
  final String message;
}

class BackendStatus {
  const BackendStatus({
    required this.status,
    required this.version,
    required this.detectorReady,
    required this.detectorName,
    required this.loadErrors,
  });

  factory BackendStatus.fromJson(Map<String, dynamic> j) => BackendStatus(
        status: j['status'] as String,
        version: j['version'] as String,
        detectorReady: (j['detector'] as Map<String, dynamic>)['ready'] as bool,
        detectorName: ((j['detector'] as Map<String, dynamic>)['component'] as Map<String, dynamic>)['name'] as String,
        loadErrors: (j['load_errors'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, v.toString())),
      );

  final String status, version;
  final bool detectorReady;
  final String detectorName;
  final Map<String, String> loadErrors;
}
