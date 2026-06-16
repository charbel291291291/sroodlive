import 'package:flutter/material.dart';
import '../../main.dart';

extension BuildContextLocale on BuildContext {
  bool get isArabic =>
      AppLanguageController.of(this).locale.languageCode == 'ar';
}
