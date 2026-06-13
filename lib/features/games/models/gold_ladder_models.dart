class GoldLadderQuestion {
  const GoldLadderQuestion({
    required this.id,
    required this.text,
    required this.textAr,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.optionAAr,
    required this.optionBAr,
    required this.optionCAr,
    required this.optionDAr,
    required this.difficulty,
  });

  final String id;
  final String text;
  final String textAr;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String optionAAr;
  final String optionBAr;
  final String optionCAr;
  final String optionDAr;
  final String difficulty;

  factory GoldLadderQuestion.fromJson(Map<String, dynamic> j) =>
      GoldLadderQuestion(
        id: j['id']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        textAr: j['text_ar']?.toString() ?? '',
        optionA: j['option_a']?.toString() ?? '',
        optionB: j['option_b']?.toString() ?? '',
        optionC: j['option_c']?.toString() ?? '',
        optionD: j['option_d']?.toString() ?? '',
        optionAAr: j['option_a_ar']?.toString() ?? '',
        optionBAr: j['option_b_ar']?.toString() ?? '',
        optionCAr: j['option_c_ar']?.toString() ?? '',
        optionDAr: j['option_d_ar']?.toString() ?? '',
        difficulty: j['difficulty']?.toString() ?? 'medium',
      );

  Map<String, dynamic> toBridgeJson() => {
        'id': id,
        'text': text,
        'text_ar': textAr,
        'option_a': optionA,
        'option_b': optionB,
        'option_c': optionC,
        'option_d': optionD,
        'option_a_ar': optionAAr,
        'option_b_ar': optionBAr,
        'option_c_ar': optionCAr,
        'option_d_ar': optionDAr,
        'difficulty': difficulty,
      };
}

class GoldLadderLadderStep {
  const GoldLadderLadderStep({
    required this.q,
    required this.multiplier,
    required this.prize,
    required this.safe,
  });

  final int q;
  final double multiplier;
  final int prize;
  final bool safe;

  factory GoldLadderLadderStep.fromJson(Map<String, dynamic> j) =>
      GoldLadderLadderStep(
        q: (j['q'] as num).toInt(),
        multiplier: (j['multiplier'] as num).toDouble(),
        prize: (j['prize'] as num).toInt(),
        safe: j['safe'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'q': q, 'multiplier': multiplier, 'prize': prize, 'safe': safe};
}

class GoldLadderRunStarted {
  const GoldLadderRunStarted({
    required this.runId,
    required this.entryFee,
    required this.balance,
    required this.questionNumber,
    required this.currentPrize,
    required this.question,
    required this.ladder,
    required this.powersRemaining,
  });

  final String runId;
  final int entryFee;
  final int balance;
  final int questionNumber;
  final int currentPrize;
  final GoldLadderQuestion question;
  final List<GoldLadderLadderStep> ladder;
  final Map<String, int> powersRemaining;

  factory GoldLadderRunStarted.fromJson(Map<String, dynamic> j) {
    final ladderList = (j['ladder'] as List<dynamic>? ?? [])
        .map((s) => GoldLadderLadderStep.fromJson(s as Map<String, dynamic>))
        .toList();
    final powers = (j['powers_remaining'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    return GoldLadderRunStarted(
      runId: j['run_id']?.toString() ?? '',
      entryFee: (j['entry_fee'] as num).toInt(),
      balance: (j['balance'] as num).toInt(),
      questionNumber: (j['question_number'] as num? ?? 1).toInt(),
      currentPrize: (j['current_prize'] as num? ?? 0).toInt(),
      question: GoldLadderQuestion.fromJson(
          j['question'] as Map<String, dynamic>),
      ladder: ladderList,
      powersRemaining: powers,
    );
  }

  Map<String, dynamic> toBridgeJson() => {
        'runId': runId,
        'entryFee': entryFee,
        'balance': balance,
        'questionNumber': questionNumber,
        'currentPrize': currentPrize,
        'question': question.toBridgeJson(),
        'ladder': ladder.map((s) => s.toJson()).toList(),
        'powersRemaining': powersRemaining,
      };
}

class GoldLadderAnswerResult {
  const GoldLadderAnswerResult({
    required this.correct,
    required this.correctOption,
    required this.explanation,
    required this.questionNumber,
    required this.isEliminated,
    required this.isCompleted,
    required this.secondChanceTriggered,
    this.cashoutAmount,
    this.newBalance,
    this.currentPrize,
    this.nextQuestion,
    this.nextQuestionNumber,
  });

  final bool correct;
  final String? correctOption;
  final String? explanation;
  final int questionNumber;
  final bool isEliminated;
  final bool isCompleted;
  final bool secondChanceTriggered;
  final int? cashoutAmount;
  final int? newBalance;
  final int? currentPrize;
  final GoldLadderQuestion? nextQuestion;
  final int? nextQuestionNumber;

  factory GoldLadderAnswerResult.fromJson(Map<String, dynamic> j) {
    GoldLadderQuestion? nq;
    if (j['next_question'] != null) {
      nq = GoldLadderQuestion.fromJson(
          j['next_question'] as Map<String, dynamic>);
    }
    return GoldLadderAnswerResult(
      correct: j['correct'] == true,
      correctOption: j['correct_option']?.toString(),
      explanation: j['explanation']?.toString(),
      questionNumber: (j['question_number'] as num? ?? 0).toInt(),
      isEliminated: j['is_eliminated'] == true,
      isCompleted: j['is_completed'] == true,
      secondChanceTriggered: j['second_chance_triggered'] == true,
      cashoutAmount: j['cashout_amount'] != null
          ? (j['cashout_amount'] as num).toInt()
          : null,
      newBalance: j['new_balance'] != null
          ? (j['new_balance'] as num).toInt()
          : null,
      currentPrize: j['current_prize'] != null
          ? (j['current_prize'] as num).toInt()
          : null,
      nextQuestion: nq,
      nextQuestionNumber: j['next_question_number'] != null
          ? (j['next_question_number'] as num).toInt()
          : null,
    );
  }

  Map<String, dynamic> toBridgeJson() => {
        'correct': correct,
        'correctOption': correctOption,
        'explanation': explanation,
        'questionNumber': questionNumber,
        'isEliminated': isEliminated,
        'isCompleted': isCompleted,
        'secondChanceTriggered': secondChanceTriggered,
        'cashoutAmount': cashoutAmount,
        'newBalance': newBalance,
        'currentPrize': currentPrize,
        'nextQuestion': nextQuestion?.toBridgeJson(),
        'nextQuestionNumber': nextQuestionNumber,
      };
}

class GoldLadderPowerResult {
  const GoldLadderPowerResult({
    required this.powerType,
    this.eliminatedOptions,
    this.distribution,
    this.confirmed,
  });

  final String powerType;
  final List<String>? eliminatedOptions;
  final Map<String, int>? distribution;
  final bool? confirmed;

  factory GoldLadderPowerResult.fromJson(Map<String, dynamic> j) {
    List<String>? elim;
    if (j['eliminated_options'] != null) {
      elim = (j['eliminated_options'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
    }
    Map<String, int>? dist;
    if (j['distribution'] != null) {
      dist = (j['distribution'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    }
    return GoldLadderPowerResult(
      powerType: j['power_type']?.toString() ?? '',
      eliminatedOptions: elim,
      distribution: dist,
      confirmed: j['confirmed'] as bool?,
    );
  }

  Map<String, dynamic> toBridgeJson() => {
        'powerType': powerType,
        'eliminatedOptions': eliminatedOptions,
        'distribution': distribution,
        'confirmed': confirmed,
      };
}

class GoldLadderWinner {
  const GoldLadderWinner({
    required this.displayName,
    required this.entryFee,
    required this.cashoutAmount,
    required this.multiplier,
    required this.status,
  });

  final String displayName;
  final int entryFee;
  final int cashoutAmount;
  final double multiplier;
  final String status;

  factory GoldLadderWinner.fromJson(Map<String, dynamic> j) =>
      GoldLadderWinner(
        displayName: j['display_name']?.toString() ?? 'Player',
        entryFee: (j['entry_fee'] as num? ?? 0).toInt(),
        cashoutAmount: (j['cashout_amount'] as num? ?? 0).toInt(),
        multiplier: (j['multiplier'] as num? ?? 0).toDouble(),
        status: j['status']?.toString() ?? 'completed',
      );

  Map<String, dynamic> toBridgeJson() => {
        'displayName': displayName,
        'entryFee': entryFee,
        'cashoutAmount': cashoutAmount,
        'multiplier': multiplier,
        'status': status,
      };
}
