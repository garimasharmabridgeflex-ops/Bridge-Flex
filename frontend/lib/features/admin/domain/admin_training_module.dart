/// Admin-side view of a training module — the same document practitioners
/// receive, plus the answer key.
///
/// Mutable rather than const-with-copyWith: this model exists to back an
/// editing form where a question's option list grows and shrinks as an admin
/// types, and an immutable tree would mean rebuilding it on every keystroke.
class AdminTrainingQuestion {
  AdminTrainingQuestion({
    required this.id,
    this.prompt = '',
    List<String>? options,
    this.correctIndex = 0,
    this.explanation = '',
  }) : options = options ?? ['', ''];

  String id;
  String prompt;
  List<String> options;
  int correctIndex;
  String explanation;

  factory AdminTrainingQuestion.fromJson(Map<String, dynamic> json) => AdminTrainingQuestion(
        id: json['id'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        options: (json['options'] as List?)?.cast<String>().toList() ?? ['', ''],
        correctIndex: (json['correctIndex'] as num?)?.toInt() ?? 0,
        explanation: json['explanation'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'options': options,
        'correctIndex': correctIndex,
        'explanation': explanation,
      };
}

class AdminTrainingSection {
  AdminTrainingSection({this.heading = '', List<String>? body}) : body = body ?? [''];

  String heading;
  List<String> body;

  factory AdminTrainingSection.fromJson(Map<String, dynamic> json) => AdminTrainingSection(
        heading: json['heading'] as String? ?? '',
        body: (json['body'] as List?)?.cast<String>().toList() ?? [''],
      );

  Map<String, dynamic> toJson() => {'heading': heading, 'body': body};
}

class AdminTrainingModule {
  AdminTrainingModule({
    required this.moduleId,
    this.order = 0,
    this.title = '',
    this.purpose = '',
    List<String>? contentOutline,
    List<AdminTrainingSection>? sections,
    this.videoStoragePath = '',
    this.videoUrl = '',
    this.videoDurationSeconds = 0,
    List<AdminTrainingQuestion>? questions,
    this.passMark = 0,
    this.published = false,
  })  : contentOutline = contentOutline ?? [],
        sections = sections ?? [],
        questions = questions ?? [];

  String moduleId;
  int order;
  String title;
  String purpose;
  List<String> contentOutline;
  List<AdminTrainingSection> sections;
  String videoStoragePath;
  String videoUrl;
  int videoDurationSeconds;
  List<AdminTrainingQuestion> questions;
  int passMark;
  bool published;

  factory AdminTrainingModule.fromJson(Map<String, dynamic> json) => AdminTrainingModule(
        moduleId: json['moduleId'] as String? ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        purpose: json['purpose'] as String? ?? '',
        contentOutline: (json['contentOutline'] as List?)?.cast<String>().toList() ?? [],
        sections: (json['sections'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(AdminTrainingSection.fromJson)
                .toList() ??
            [],
        videoStoragePath: json['videoStoragePath'] as String? ?? '',
        videoUrl: json['videoUrl'] as String? ?? '',
        videoDurationSeconds: (json['videoDurationSeconds'] as num?)?.toInt() ?? 0,
        questions: (json['questions'] as List?)
                ?.cast<Map<String, dynamic>>()
                .map(AdminTrainingQuestion.fromJson)
                .toList() ??
            [],
        passMark: (json['passMark'] as num?)?.toInt() ?? 0,
        published: json['published'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'moduleId': moduleId,
        'order': order,
        'title': title,
        'purpose': purpose,
        'contentOutline': contentOutline.where((e) => e.trim().isNotEmpty).toList(),
        'sections': sections
            .where((s) => s.heading.trim().isNotEmpty || s.body.any((b) => b.trim().isNotEmpty))
            .map((s) => {
                  'heading': s.heading,
                  'body': s.body.where((b) => b.trim().isNotEmpty).toList(),
                })
            .toList(),
        'videoStoragePath': videoStoragePath,
        'videoUrl': videoUrl,
        'videoDurationSeconds': videoDurationSeconds,
        'questions': questions.map((q) => q.toJson()).toList(),
        'passMark': passMark,
        'published': published,
      };
}
