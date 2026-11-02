<#
 patch-history.ps1
 Palaizams VIENU REIZI no administratora datora. Pielabo NAS failu Scripts\client-install.ps1:
 datora ciklu vesture (Logs\Status\<DATORS>.json) glaba pedejos 100 ierakstus (agrak - 3).
 Pec kartas atkartoti "JauAktuals" cikli tiek sakopoti vienaa ieraksta (ik 15 min cikli neuzpilda saraksta).
 Citas izmainas netiek skartas. Pirms izmainam - rezerves kopija .bak-*.
#>
param(
    [string]$Path = "\\192.168.3.31\Updates\Scripts\client-install.ps1"
)

if (-not (Test-Path $Path)) { Write-Host "KLUDA: nav atrasts $Path" -ForegroundColor Red; exit 1 }
$raw = [System.IO.File]::ReadAllText($Path)
if ($raw -like "*Pedejo 100 REALO ciklu vesture*") { Write-Host "Jau pielabots - nekas nav jadara." -ForegroundColor Yellow; exit 0 }

$crlf = $raw.Contains("`r`n")
$text = $raw.Replace("`r`n", "`n")
$edits = @()
$a1 = @'
        # Pedejo 3 REALO ciklu vesture (izlaistas parbaudes to nemaina)
'@
$n1 = @'
        # Pedejo 100 REALO ciklu vesture (izlaistas parbaudes to nemaina; pec kartas "viss aktuals" cikli tiek sakopoti)
'@
$edits += ,@($a1, $n1)
$a2 = @'
            $history = @((@($record) + $history) | Select-Object -First 3)
'@
$n2 = @'
            if (($Result -eq "JauAktuals") -and ($history.Count -gt 0) -and ([string]$history[0].Result -eq "JauAktuals")) {
                # nekas nav mainijies kops pedeja cikla - neveidojam jaunu ierakstu, tikai atjaunojam pedejo "viss aktuals"
                $history[0] = $record
            } else {
                $history = @((@($record) + $history) | Select-Object -First 100)
            }
'@
$edits += ,@($a2, $n2)

foreach ($e in $edits) {
    $old = [string]$e[0]; $new = [string]$e[1]
    $cnt = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($cnt -ne 1) {
        Write-Host ("KLUDA: anchor atrasts {0} reizes (gaidits 1): {1}" -f $cnt, $old.Trim()) -ForegroundColor Red
        Write-Host "Fails ir mainits kops ta pielabosanas? Nekas netika mainits." -ForegroundColor Red
        exit 1
    }
    $text = $text.Replace($old, $new)
}

if ($crlf) { $text = $text.Replace("`n", "`r`n") }
Copy-Item $Path ($Path + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
[System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "Gatavs: client-install.ps1 pielabots - vesture glabas 100 ierakstus (rezerves kopija .bak-*)." -ForegroundColor Green
