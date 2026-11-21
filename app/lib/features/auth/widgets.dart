import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Shows a date picker for a birth date. Returns null when cancelled.
Future<DateTime?> pickBirthDate(BuildContext context, {DateTime? initial}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? DateTime(now.year - 20, 1, 1),
    firstDate: DateTime(now.year - 100),
    lastDate: now,
    initialDatePickerMode: DatePickerMode.year,
    helpText: AppLocalizations.of(context).authBirthDateLabel,
  );
}

/// `21.11.2001`, the usual way to write a date in Uzbekistan and Russia.
String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.${d.year}';
