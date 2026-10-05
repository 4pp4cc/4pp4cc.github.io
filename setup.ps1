# Fresh Windows Setup launcher - https://4pp4cc.github.io/setup.ps1
& {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $folder = Join-Path $env:TEMP ('FreshWindowsSetup-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder | Out-Null
    $scriptPath = Join-Path $folder 'Fresh-Windows-Setup.ps1'
    $url = 'https://raw.githubusercontent.com/4pp4cc/fresh-windows-setup/main/Fresh-Windows-Setup.ps1'
    Write-Host 'Downloading the latest Fresh Windows Setup...'
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $scriptPath
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Downloaded setup script has syntax errors. Setup was not started.' }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
    Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $arguments
    Write-Host 'Setup opened in its own administrator terminal. Keep the downloaded file until all setup terminals finish.'
}
