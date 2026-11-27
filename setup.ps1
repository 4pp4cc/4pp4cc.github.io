# Fresh Windows Setup launcher - https://4pp4cc.github.io/setup.ps1
& {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $folder = Join-Path $env:TEMP ('FreshWindowsSetup-' + [guid]::NewGuid().ToString('N'))
    $logPath = Join-Path $folder 'launcher.log'
    $scriptPath = Join-Path $folder 'Fresh-Windows-Setup.ps1'
    function Show-SetupSupport {
        Clear-Host
        Write-Host '  +==========================================================+' -ForegroundColor Cyan
        Write-Host '  |                FRESH WINDOWS SETUP                       |' -ForegroundColor White
        Write-Host '  |                    GZ / 4pp4cc                           |' -ForegroundColor Cyan
        Write-Host '  +----------------------------------------------------------+' -ForegroundColor Cyan
        Write-Host '  |       ( (                                                |' -ForegroundColor Yellow
        Write-Host '  |        ) )      LIKE THIS PROJECT?                        |' -ForegroundColor Yellow
        Write-Host '  |     .------.     Support the next improvement             |' -ForegroundColor Yellow
        Write-Host '  |     |      |]                                            |' -ForegroundColor Yellow
        Write-Host '  |     `------`       KO-FI                                  |' -ForegroundColor Yellow
        Write-Host '  +==========================================================+' -ForegroundColor Cyan
        Write-Host '                 https://ko-fi.com/gzred' -ForegroundColor Green
        Write-Host ''
        Write-Host '  Setup runs in the other windows. This launcher stays here.'
        Write-Host '  Ctrl+C exits and keeps this session''s files.'
        Write-Host ''
    }
    function Get-FailedSetupParts {
        $path = Join-Path $folder 'State\last-run.json'
        if (-not (Test-Path -LiteralPath $path)) { return @('All') }
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $bad = @{}
        $history = $state.RunHistory
        $runs = if ($history) { @($history.PSObject.Properties | Sort-Object {$_.Value.Time}) }
            else { @([pscustomobject]@{Name='All';Value=[pscustomobject]@{Results=$state.Results}}) }
        foreach ($run in $runs) {
            if ($run.Name -ne 'All') { $bad.Remove($run.Name) }
            foreach ($result in @($run.Value.Results | Where-Object Status -eq 'Needs attention')) {
                if ($run.Name -ne 'All') { $bad[$run.Name]=$true; continue }
                switch -Regex ([string]$result.Step) {
                    'GPU|AMD|NVIDIA|Intel Driver & Support Assistant' { $bad['Gpu']=$true; break }
                    'Office|activation|requested command' { $bad['Office']=$true; break }
                    'driver|SDI|Manufacturer|catalog' { $bad['Drivers']=$true; break }
                    'Chrome|Google|Brave|WinGet|Install/update|NetTime|RustDesk|Apps|software' { $bad['Software']=$true; break }
                    default { $bad['Debloat']=$true }
                }
            }
        }
        if (@($state.UnresolvedDevices).Count) { $bad['Drivers']=$true }
        if ($history.All -or $history.Software -or -not $history) {
            $chrome = @((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
                (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
                (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')) |
                Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $chrome) { $bad['Software']=$true }
        }
        return @('Software','Gpu','Office','Drivers','Debloat') | Where-Object { $bad.ContainsKey($_) }
    }

    function Remove-LauncherSession {
        $root = (Resolve-Path -LiteralPath $folder).ProviderPath
        $temp = (Resolve-Path -LiteralPath $env:TEMP).ProviderPath.TrimEnd('\')
        if ((Split-Path $root -Parent) -ne $temp -or
            (Split-Path $root -Leaf) -notmatch '^FreshWindowsSetup-[a-f0-9]{32}$') { throw 'Unexpected session path.' }
        $pending = New-Object 'Collections.Generic.Stack[string]'
        $pending.Push($root)
        while ($pending.Count) {
            $path = $pending.Pop()
            if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Cleanup refuses linked directories.'
            }
            foreach ($item in Get-ChildItem -LiteralPath $path -Force) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Cleanup refuses linked items.' }
                if ($item.PSIsContainer) { $pending.Push($item.FullName) }
            }
        }
        Remove-Item -LiteralPath $root -Recurse -Force
    }

    function Invoke-LauncherTask {
        param(
            [ValidateSet('All','Debloat','Software','Office','Drivers','Gpu')][string]$Part,
            [ValidateSet('Auto','x64','x86','UninstallOlder')][string]$OfficeAction = 'Auto'
        )
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            Write-Host 'Downloading Fresh Windows Setup...'
            $download = $scriptPath + '.download'
            Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/4pp4cc/fresh-windows-setup/main/Fresh-Windows-Setup.ps1' -OutFile $download
            $parseErrors = $null
            [void][Management.Automation.Language.Parser]::ParseFile($download,[ref]$null,[ref]$parseErrors)
            if ($parseErrors) { throw ($parseErrors -join [Environment]::NewLine) }
            Move-Item -LiteralPath $download -Destination $scriptPath -Force
        }
        $quotedLog = "'" + $logPath.Replace("'", "''") + "'"
        $quotedFolder = "'" + $folder.Replace("'", "''") + "'"
        $quotedScript = "'" + $scriptPath.Replace("'", "''") + "'"
        $command = '& {0} -Part {1} -OfficeAction {2} -LauncherRoot {3}' -f $quotedScript,$Part,$OfficeAction,$quotedFolder
        $bootstrap = @"
`$ErrorActionPreference = 'Stop'
`$log = $quotedLog
try {
    'Starting $Part ($OfficeAction).' | Add-Content -LiteralPath `$log -Encoding UTF8
    $command
    `$code = `$LASTEXITCODE
    "Setup returned `$code." | Add-Content -LiteralPath `$log -Encoding UTF8
    exit `$code
} catch {
    (`$_ | Out-String) | Add-Content -LiteralPath `$log -Encoding UTF8
    exit 1
}
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
        $system = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { 'Sysnative' } else { 'System32' }
        $powershell = Join-Path $env:SystemRoot "$system\WindowsPowerShell\v1.0\powershell.exe"
        $process = Start-Process -FilePath $powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -PassThru
        while (-not $process.WaitForExit(250)) { Start-Sleep -Milliseconds 100 }
        $process.Refresh()
        return $process.ExitCode -eq 0
    }

    $message = ''
    $failureMessage = 'The action failed and was logged. Press 9 to view logs.'
    New-Item -ItemType Directory -Path $folder | Out-Null
    "Launcher started $(Get-Date -Format o)" | Set-Content -LiteralPath $logPath -Encoding UTF8
    $officeOnly = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber -lt 22000
    $inOffice = $false
    while ($true) {
        Show-SetupSupport
        if ($message) { Write-Host "  $message"; Write-Host '' }
        $message = ''
        try {
            if ($inOffice) {
                Write-Host '  Office'
                if ([Environment]::Is64BitOperatingSystem) { Write-Host '  1) Install or update Office 2024 (64-bit)' }
                Write-Host '  2) Uninstall older Office and Microsoft 365 desktop apps'
                Write-Host '  3) Install or update Office 2024 (32-bit)'
                Write-Host '  5) Run Activation menu (1 for Windows / 2>1 for Office)'
                Write-Host '  9) View logs and errors'
                Write-Host '  0) Return to the main menu'
                $selection = Read-Host 'Choose (Enter = install for this PC)'
                switch ($selection) {
                    '' { if (-not (Invoke-LauncherTask Office Auto)) { $message = $failureMessage } }
                    '0' { $inOffice = $false }
                    '1' {
                        if ([Environment]::Is64BitOperatingSystem -and -not (Invoke-LauncherTask Office x64)) { $message = $failureMessage }
                    }
                    '2' {
                        $confirm = Read-Host 'Remove pre-2024 Office and Microsoft 365 desktop apps? Office 2024 is kept. [y/N]'
                        if ($confirm -eq 'y' -and -not (Invoke-LauncherTask Office UninstallOlder)) { $message = $failureMessage }
                    }
                    '3' { if (-not (Invoke-LauncherTask Office x86)) { $message = $failureMessage } }
                    '5' {
                     $psPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Start-Process -FilePath $psPath -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command "irm https://get.activated.win | iex"'
                    }
                    '9' { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $folder) }
                }
                continue
            }
            Write-Host '  0) Exit and delete this session''s setup files and logs'
            Write-Host '  1) Run the full normal sequence'
            Write-Host '  2) Debloat'
            Write-Host '  3) Software'
            Write-Host '  4) Office'
            Write-Host '  5) Drivers (manufacturer + hardware-ID/SDI windows)'
            Write-Host '  6) AMD/NVIDIA/Intel utilities'
            Write-Host '  7) Retry failed or missing parts'
            Write-Host '  9) View logs and errors'
            $selection = Read-Host 'Choose'
            switch ($selection) {
                '0' { Remove-LauncherSession; return }
                '4' { $inOffice = $true }
                '9' { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $folder) }
                default {
                    if ($officeOnly) {
                        if ($selection -eq '7') { $inOffice = $true }
                        elseif ($selection -in @('1','2','3','5','6')) {
                            $message = 'That option requires Windows 11. Choose 4 for Office on this PC.'
                        }
                        continue
                    }
                    $parts = @(switch ($selection) {
                        '1' { 'All' }; '2' { 'Debloat' }; '3' { 'Software' }
                        '5' { 'Drivers' }; '6' { 'Gpu' }; '7' { Get-FailedSetupParts }
                    })
                    foreach ($part in $parts) {
                        if (-not (Invoke-LauncherTask $part)) { $message = $failureMessage }
                    }
                }
            }
        } catch {
            ($_ | Out-String) | Add-Content -LiteralPath $logPath -Encoding UTF8
            $message = $failureMessage
        }
    }
}
