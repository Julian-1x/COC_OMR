<?php

namespace App\Services\Auth;

/**
 * RFC 6238 TOTP (Google Authenticator compatible).
 */
class TotpService
{
    public function generateSecret(int $length = 16): string
    {
        $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
        $secret = '';
        for ($i = 0; $i < $length; $i++) {
            $secret .= $alphabet[random_int(0, strlen($alphabet) - 1)];
        }

        return $secret;
    }

    public function provisioningUri(string $email, string $secret): string
    {
        $issuer = rawurlencode((string) config('security.mfa.issuer', 'COC OMR'));
        $label = rawurlencode($issuer.':'.$email);
        $encodedSecret = rawurlencode($secret);

        return "otpauth://totp/{$label}?secret={$encodedSecret}&issuer={$issuer}&digits=6&period=30";
    }

    public function verify(string $secret, string $code, int $window = 1): bool
    {
        $normalized = preg_replace('/\s+/', '', $code) ?? '';
        if (! preg_match('/^\d{6,8}$/', $normalized)) {
            return false;
        }

        $counter = (int) floor(time() / 30);
        for ($offset = -$window; $offset <= $window; $offset++) {
            if (hash_equals($this->codeAt($secret, $counter + $offset), substr($normalized, 0, 6))) {
                return true;
            }
        }

        return false;
    }

    public function codeAt(string $secret, int $counter): string
    {
        $key = $this->base32Decode($secret);
        $binCounter = pack('N*', 0, $counter);
        $hash = hash_hmac('sha1', $binCounter, $key, true);
        $offset = ord($hash[19]) & 0x0F;
        $truncated = unpack('N', substr($hash, $offset, 4))[1] & 0x7FFFFFFF;

        return str_pad((string) ($truncated % 1000000), 6, '0', STR_PAD_LEFT);
    }

    private function base32Decode(string $secret): string
    {
        $secret = strtoupper(preg_replace('/[^A-Z2-7]/', '', $secret) ?? '');
        $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
        $bits = '';
        $length = strlen($secret);
        for ($i = 0; $i < $length; $i++) {
            $value = strpos($alphabet, $secret[$i]);
            if ($value === false) {
                continue;
            }
            $bits .= str_pad(decbin($value), 5, '0', STR_PAD_LEFT);
        }

        $binary = '';
        foreach (str_split($bits, 8) as $chunk) {
            if (strlen($chunk) === 8) {
                $binary .= chr(bindec($chunk));
            }
        }

        return $binary;
    }
}
