<?php

namespace App\Support;

/**
 * Canonical school identity for COC OMR (single-tenant deployment).
 */
final class CocSchool
{
    public const NAME = 'Cagayan de Oro College';

    public const ACCESS_PENDING = 'pending';

    public const ACCESS_APPROVED = 'approved';

    public const ACCESS_REVOKED = 'revoked';

    public static function isValidAccessStatus(string $status): bool
    {
        return in_array($status, [
            self::ACCESS_PENDING,
            self::ACCESS_APPROVED,
            self::ACCESS_REVOKED,
        ], true);
    }
}
