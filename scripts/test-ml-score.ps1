# Test E2E : inscription + score → vérifie engine=ml
$ErrorActionPreference = "Stop"
$api = "http://127.0.0.1:3001"
$phone = "+22670" + (Get-Random -Minimum 100000 -Maximum 999999)

function PostJson($url, $body) {
  Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body ($body | ConvertTo-Json)
}

Write-Host "1. OTP request ($phone)"
$otp = PostJson "$api/auth/otp/request" @{ phone = $phone; purpose = "register" }
$code = $otp.devCode
Write-Host "   devCode=$code"

Write-Host "2. OTP verify"
$verify = PostJson "$api/auth/otp/verify" @{ phone = $phone; code = $code; purpose = "register" }

Write-Host "3. Register"
$reg = PostJson "$api/auth/register" @{
  phone = $phone; pin = "8362"; displayName = "Test ML"; language = "fr"; otpToken = $verify.otpToken
}
$token = $reg.accessToken
if (-not $token) { $token = $reg.tokens.accessToken }
Write-Host "   token OK"

$h = @{ Authorization = "Bearer $token" }

Write-Host "4. Recalcul score"
$score = Invoke-RestMethod -Method Post -Uri "$api/score/recalculate" -Headers $h -ContentType "application/json" -Body "{}"
Write-Host ("   score={0} engine={1} modelVersion={2} eligible={3}" -f $score.score, $score.engine, $score.modelVersion, $score.eligible)

if ($score.engine -eq "ml") {
  Write-Host "SUCCESS: scoring ML actif" -ForegroundColor Green
} else {
  Write-Host "FAIL: engine=$($score.engine) (fallback heuristique)" -ForegroundColor Red
  exit 1
}
