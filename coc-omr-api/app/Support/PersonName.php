<?php

namespace App\Support;

/**
 * Normalize person names to "First Last" title case for teachers and students.
 */
final class PersonName
{
    /** @var list<string> */
    private const LOWER_PARTICLES = [
        'de', 'del', 'la', 'las', 'los', 'van', 'von', 'y', 'e', 'da', 'dos', 'das',
        'san', 'santa', 'sta', 'sto',
    ];

    public static function normalize(string $input): string
    {
        $value = preg_replace('/\s+/u', ' ', trim($input)) ?? '';
        if ($value === '') {
            return '';
        }

        if (str_contains($value, ',')) {
            $parts = array_values(array_filter(array_map('trim', explode(',', $value))));
            if (count($parts) >= 2) {
                $family = array_shift($parts);
                $given = implode(' ', $parts);
                $value = trim($given.' '.$family);
                $value = preg_replace('/\s+/u', ' ', $value) ?? $value;
            }
        }

        $words = preg_split('/\s+/u', $value) ?: [];
        $normalized = [];
        $count = count($words);

        for ($index = 0; $index < $count; $index++) {
            $word = $words[$index];
            if ($word === '') {
                continue;
            }

            $lower = mb_strtolower($word, 'UTF-8');

            if ($index > 0 && in_array($lower, self::LOWER_PARTICLES, true)) {
                $normalized[] = $lower;

                continue;
            }

            if ($index > 0 && $lower === 'de' && $index + 1 < $count) {
                $nextLower = mb_strtolower((string) $words[$index + 1], 'UTF-8');
                if (in_array($nextLower, ['la', 'los', 'las'], true)) {
                    $normalized[] = 'de';
                    $normalized[] = $nextLower;
                    $index++;

                    continue;
                }
            }

            $normalized[] = self::titleWord($word);
        }

        return implode(' ', $normalized);
    }

    private static function titleWord(string $word): string
    {
        if (str_contains($word, '-')) {
            $parts = explode('-', $word);

            return implode('-', array_map(static fn (string $part) => self::titleWord($part), $parts));
        }

        $apostrophe = mb_strpos($word, "'");
        if ($apostrophe !== false && $apostrophe < mb_strlen($word, 'UTF-8') - 1) {
            $prefix = mb_substr($word, 0, $apostrophe + 1, 'UTF-8');
            $suffix = mb_substr($word, $apostrophe + 1, null, 'UTF-8');

            return $prefix.self::titleWord($suffix);
        }

        $lower = mb_strtolower($word, 'UTF-8');
        if (str_starts_with($lower, 'mc') && mb_strlen($lower, 'UTF-8') > 2) {
            return 'Mc'.self::titleWord(mb_substr($word, 2, null, 'UTF-8'));
        }

        if (preg_match('/^(jr|sr|ii|iii|iv)\.?$/iu', $lower)) {
            $suffix = str_ends_with($lower, '.') ? '.' : '';

            return strtoupper(rtrim($lower, '.')).$suffix;
        }

        return mb_strtoupper(mb_substr($lower, 0, 1, 'UTF-8'), 'UTF-8')
            .mb_substr($lower, 1, null, 'UTF-8');
    }
}
