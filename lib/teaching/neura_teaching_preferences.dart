/// Explicit delivery settings, not inferred traits or companion-memory notes.
enum NeuraAnswerDetail { brief, balanced, detailed }

extension NeuraAnswerDetailLabel on NeuraAnswerDetail {
  String get label => switch (this) {
        NeuraAnswerDetail.brief => 'Brief',
        NeuraAnswerDetail.balanced => 'Balanced',
        NeuraAnswerDetail.detailed => 'Detailed',
      };

  double get depth => switch (this) {
        NeuraAnswerDetail.brief => 0.2,
        NeuraAnswerDetail.balanced => 0.5,
        NeuraAnswerDetail.detailed => 0.8,
      };
}

enum NeuraPlanSize { one, three }

extension NeuraPlanSizeLabel on NeuraPlanSize {
  int get count => this == NeuraPlanSize.one ? 1 : 3;
  String get label => this == NeuraPlanSize.one ? 'One step' : 'Three steps';
}

class NeuraTeachingPreferences {
  const NeuraTeachingPreferences({this.answerDetail, this.planSize});

  final NeuraAnswerDetail? answerDetail;
  final NeuraPlanSize? planSize;
  bool get isEmpty => answerDetail == null && planSize == null;

  NeuraTeachingPreferences withAnswerDetail(NeuraAnswerDetail? value) =>
      NeuraTeachingPreferences(answerDetail: value, planSize: planSize);
  NeuraTeachingPreferences withPlanSize(NeuraPlanSize? value) =>
      NeuraTeachingPreferences(answerDetail: answerDetail, planSize: value);

  Map<String, dynamic> toJson() => {
        'version': 1,
        'answer_detail': answerDetail?.name,
        'plan_size': planSize?.name,
      };

  factory NeuraTeachingPreferences.fromJson(Map<String, dynamic> json) {
    if (json.length != 3 ||
        json['version'] != 1 ||
        !json.containsKey('answer_detail') ||
        !json.containsKey('plan_size')) {
      throw const FormatException('Invalid teaching settings.');
    }
    T? value<T extends Enum>(String key, List<T> values) {
      final name = json[key];
      if (name == null) return null;
      for (final value in values) {
        if (name == value.name) return value;
      }
      throw const FormatException('Invalid teaching setting.');
    }

    return NeuraTeachingPreferences(
      answerDetail: value('answer_detail', NeuraAnswerDetail.values),
      planSize: value('plan_size', NeuraPlanSize.values),
    );
  }
}
