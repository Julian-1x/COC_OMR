<?php

return [
    /*
    | Soft-archived sections/students are permanently deleted after this many
    | months (from archived_at). Teachers can restore before the deadline.
    */
    'archive_retention_months' => max(1, (int) env('ARCHIVE_RETENTION_MONTHS', 4)),
];
