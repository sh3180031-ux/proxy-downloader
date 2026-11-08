# Proxy Downloader - Windows client.
# Sends the request to GitHub Actions, waits for the run, then saves the file straight into the Downloads folder.
# No browser, no zip. The file is deleted from GitHub after it was saved.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ConfigDir  = Join-Path $env:APPDATA 'ProxyDownloader'
$ConfigFile = Join-Path $ConfigDir 'config.json'
$SaveDir    = Join-Path $env:USERPROFILE 'Downloads'
$script:Cancel = $false
$script:Busy = $false

# ---------------- settings (token is encrypted with Windows DPAPI, readable only by this user) ----------------
function Load-Config {
    if (-not (Test-Path $ConfigFile)) { return $null }
    try {
        $c = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $sec = ConvertTo-SecureString $c.token
        $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
        return @{ owner = $c.owner; repo = $c.repo; token = $token }
    } catch { return $null }
}
function Save-Config($owner, $repo, $token) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $enc = ConvertTo-SecureString $token -AsPlainText -Force | ConvertFrom-SecureString
    @{ owner = $owner; repo = $repo; token = $enc } | ConvertTo-Json | Set-Content $ConfigFile -Encoding UTF8
}

# ---------------- helpers ----------------
function Wait-Ui([int]$ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $ms) {
        [System.Windows.Forms.Application]::DoEvents()
        if ($script:Cancel) { throw 'בוטל' }
        Start-Sleep -Milliseconds 50
    }
}
function Set-Status([string]$text) {
    $lblStatus.Text = $text
    [System.Windows.Forms.Application]::DoEvents()
}
function Gh([string]$method, [string]$path, $body = $null) {
    $h = @{
        Authorization          = "Bearer $($script:Cfg.token)"
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'proxy-downloader-win'
    }
    $uri = "https://api.github.com/repos/$($script:Cfg.owner)/$($script:Cfg.repo)$path"
    try {
        if ($body) {
            $json = $body | ConvertTo-Json -Depth 5 -Compress
            return Invoke-RestMethod -Method $method -Uri $uri -Headers $h -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json))
        }
        return Invoke-RestMethod -Method $method -Uri $uri -Headers $h
    } catch {
        $code = $null
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        $msg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            try { $msg = ($_.ErrorDetails.Message | ConvertFrom-Json).message } catch {}
        }
        $err = New-Object Exception("GitHub ($code): $msg")
        $err.Data['code'] = $code
        throw $err
    }
}
function Clean-FileName([string]$name) {
    foreach ($c in [IO.Path]::GetInvalidFileNameChars()) { $name = $name.Replace([string]$c, '_') }
    $name = $name.Trim().TrimEnd('.')
    if (-not $name) { $name = 'download' }
    return $name
}
function Unique-Path([string]$dir, [string]$name) {
    $p = Join-Path $dir $name
    if (-not (Test-Path -LiteralPath $p)) { return $p }
    $stem = [IO.Path]::GetFileNameWithoutExtension($name); $ext = [IO.Path]::GetExtension($name)
    $i = 2
    while (Test-Path -LiteralPath (Join-Path $dir "$stem ($i)$ext")) { $i++ }
    return Join-Path $dir "$stem ($i)$ext"
}
function Format-Size([double]$b) {
    if ($b -ge 1GB) { return '{0:N2} GB' -f ($b / 1GB) }
    if ($b -ge 1MB) { return '{0:N1} MB' -f ($b / 1MB) }
    return '{0:N0} KB' -f [Math]::Max(1, $b / 1KB)
}

function Download-Asset($asset, [string]$target) {
    $tmp = "$target.part"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('Authorization', "Bearer $($script:Cfg.token)")   # .NET drops it on the redirect to the storage host
    $wc.Headers.Add('Accept', 'application/octet-stream')
    $wc.Headers.Add('User-Agent', 'proxy-downloader-win')
    $wc.DownloadFileAsync([Uri]$asset.url, $tmp)
    $total = [double]$asset.size
    try {
        while ($wc.IsBusy) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($script:Cancel) { $wc.CancelAsync(); throw 'בוטל' }
            if (Test-Path -LiteralPath $tmp) {
                $got = (Get-Item -LiteralPath $tmp).Length
                if ($total -gt 0) { $progress.Value = [int][Math]::Min(1000, 1000 * $got / $total) }
                $lblStatus.Text = "מוריד למחשב: $(Format-Size $got) מתוך $(Format-Size $total)"
            }
            Start-Sleep -Milliseconds 150
        }
    } finally { $wc.Dispose() }
    $got = 0
    if (Test-Path -LiteralPath $tmp) { $got = (Get-Item -LiteralPath $tmp).Length }
    if ($got -ne $asset.size) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "ההורדה למחשב לא הושלמה ($(Format-Size $got) מתוך $(Format-Size $asset.size))"
    }
    Move-Item -LiteralPath $tmp -Destination $target
}

# ---------------- main flow ----------------
function Start-Job-Download {
    $url = $txtUrl.Text.Trim()
    if (-not $script:Cfg) { Show-Settings; if (-not $script:Cfg) { return } }
    if ($url -notmatch '^https?://') { Set-Status 'נא להדביק קישור שמתחיל ב-http:// או https://'; return }

    $mode = if ($rbFile.Checked) { 'file' } else { 'video' }
    $quality = @('best', '1080', '720', '480', 'audio')[$cmbQuality.SelectedIndex]
    $requestId = [guid]::NewGuid().ToString()
    $tag = "dl-$requestId"

    $script:Busy = $true; $script:Cancel = $false
    $btnGo.Enabled = $false; $btnCancel.Enabled = $true; $btnSettings.Enabled = $false
    $progress.Style = 'Marquee'; $progress.Value = 0
    $saved = @()
    try {
        Set-Status 'שולח בקשה ל-GitHub...'
        $payload = @{ request_id = $requestId; mode = $mode; url = $url }
        if ($mode -eq 'video') { $payload.quality = $quality }
        Gh 'POST' '/dispatches' @{ event_type = 'download'; client_payload = $payload } | Out-Null

        Set-Status 'מחפש את הריצה...'
        $runId = $null
        for ($i = 0; $i -lt 40 -and -not $runId; $i++) {
            Wait-Ui 2000
            $runs = Gh 'GET' '/actions/runs?event=repository_dispatch&per_page=20'
            $m = $runs.workflow_runs | Where-Object { $_.display_title -eq $tag } | Select-Object -First 1
            if ($m) { $runId = $m.id }
        }
        if (-not $runId) { throw 'לא נמצאה ריצה ב-GitHub תוך 80 שניות' }

        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            $run = Gh 'GET' "/actions/runs/$runId"
            if ($run.status -eq 'completed') { break }
            $st = @{ queued = 'בתור'; in_progress = 'השרת מוריד את הקובץ'; waiting = 'ממתין' }[$run.status]
            if (-not $st) { $st = $run.status }
            Set-Status ("{0}... ({1:mm\:ss})" -f $st, $sw.Elapsed)
            if ($sw.Elapsed.TotalMinutes -gt 130) { throw 'הריצה לא הסתיימה בזמן' }
            Wait-Ui 5000
        }
        if ($run.conclusion -ne 'success') {
            throw "ההורדה בשרת נכשלה ($($run.conclusion)). פרטים: https://github.com/$($script:Cfg.owner)/$($script:Cfg.repo)/actions/runs/$runId"
        }

        Set-Status 'מכין את הקובץ...'
        $release = $null
        for ($i = 0; $i -lt 6 -and -not $release; $i++) {
            try { $release = Gh 'GET' "/releases/tags/$tag" } catch { Wait-Ui 2000 }
        }
        if (-not $release -or -not $release.assets) {
            throw "הקובץ ירד בשרת אבל לא פורסם (אולי גדול מ-2GB). אפשר להוריד מכאן: https://github.com/$($script:Cfg.owner)/$($script:Cfg.repo)/actions/runs/$runId"
        }

        $progress.Style = 'Continuous'; $progress.Maximum = 1000
        foreach ($a in $release.assets) {
            $name = if ($a.label) { $a.label } else { $a.name }
            $target = Unique-Path $SaveDir (Clean-FileName $name)
            Download-Asset $a $target
            $saved += $target
        }

        # Remove the file from GitHub now that it is on this computer.
        try { Gh 'DELETE' "/releases/$($release.id)" | Out-Null } catch {}
        try { Gh 'DELETE' "/git/refs/tags/$tag" | Out-Null } catch {}

        $progress.Value = 1000
        $script:LastFile = $saved[-1]
        $btnOpen.Enabled = $true
        Set-Status ("✓ נשמר: " + (($saved | ForEach-Object { Split-Path $_ -Leaf }) -join ', '))
        [System.Media.SystemSounds]::Asterisk.Play()
    } catch {
        $progress.Style = 'Continuous'; $progress.Value = 0
        $msg = if ($_.Exception) { $_.Exception.Message } else { "$_" }
        if ($_.Exception.Data['code'] -eq 403 -or $_.Exception.Data['code'] -eq 401) {
            $msg += '  — בדוק את הטוקן בהגדרות (צריך הרשאת repo).'
        }
        Set-Status "✗ $msg"
    } finally {
        $script:Busy = $false
        $btnGo.Enabled = $true; $btnCancel.Enabled = $false; $btnSettings.Enabled = $true
    }
}

# ---------------- settings window ----------------
function Show-Settings {
    $f = New-Object Windows.Forms.Form
    $f.Text = 'הגדרות'; $f.RightToLeft = 'Yes'; $f.RightToLeftLayout = $true
    $f.Size = New-Object Drawing.Size(440, 300); $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.Font = New-Object Drawing.Font('Segoe UI', 10)
    $y = 15; $boxes = @{}
    foreach ($row in @(@('owner', 'משתמש GitHub (owner)'), @('repo', 'שם הריפו'), @('token', 'טוקן'))) {
        $l = New-Object Windows.Forms.Label; $l.Text = $row[1]; $l.Location = New-Object Drawing.Point(15, $y); $l.AutoSize = $true
        $t = New-Object Windows.Forms.TextBox; $t.Location = New-Object Drawing.Point(15, ($y + 22)); $t.Width = 390
        $t.RightToLeft = 'No'
        if ($row[0] -eq 'token') { $t.UseSystemPasswordChar = $true }
        if ($script:Cfg) { $t.Text = $script:Cfg[$row[0]] }
        elseif ($row[0] -eq 'repo') { $t.Text = 'proxy-downloader' }
        $f.Controls.AddRange(@($l, $t)); $boxes[$row[0]] = $t; $y += 58
    }
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'שמור'; $ok.Location = New-Object Drawing.Point(15, ($y + 5)); $ok.Width = 100
    $ok.Add_Click({
        $o = $boxes.owner.Text.Trim(); $r = $boxes.repo.Text.Trim(); $tk = $boxes.token.Text.Trim()
        if (-not $o -or -not $r -or -not $tk) { [Windows.Forms.MessageBox]::Show('יש למלא את כל השדות') | Out-Null; return }
        Save-Config $o $r $tk
        $script:Cfg = @{ owner = $o; repo = $r; token = $tk }
        $f.Close()
    })
    $f.Controls.Add($ok); $f.AcceptButton = $ok
    [void]$f.ShowDialog($form)
}

# ---------------- main window ----------------
$form = New-Object Windows.Forms.Form
$form.Text = 'Proxy Downloader'
$form.RightToLeft = 'Yes'; $form.RightToLeftLayout = $true
$form.Size = New-Object Drawing.Size(560, 330); $form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$lblUrl = New-Object Windows.Forms.Label; $lblUrl.Text = 'קישור להורדה:'; $lblUrl.Location = New-Object Drawing.Point(15, 15); $lblUrl.AutoSize = $true
$txtUrl = New-Object Windows.Forms.TextBox; $txtUrl.Location = New-Object Drawing.Point(15, 38); $txtUrl.Width = 510; $txtUrl.RightToLeft = 'No'

$rbVideo = New-Object Windows.Forms.RadioButton; $rbVideo.Text = 'וידאו (YouTube, Drive...)'; $rbVideo.Location = New-Object Drawing.Point(15, 75); $rbVideo.AutoSize = $true; $rbVideo.Checked = $true
$rbFile = New-Object Windows.Forms.RadioButton; $rbFile.Text = 'קובץ (קישור ישיר / Drive)'; $rbFile.Location = New-Object Drawing.Point(15, 102); $rbFile.AutoSize = $true

$lblQ = New-Object Windows.Forms.Label; $lblQ.Text = 'איכות:'; $lblQ.Location = New-Object Drawing.Point(300, 78); $lblQ.AutoSize = $true
$cmbQuality = New-Object Windows.Forms.ComboBox; $cmbQuality.DropDownStyle = 'DropDownList'
$cmbQuality.Location = New-Object Drawing.Point(360, 75); $cmbQuality.Width = 165
[void]$cmbQuality.Items.AddRange(@('מקסימלית', '1080p', '720p', '480p', 'שמע בלבד (MP3)')); $cmbQuality.SelectedIndex = 0
$rbFile.Add_CheckedChanged({ $cmbQuality.Enabled = -not $rbFile.Checked })

$btnGo = New-Object Windows.Forms.Button; $btnGo.Text = 'הורד'; $btnGo.Location = New-Object Drawing.Point(15, 140); $btnGo.Size = New-Object Drawing.Size(150, 36)
$btnCancel = New-Object Windows.Forms.Button; $btnCancel.Text = 'בטל'; $btnCancel.Location = New-Object Drawing.Point(175, 140); $btnCancel.Size = New-Object Drawing.Size(80, 36); $btnCancel.Enabled = $false
$btnOpen = New-Object Windows.Forms.Button; $btnOpen.Text = 'הצג בתיקייה'; $btnOpen.Location = New-Object Drawing.Point(265, 140); $btnOpen.Size = New-Object Drawing.Size(120, 36); $btnOpen.Enabled = $false
$btnSettings = New-Object Windows.Forms.Button; $btnSettings.Text = 'הגדרות'; $btnSettings.Location = New-Object Drawing.Point(425, 140); $btnSettings.Size = New-Object Drawing.Size(100, 36)

$progress = New-Object Windows.Forms.ProgressBar; $progress.Location = New-Object Drawing.Point(15, 192); $progress.Size = New-Object Drawing.Size(510, 18); $progress.MarqueeAnimationSpeed = 30
$lblStatus = New-Object Windows.Forms.Label; $lblStatus.Location = New-Object Drawing.Point(15, 218); $lblStatus.Size = New-Object Drawing.Size(510, 60); $lblStatus.Text = "הקבצים נשמרים ב: $SaveDir"

$btnGo.Add_Click({ Start-Job-Download })
$btnCancel.Add_Click({ $script:Cancel = $true })
$btnSettings.Add_Click({ Show-Settings })
$btnOpen.Add_Click({ if ($script:LastFile) { Start-Process explorer.exe "/select,`"$script:LastFile`"" } })
$form.Add_FormClosing({ if ($script:Busy) { $script:Cancel = $true } })

$form.Controls.AddRange(@($lblUrl, $txtUrl, $rbVideo, $rbFile, $lblQ, $cmbQuality, $btnGo, $btnCancel, $btnOpen, $btnSettings, $progress, $lblStatus))
$form.AcceptButton = $btnGo

$script:Cfg = Load-Config
$form.Add_Shown({
    if (-not $script:Cfg) { Show-Settings }
    if ([Windows.Forms.Clipboard]::ContainsText()) {
        $clip = [Windows.Forms.Clipboard]::GetText().Trim()
        if ($clip -match '^https?://\S+$') { $txtUrl.Text = $clip }
    }
})
[void]$form.ShowDialog()
