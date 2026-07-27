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

    /** @var list<string> */
    public const DEPARTMENTS = [
        'COE',
        'SCCJ',
        'CMA',
        'CIT',
        'CEA',
        'CAHS',
    ];

    public static function isValidAccessStatus(string $status): bool
    {
        return in_array($status, [
            self::ACCESS_PENDING,
            self::ACCESS_APPROVED,
            self::ACCESS_REVOKED,
        ], true);
    }

    public static function isValidDepartment(string $department): bool
    {
        return in_array(strtoupper(trim($department)), self::DEPARTMENTS, true);
    }

    public static function normalizeDepartment(string $department): string
    {
        return strtoupper(trim($department));
    }
}
