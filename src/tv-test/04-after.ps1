# 04-after.ps1 - nolasa stavokli PEC parinstalesanas un salidzina ar before.json.
. "$PSScriptRoot\00-common.ps1"

$beforeFile = Join-Path $OutDir "before-$PC.json"
if (-not (Test-Path $beforeFile)) { throw "Nav before.json - vispirms palaidiet 02-before.ps1" }
$before = Get-Content $beforeFile -Raw -Encoding UTF8 | ConvertFrom-Json

$s = New-PSSession -ComputerName $PC -Credential $cred
try { $after = Get-TvState -Session $s } finally { Remove-PSSession $s }

# Dodam laiku, lai TeamViewer paspej pieslegties (lidz 3 min)
$token = Get-TvToken
$api = @()
$deadline = (Get-Date).AddMinutes(3)
do {
    $api = @(Get-TvApiDevice -Token $token -Name $PC)
    if (($api.Count -ge 1) -and ($api[0].online_state -eq "Online")) { break }
    if (@($before.Api).Count -eq 0) { break }   # API nedeva datus jau pirms - negaidam
    Write-Host "  gaidu, kamer ierice kluust Online konsole..."
    Start-Sleep -Seconds 15
} while ((Get-Date) -lt $deadline)

[PSCustomObject]@{ Local = $after; Api = $api } |
    ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $OutDir "after-$PC.json") -Encoding UTF8

$checks = New-Object System.Collections.ArrayList
function Add-Check { param($Name, [bool]$Ok, $Detail) [void]$checks.Add([PSCustomObject]@{ Parbaude = $Name; Rezultats = $(if ($Ok) { "OK" } else { "KLUDA" }); Detalas = $Detail }) }

$b = $before.Local
Add-Check "TeamViewer ID nemainijies" ($b.ClientID -eq $after.ClientID) "$($b.ClientID) -> $($after.ClientID)"
Add-Check "Serviss darbojas"         ($after.Service -eq "Running")      "$($after.Service)"
Add-Check "Serviss startejas automatiski" ($after.StartType -eq "Automatic") "$($after.StartType)"
Add-Check "Autostart_GUI = 1"        ($after.AutostartGUI -eq "1")       "$($after.AutostartGUI)"

$bApi = @($before.Api)
if ($bApi.Count -gt 0) {
    Add-Check "Konsole: viens ieraksts (nav dublikata)" ($api.Count -eq 1) "ieraksti pec atjauninasanas: $($api.Count)"
    if ($api.Count -ge 1) {
        Add-Check "Konsole: device_id nemainijies"        ($bApi[0].device_id -eq $api[0].device_id)               "$($bApi[0].device_id) -> $($api[0].device_id)"
        Add-Check "Konsole: remotecontrol_id nemainijies" ($bApi[0].remotecontrol_id -eq $api[0].remotecontrol_id) "$($bApi[0].remotecontrol_id) -> $($api[0].remotecontrol_id)"
        Add-Check "Konsole: alias nemainijies"            ($bApi[0].alias -eq $api[0].alias)                       "$($bApi[0].alias) -> $($api[0].alias)"
        Add-Check "Konsole: grupa nemainijusies"          ($bApi[0].groupid -eq $api[0].groupid)                   "$($bApi[0].groupid) -> $($api[0].groupid)"
        Add-Check "Konsole: ierice Online"                ($api[0].online_state -eq "Online")                      "$($api[0].online_state)"
    }
}

Write-Host "`n=== Salidzinajums ($PC) ===" -ForegroundColor Cyan
$checks | Format-Table -AutoSize -Wrap
Write-Host "Versija pirms:  $($b.Version)   (kodi: $($b.ProductCodes))"
Write-Host "Versija pec:    $($after.Version)   (kodi: $($after.ProductCodes))"
if ($bApi.Count -eq 0) { Write-Host "API nedeva datus: konsole parbaudiet ar roku (alias, grupa, ID, online, nav dublikata)." -ForegroundColor Yellow }
if (@($checks | Where-Object { $_.Rezultats -eq "KLUDA" }).Count -eq 0) {
    Write-Host "`nVisas parbaudes OK. Piesaiste un ID saglabajusies." -ForegroundColor Green
    Write-Host "Vel pameginiet savienoties ar $PC caur TeamViewer (bez paroles) un restartejiet datoru - pec tam tam japaradas Online."
} else {
    Write-Host "`nIr KLUDAS - neieslediet TeamViewer atjauninasanu pariejiem datoriem. Atsutiet man before.json un after.json no $OutDir." -ForegroundColor Red
}
