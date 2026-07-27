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

    public const ROLE_TEACHER = 'teacher';

    public const ROLE_DEPT_ADMIN = 'dept_admin';

    public const ROLE_SUPER_ADMIN = 'super_admin';

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

    public static function isAccessAdminRole(string $role): bool
    {
        return in_array($role, [
            self::ROLE_SUPER_ADMIN,
            self::ROLE_DEPT_ADMIN,
            // Legacy aliases still accepted until clients catch up.
            'admin',
            'school_admin',
        ], true);
    }

    public static function isSuperAdminRole(string $role): bool
    {
        return in_array($role, [
            self::ROLE_SUPER_ADMIN,
            'admin',
            'school_admin',
        ], true);
    }
}
