# Fresh Windows Setup launcher - https://4pp4cc.github.io/setup.ps1
& {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $folder = Join-Path $env:TEMP ('FreshWindowsSetup-' + [guid]::NewGuid().ToString('N'))
    $process = $null
    try {
        New-Item -ItemType Directory -Path $folder | Out-Null
        $scriptPath = Join-Path $folder 'Fresh-Windows-Setup.ps1'
        Write-Host 'Downloading the latest Fresh Windows Setup...'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/4pp4cc/fresh-windows-setup/main/Fresh-Windows-Setup.ps1' -OutFile $scriptPath
        $tokens = $null; $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw 'Downloaded setup script has syntax errors. Setup was not started.' }
        Write-Host 'Review the report before closing the setup terminal. Its downloads, reports and registry backups will then be removed.'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" -CleanSetupFiles'
        $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arguments -PassThru
        $process.WaitForExit()
    } finally {
        if (-not $process -or $process.HasExited) {
            if (Test-Path -LiteralPath $folder) {
                $resolved = (Resolve-Path -LiteralPath $folder).ProviderPath
                $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
                if (-not $resolved.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
                    (Split-Path $resolved -Leaf) -notmatch '^FreshWindowsSetup-[a-f0-9]{32}$') { throw 'Unexpected launcher cleanup path.' }
                if ((Get-Item -LiteralPath $resolved -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Launcher cleanup refuses linked folders.' }
                # This folder contains only the single downloaded script.
                Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $resolved -Force
            }
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
            Clear-Host
        } catch { Write-Warning "Terminal history cleanup was incomplete: $($_.Exception.Message)" }
    }
}
