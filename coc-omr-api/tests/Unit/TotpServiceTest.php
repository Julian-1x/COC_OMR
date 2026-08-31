<?php

namespace Tests\Unit;

use App\Services\Auth\TotpService;
use PHPUnit\Framework\TestCase;

class TotpServiceTest extends TestCase
{
    public function test_verify_accepts_current_code_for_known_secret(): void
    {
        $service = new TotpService;
        $secret = 'JBSWY3DPEHPK3PXP';
        $code = $service->codeAt($secret, (int) floor(time() / 30));

        $this->assertTrue($service->verify($secret, $code));
    }

    public function test_verify_rejects_wrong_code(): void
    {
        $service = new TotpService;

        $this->assertFalse($service->verify('JBSWY3DPEHPK3PXP', '000000'));
    }
}
