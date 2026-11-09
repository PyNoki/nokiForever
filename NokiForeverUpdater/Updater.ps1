param([string]$ZipPath, [string]$GamePath, [switch]$NoDialogs)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Find-ForeverFolder([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    $item = Get-Item -LiteralPath $Path
    $child = Join-Path $item.FullName '_forever_'
    if (Test-Path -LiteralPath (Join-Path $child 'Wow.exe') -PathType Leaf) { return $child }
    while ($item) {
        if ($item.Name -ieq '_forever_' -and (Test-Path -LiteralPath (Join-Path $item.FullName 'Wow.exe') -PathType Leaf)) { return $item.FullName }
        $item = $item.Parent
    }
    return $null
}

try {
    if (-not $ZipPath) {
        $download = Join-Path ([IO.Path]::GetTempPath()) ('NokiForeverDownload-' + [guid]::NewGuid().ToString('N') + '.zip')
        Write-Host 'Downloading the latest Noki Forever from GitHub...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri 'https://github.com/PyNoki/nokiForever/archive/refs/heads/main.zip' -OutFile $download -UseBasicParsing
        $ZipPath = $download
    }
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw 'The selected ZIP was not found.' }

    if (-not $GamePath) {
        $candidates = @(@(
            "$env:ProgramFiles\World of Warcraft\_forever_",
            "${env:ProgramFiles(x86)}\World of Warcraft\_forever_",
            'C:\World of Warcraft\_forever_', 'C:\Games\World of Warcraft\_forever_'
        ) + @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { Join-Path $_.Root 'Battle.net\World of Warcraft\_forever_' })) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'Wow.exe') -PathType Leaf } | Select-Object -Unique
        $candidates = @($candidates)
        if ($candidates.Count -eq 1) {
            $answer = [System.Windows.Forms.MessageBox]::Show("Install to this Forever folder?`n`n$($candidates[0])`n`nChoose No to select another folder.", 'Noki Forever Updater', 'YesNoCancel', 'Question')
            if ($answer -eq 'Cancel') { throw 'Installation cancelled.' }
            if ($answer -eq 'Yes') { $GamePath = $candidates[0] }
        }
        while (-not $GamePath) {
            $picker = New-Object System.Windows.Forms.FolderBrowserDialog
            $picker.Description = 'Select the _forever_ folder, World of Warcraft folder, or a folder inside _forever_'
            if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'No game folder selected. Nothing was installed.' }
            $GamePath = Find-ForeverFolder $picker.SelectedPath
            if (-not $GamePath) {
                [System.Windows.Forms.MessageBox]::Show("Could not find Wow.exe in _forever_. Select your World of Warcraft folder, _forever_ folder, or a folder inside _forever_.`n`nFor example: F:\Battle.net\World of Warcraft\_forever_", 'Choose a different folder', 'OK', 'Warning') | Out-Null
            }
        }
    }
    $GamePath = Find-ForeverFolder $GamePath
    if (-not $GamePath) { throw 'Could not find Wow.exe in the selected _forever_ folder. Select the active Forever installation.' }

    $archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
    try {
        $toc = @($archive.Entries | Where-Object { $_.FullName -match '^(?:[^/]+/)?NokiForever/NokiForever\.toc$' })
        if ($toc.Count -ne 1) { throw 'The downloaded archive does not contain one valid NokiForever folder.' }
        $prefix = $toc[0].FullName.Substring(0, $toc[0].FullName.Length - 'NokiForever.toc'.Length)
        $entries = @($archive.Entries | Where-Object { $_.FullName.StartsWith($prefix, [StringComparison]::Ordinal) -and $_.Name })
        if (-not ($entries.FullName -contains ($prefix + 'NokiForever.lua'))) {
            throw 'This ZIP does not contain NokiForever/NokiForever.toc and NokiForever/NokiForever.lua. Select the official Noki Forever update ZIP.'
        }
        $stage = Join-Path ([IO.Path]::GetTempPath()) ('NokiForeverUpdate-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        try {
            foreach ($entry in $entries) {
                $relative = $entry.FullName.Substring($prefix.Length).Replace('/', '\')
                $target = [IO.Path]::GetFullPath((Join-Path $stage $relative))
                if (-not $target.StartsWith($stage + '\', [StringComparison]::OrdinalIgnoreCase) -or $relative.Contains(':')) { throw 'The ZIP contains an unsafe file path.' }
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
            }
            $destination = Join-Path $GamePath 'Interface\AddOns\NokiForever'
            [IO.Directory]::CreateDirectory($destination) | Out-Null
            Copy-Item -Path (Join-Path $stage '*') -Destination $destination -Recurse -Force
            Write-Host "Installed Noki Forever to: $destination"
            Write-Host 'Restart WoW, or type /reload if the addon was already installed and enabled.'
            if (-not $NoDialogs) { [System.Windows.Forms.MessageBox]::Show("Noki Forever was installed to:`n$destination`n`nRestart WoW, or type /reload if it was already installed and enabled.", 'Noki Forever Updater') | Out-Null }
        } finally { if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force } }
    } finally { $archive.Dispose() }
} catch {
    Write-Host "Update failed: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $NoDialogs) { [System.Windows.Forms.MessageBox]::Show("Update failed:`n$($_.Exception.Message)", 'Noki Forever Updater', 'OK', 'Error') | Out-Null }
    exit 1
} finally {
    if ($download -and (Test-Path -LiteralPath $download)) { Remove-Item -LiteralPath $download -Force }
}

