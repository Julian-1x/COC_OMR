<?php

namespace Tests\Unit;

use App\Support\PersonName;
use PHPUnit\Framework\TestCase;

class PersonNameTest extends TestCase
{
    public function test_title_cases_plain_names(): void
    {
        $this->assertSame('Maria Santos', PersonName::normalize('maria santos'));
        $this->assertSame(
            'Alexander Julian Balaba',
            PersonName::normalize('  ALEXANDER   JULIAN   BALABA  '),
        );
    }

    public function test_reorders_last_first_to_first_last(): void
    {
        $this->assertSame('Maria Santos', PersonName::normalize('Santos, Maria'));
        $this->assertSame(
            'Alexander Julian Balaba',
            PersonName::normalize('Balaba, Alexander Julian'),
        );
    }

    public function test_lowercases_name_particles(): void
    {
        $this->assertSame('Maria de la Cruz', PersonName::normalize('MARIA DE LA CRUZ'));
    }
}
