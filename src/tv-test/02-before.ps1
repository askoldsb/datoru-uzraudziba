# 02-before.ps1 - saglaba TeamViewer stavokli PIRMS parinstalesanas (C:\Temp\tv-test\before.json).
. "$PSScriptRoot\00-common.ps1"

$s = New-PSSession -ComputerName $PC -Credential $cred
try { $local = Get-TvState -Session $s } finally { Remove-PSSession $s }

$api = @(Get-TvApiDevice -Token (Get-TvToken) -Name $PC)

[PSCustomObject]@{ Local = $local; Api = $api } |
    ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $OutDir "before-$PC.json") -Encoding UTF8

Write-Host "`n=== Lokalais stavoklis ($PC) ===" -ForegroundColor Cyan
$local | Format-List
Write-Host "=== TeamViewer konsole (API) ===" -ForegroundColor Cyan
if ($api.Count -gt 0) { $api | Format-Table -AutoSize } else { Write-Host "(API nedeva datus - pierakstiet konsoles datus ar roku: alias, grupa, ID, online)" }
Write-Host "Saglabats: $(Join-Path $OutDir "before-$PC.json")"
Write-Host "Papildus: no admin datora pameginiet savienoties ar $PC caur TeamViewer un parbaudiet, ka nav jaievada parole."
