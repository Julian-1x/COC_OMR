/// Normalizes teacher and student names to "First Last" title case.
class PersonName {
  PersonName._();

  static const Set<String> _lowerParticles = {
    'de',
    'del',
    'la',
    'las',
    'los',
    'van',
    'von',
    'y',
    'e',
    'da',
    'dos',
    'das',
    'san',
    'santa',
    'sta',
    'sto',
  };

  static String normalize(String input) {
    var value = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) {
      return '';
    }

    if (value.contains(',')) {
      final parts =
          value.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
      if (parts.length >= 2) {
        final family = parts.removeAt(0);
        final given = parts.join(' ');
        value = '$given $family'.trim().replaceAll(RegExp(r'\s+'), ' ');
      }
    }

    final words = value.split(' ');
    final normalized = <String>[];
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      if (word.isEmpty) {
        continue;
      }

      final lower = word.toLowerCase();
      if (index > 0 && _lowerParticles.contains(lower)) {
        normalized.add(lower);
        continue;
      }

      if (index > 0 &&
          lower == 'de' &&
          index + 1 < words.length &&
          {'la', 'los', 'las'}.contains(words[index + 1].toLowerCase())) {
        normalized.add('de');
        normalized.add(words[index + 1].toLowerCase());
        index += 1;
        continue;
      }

      normalized.add(_titleWord(word));
    }

    return normalized.join(' ');
  }

  static String _titleWord(String word) {
    if (word.isEmpty) {
      return word;
    }

    if (word.contains('-')) {
      return word.split('-').map(_titleWord).join('-');
    }

    final apostrophe = word.indexOf("'");
    if (apostrophe >= 0 && apostrophe < word.length - 1) {
      return '${word.substring(0, apostrophe + 1)}'
          '${_titleWord(word.substring(apostrophe + 1))}';
    }

    final lower = word.toLowerCase();
    if (lower.startsWith('mc') && lower.length > 2) {
      return 'Mc${_titleWord(word.substring(2))}';
    }

    if (RegExp(r'^(jr|sr|ii|iii|iv)\.?$', caseSensitive: false).hasMatch(lower)) {
      final suffix = lower.endsWith('.') ? '.' : '';
      return '${lower.replaceAll('.', '').toUpperCase()}$suffix';
    }

    return lower[0].toUpperCase() + lower.substring(1);
  }
}
