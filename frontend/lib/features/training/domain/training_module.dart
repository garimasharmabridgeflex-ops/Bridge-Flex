/// Training module as returned by the backend's listTrainingModules —
/// backend/services/core/training.go.
///
/// Note what is NOT here: a question's correct answer. The backend strips it
/// before serialising, so the answer key never reaches the device. Grading
/// happens server-side in submitTrainingQuiz.
enum TrainingStatus { notStarted, inProgress, completed }

TrainingStatus trainingStatusFromString(String? value) => switch (value) {
      'in_progress' => TrainingStatus.inProgress,
      'completed' => TrainingStatus.completed,
      _ => TrainingStatus.notStarted,
    };

class TrainingQuestion {
  const TrainingQuestion({
    required this.id,
    required this.prompt,
    required this.options,
  });

  final String id;
  final String prompt;
  final List<String> options;

  factory TrainingQuestion.fromJson(Map<String, dynamic> json) => TrainingQuestion(
        id: json['id'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        options: (json['options'] as List?)?.cast<String>() ?? const [],
      );
}

class TrainingModule {
  const TrainingModule({
    required this.moduleId,
    required this.order,
    required this.title,
    required this.purpose,
    required this.contentOutline,
    required this.videoStoragePath,
    required this.videoUrl,
    required this.videoDurationSeconds,
    required this.questions,
    required this.passMark,
    required this.status,
    required this.videoWatched,
    required this.attempts,
    required this.bestScore,
    required this.lastScore,
    required this.totalQuestions,
    required this.completedAt,
  });

  final String moduleId;
  final int order;
  final String title;
  final String purpose;
  final List<String> contentOutline;

  /// Path inside the Firebase Storage bucket, resolved with getDownloadURL().
  /// Preferred over [videoUrl] so the video can be replaced in place without
  /// editing the module document.
  final String videoStoragePath;
  final String videoUrl;
  final int videoDurationSeconds;

  final List<TrainingQuestion> questions;
  final int passMark;

  final TrainingStatus status;
  final bool videoWatched;
  final int attempts;
  final int bestScore;
  final int lastScore;
  final int totalQuestions;
  final DateTime? completedAt;

  bool get isCompleted => status == TrainingStatus.completed;
  bool get hasQuiz => questions.isNotEmpty;

  factory TrainingModule.fromJson(Map<String, dynamic> json) => TrainingModule(
        moduleId: json['moduleId'] as String? ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        purpose: json['purpose'] as String? ?? '',
        contentOutline: (json['contentOutline'] as List?)?.cast<String>() ?? const [],
        videoStoragePath: json['videoStoragePath'] as String? ?? '',
        videoUrl: json['videoUrl'] as String? ?? '',
        videoDurationSeconds: (json['videoDurationSeconds'] as num?)?.toInt() ?? 0,
        questions: (json['questions'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(TrainingQuestion.fromJson)
                .toList() ??
            const [],
        passMark: (json['passMark'] as num?)?.toInt() ?? 0,
        status: trainingStatusFromString(json['status'] as String?),
        videoWatched: json['videoWatched'] as bool? ?? false,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        bestScore: (json['bestScore'] as num?)?.toInt() ?? 0,
        lastScore: (json['lastScore'] as num?)?.toInt() ?? 0,
        totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 0,
        completedAt: json['completedAt'] != null
            ? DateTime.tryParse(json['completedAt'] as String)?.toLocal()
            : null,
      );
}

/// Everything the training tab needs in one response.
class TrainingOverview {
  const TrainingOverview({
    required this.modules,
    required this.completedCount,
    required this.totalCount,
  });

  final List<TrainingModule> modules;
  final int completedCount;
  final int totalCount;

  bool get allComplete => totalCount > 0 && completedCount >= totalCount;

  factory TrainingOverview.fromJson(Map<String, dynamic> json) => TrainingOverview(
        modules: (json['modules'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(TrainingModule.fromJson)
                .toList() ??
            const [],
        completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
        totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      );
}

/// One question's outcome from a submitted attempt. [correctIndex] and
/// [explanation] are only populated once the module has been passed — the
/// backend withholds them on a failed attempt so repeated failures can't be
/// used to reveal the answers.
class QuizQuestionResult {
  const QuizQuestionResult({
    required this.questionId,
    required this.correct,
    required this.correctIndex,
    required this.explanation,
  });

  final String questionId;
  final bool correct;
  final int? correctIndex;
  final String explanation;

  factory QuizQuestionResult.fromJson(Map<String, dynamic> json) => QuizQuestionResult(
        questionId: json['questionId'] as String? ?? '',
        correct: json['correct'] as bool? ?? false,
        correctIndex: (json['correctIndex'] as num?)?.toInt(),
        explanation: json['explanation'] as String? ?? '',
      );
}

class QuizResult {
  const QuizResult({
    required this.moduleId,
    required this.score,
    required this.total,
    required this.passMark,
    required this.passed,
    required this.attempts,
    required this.bestScore,
    required this.results,
  });

  final String moduleId;
  final int score;
  final int total;
  final int passMark;
  final bool passed;
  final int attempts;
  final int bestScore;
  final List<QuizQuestionResult> results;

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
        moduleId: json['moduleId'] as String? ?? '',
        score: (json['score'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
        passMark: (json['passMark'] as num?)?.toInt() ?? 0,
        passed: json['passed'] as bool? ?? false,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        bestScore: (json['bestScore'] as num?)?.toInt() ?? 0,
        results: (json['results'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(QuizQuestionResult.fromJson)
                .toList() ??
            const [],
      );
}
