# Fresh Windows Setup launcher - https://4pp4cc.github.io/setup.ps1
& {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $folder = Join-Path $env:TEMP ('FreshWindowsSetup-' + [guid]::NewGuid().ToString('N'))
    $process = $null
    $launcherFailed = $false
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
        Write-Host '  After every setup window closes, choose what to run again.'
        Write-Host '  Debug .log files and run state are kept in ProgramData\FreshWindowsSetup.'
        Write-Host ''
    }
    function Get-FailedSetupParts {
        $path = Join-Path $env:ProgramData 'FreshWindowsSetup\State\last-run.json'
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
                    'GPU|AMD|NVIDIA' { $bad['Gpu']=$true; break }
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
    try {
        New-Item -ItemType Directory -Path $folder | Out-Null
        $scriptPath = Join-Path $folder 'Fresh-Windows-Setup.ps1'
        Write-Host 'Downloading the latest Fresh Windows Setup...'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/4pp4cc/fresh-windows-setup/main/Fresh-Windows-Setup.ps1' -OutFile $scriptPath
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors)
        if ($parseErrors.Count) { throw 'Downloaded setup has syntax errors; no setup was started.' }
        $parts = @('All')
        do {
            foreach ($part in $parts) {
                $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" -CleanSetupFiles -Part ' + $part
                $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arguments -PassThru
                Show-SetupSupport
                Write-Host ("  Currently running: " + $part) -ForegroundColor Cyan
                $process.WaitForExit()
                $process.Refresh()
                if ($process.ExitCode -ne 0) { Write-Warning "Setup returned code $($process.ExitCode). Review the saved logs." }
            }
            Write-Host ''
            Write-Host '  All setup windows have closed. Run again:' -ForegroundColor Cyan
            Write-Host '  0) Exit and clean temporary setup files (logs retained)'
            Write-Host '  1) Run all again'
            Write-Host '  2) Debloat'
            Write-Host '  3) Software'
            Write-Host '  4) Office'
            Write-Host '  5) Drivers (manufacturer + hardware-ID/SDI windows)'
            Write-Host '  6) AMD/NVIDIA'
            Write-Host '  7) Retry failed or missing parts [Enter]'
            do { $choice = Read-Host 'Choose 0-7' } until ($choice -in @('','0','1','2','3','4','5','6','7'))
            if ($choice -eq '') { $choice = '7' }
            $parts = switch ($choice) {
                '1' { @('All') }; '2' { @('Debloat') }; '3' { @('Software') }
                '4' { @('Office') }; '5' { @('Drivers') }; '6' { @('Gpu') }
                '7' { @(Get-FailedSetupParts) }; default { @() }
            }
            if ($choice -eq '7' -and -not @($parts).Count) { Write-Host 'No recorded failures or missing required Chrome installation. Choose another part or 0 to exit.' -ForegroundColor Green }
        } while ($choice -ne '0')
    } catch {
        $launcherFailed = $true
        Write-Warning "Setup launch failed: $($_.Exception.Message)"
        throw
    } finally {
        try {
        if (-not $process -or $process.HasExited) {
            if (Test-Path -LiteralPath $folder) {
                $resolved = (Resolve-Path -LiteralPath $folder).ProviderPath
                $tempRoot = (Resolve-Path -LiteralPath $env:TEMP).ProviderPath.TrimEnd('\')
                $resolvedParent = (Resolve-Path -LiteralPath (Split-Path $resolved -Parent)).ProviderPath.TrimEnd('\')
                if (-not [string]::Equals($resolvedParent, $tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
                    (Split-Path $resolved -Leaf) -notmatch '^FreshWindowsSetup-[a-f0-9]{32}$') { throw 'Unexpected launcher cleanup path.' }
                if ((Get-Item -LiteralPath $resolved -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Launcher cleanup refuses linked folders.' }
                # This folder contains only the single downloaded script.
                Remove-Item -LiteralPath (Join-Path $resolved 'Fresh-Windows-Setup.ps1') -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $resolved -Force
            }
        }
        } catch {
            Write-Warning "Launcher temporary-file cleanup failed: $($_.Exception.Message)"
        }
        try {
            $pattern = '(?i)https?://4pp4cc\.github\.io/setup\.ps1'
            Get-History | Where-Object CommandLine -match $pattern | ForEach-Object { Clear-History -Id $_.Id }
            if (Get-Module PSReadLine) {
                $options = Get-PSReadLineOption
                $saveStyle = $options.HistorySaveStyle
                $memory = @([Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems() |
                    Where-Object CommandLine -notmatch $pattern | ForEach-Object CommandLine)
                Set-PSReadLineOption -HistorySaveStyle SaveNothing
                try {
                    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
                    foreach ($line in $memory) { [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line) }
                    $historyPath = $options.HistorySavePath
                    if (Test-Path -LiteralPath $historyPath) {
                        $raw = [IO.File]::ReadAllText($historyPath)
                        # Preserve complete multiline commands unless they contain this launcher URL.
                        $commands = New-Object 'Collections.Generic.List[string]'
                        $command = ''
                        foreach ($line in [regex]::Matches($raw, '[^\r\n]*(?:\r\n|\n|\r|$)')) {
                            if (-not $line.Value.Length) { continue }
                            $command += $line.Value
                            if ($line.Value.TrimEnd([char]13,[char]10).EndsWith([string][char]96)) { continue }
                            if ($command -notmatch $pattern) { $commands.Add($command) }
                            $command = ''
                        }
                        if ($command -and $command -notmatch $pattern) { $commands.Add($command) }
                        [IO.File]::WriteAllText($historyPath, ($commands -join ''), (New-Object Text.UTF8Encoding($false)))
                    }
                } finally { Set-PSReadLineOption -HistorySaveStyle $saveStyle }
            }
            if (-not $launcherFailed) { Clear-Host }
        } catch { Write-Warning "Terminal history cleanup was incomplete: $($_.Exception.Message)" }
    }
}
exit
