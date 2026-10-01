$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$manager = Join-Path $repo 'scripts\manage.cmd'
$testRoot = Join-Path $env:TEMP ('blue-whale-tests-' + [guid]::NewGuid().ToString('N'))
$taskHome = Join-Path $testRoot ('home space ' + [char]0x6D4B + [char]0x8BD5)
$target = Join-Path $taskHome 'pets\blue-whale-pet'
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Invoke-Manager($action, $root, $replace = '', $commandPath = $manager) {
    foreach ($value in @($action, $root, $replace, $commandPath)) {
        if ($value -match '["\r\n]') { throw 'Invalid command argument' }
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $env:ComSpec
    $info.Arguments = '/d /s /c ""' + $commandPath + '" "' + $action + '" "' + $root + '" "' + $replace + '""'
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $script:lastCommandOutput = $stdout + $stderr
    Write-Host $script:lastCommandOutput
    $result = $process.ExitCode
    $process.Dispose()
    return $result
}
Assert (Test-Path -LiteralPath $manager) 'FAIL: installation command is missing'
Assert ((Invoke-Manager 'install' $taskHome) -eq 0) 'Clean installation failed'
Assert (Test-Path -LiteralPath (Join-Path $target 'pet.json')) 'Manifest missing'
Assert ((Get-FileHash -LiteralPath (Join-Path $target 'spritesheet.png')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $repo 'pet\spritesheet.png')).Hash) 'Installed asset changed'
Assert ((Invoke-Manager 'install' $taskHome) -eq 0) 'Repeated installation failed'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $taskHome 'pets') -Directory).Count -eq 1) 'Repeated install created a backup'
Set-Content -LiteralPath (Join-Path $target 'pet.json') -Value 'modified'
Assert ((Invoke-Manager 'uninstall' $taskHome) -ne 0) 'Uninstall removed a changed installation file'
Assert ((Get-Content -LiteralPath (Join-Path $target 'pet.json') -Raw).Trim() -eq 'modified') 'Changed installation file was lost'
Copy-Item -LiteralPath (Join-Path $repo 'pet\pet.json') -Destination (Join-Path $target 'pet.json')
Set-Content -LiteralPath (Join-Path $target 'keep.txt') -Value 'user file'
Assert ((Invoke-Manager 'install' $taskHome) -ne 0) 'Conflict was silently overwritten'
Assert (Test-Path -LiteralPath (Join-Path $target 'keep.txt')) 'Conflict file was lost'
Assert ((Invoke-Manager 'uninstall' $taskHome) -ne 0) 'Uninstall removed a modified folder'
Assert ((Invoke-Manager 'install' $taskHome '--replace') -eq 0) 'Explicit replacement failed'
$backups = @(Get-ChildItem -LiteralPath (Join-Path $taskHome 'pets') -Directory -Filter 'blue-whale-pet.backup-*')
Assert ($backups.Count -eq 1) 'Conflict backup missing'
Assert (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'keep.txt')) 'Backup lost user file'
Assert ((Invoke-Manager 'uninstall' $taskHome) -eq 0) 'Uninstall failed'
Assert (-not (Test-Path -LiteralPath $target)) 'Uninstall left pet folder'
Assert (Test-Path -LiteralPath $backups[0].FullName) 'Uninstall removed backup'
Assert ((Invoke-Manager 'uninstall' $taskHome) -eq 0) 'Repeated uninstall failed'
$env:CODEX_HOME = Join-Path $testRoot 'environment home'
Assert ((Invoke-Manager 'install' '') -eq 0) 'CODEX_HOME not honored'
Assert (Test-Path -LiteralPath (Join-Path $env:CODEX_HOME 'pets\blue-whale-pet\pet.json')) 'Wrong default home'
$copy = Join-Path $testRoot ('package space ' + [char]0x6D4B + [char]0x8BD5)
Copy-Item -LiteralPath $repo -Destination $copy -Recurse
$entryHome = Join-Path $testRoot 'entry home'
Assert ((Invoke-Manager $entryHome '' '' (Join-Path $copy 'install.cmd')) -eq 0) 'Install entry/package path with spaces/non-ASCII failed'
Assert ((Invoke-Manager $entryHome '' '' (Join-Path $copy 'uninstall.cmd')) -eq 0) 'Uninstall entry/package path with spaces/non-ASCII failed'
Add-Content -LiteralPath (Join-Path $copy 'pet\spritesheet.png') -Value 'tamper'
Assert ((Invoke-Manager 'install' (Join-Path $testRoot 'tamper home') '' (Join-Path $copy 'scripts\manage.cmd')) -ne 0) 'Changed source asset accepted'
Assert ($script:lastCommandOutput -match 'Package checksum failed') 'Source corruption failed for the wrong reason'
Assert (-not (Test-Path -LiteralPath (Join-Path $testRoot 'tamper home\pets\blue-whale-pet'))) 'Tampered source installed'
$outside = Join-Path $testRoot 'outside data'
New-Item -ItemType Directory -Path $outside | Out-Null
Set-Content -LiteralPath (Join-Path $outside 'keep.txt') -Value 'outside'
$linkHome = Join-Path $testRoot 'junction home'
New-Item -ItemType Directory -Path (Join-Path $linkHome 'pets') | Out-Null
New-Item -ItemType Junction -Path (Join-Path $linkHome 'pets\blue-whale-pet') -Target $outside | Out-Null
Assert ((Invoke-Manager 'install' $linkHome '--replace') -ne 0) 'Destination junction accepted'
Assert ((Invoke-Manager 'uninstall' $linkHome) -ne 0) 'Destination junction uninstalled'
Assert ((Get-Content -LiteralPath (Join-Path $outside 'keep.txt') -Raw).Trim() -eq 'outside') 'Outside data changed'
$nestedHome = Join-Path $testRoot 'nested junction home'
Assert ((Invoke-Manager 'install' $nestedHome) -eq 0) 'Nested link fixture install failed'
New-Item -ItemType Junction -Path (Join-Path $nestedHome 'pets\blue-whale-pet\linked data') -Target $outside | Out-Null
Assert ((Invoke-Manager 'install' $nestedHome '--replace') -ne 0) 'Replacement accepted a link inside the destination'
Assert ($script:lastCommandOutput -match 'inside the destination folder') 'Nested link failed for the wrong reason'
Assert ((Get-Content -LiteralPath (Join-Path $outside 'keep.txt') -Raw).Trim() -eq 'outside') 'Nested link altered outside data'
$linkedPackage = Join-Path $testRoot 'junction package'
Copy-Item -LiteralPath $repo -Destination $linkedPackage -Recurse
Move-Item -LiteralPath (Join-Path $linkedPackage 'pet') -Destination (Join-Path $linkedPackage 'pet-original')
New-Item -ItemType Junction -Path (Join-Path $linkedPackage 'pet') -Target (Join-Path $linkedPackage 'pet-original') | Out-Null
Assert ((Invoke-Manager 'install' (Join-Path $testRoot 'linked source home') '' (Join-Path $linkedPackage 'scripts\manage.cmd')) -ne 0) 'Source junction accepted'
Assert ($script:lastCommandOutput -match 'symbolic link or junction') 'Source junction failed for the wrong reason'
Write-Host 'PASS: clean install, spaces/non-ASCII paths, repeated install, conflict preservation, backup, protected uninstall, repeated uninstall, CODEX_HOME and source hash rejection'
Write-Host ('Evidence directory: ' + $testRoot)
