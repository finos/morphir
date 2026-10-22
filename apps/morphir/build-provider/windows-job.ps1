$ErrorActionPreference = 'Stop'
try {
    # Load the two built-in modules this script uses from PowerShell's own
    # directory and never search PSModulePath. Command autoloading reached the
    # all-users Program Files modules under a stripped host environment, which
    # cost about 22 seconds per job on Windows CI.
    $PSModuleAutoLoadingPreference = 'None'
    foreach ($module in 'Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility') {
        Import-Module -Name ([IO.Path]::Combine($PSHOME, 'Modules', $module, "$module.psd1"))
    }
    $requestPath = $args[0]
    $file = Get-Item -LiteralPath $requestPath
    if ($file.Length -gt 131072) { throw 'Invalid job request' }
    $request = [IO.File]::ReadAllText($requestPath) | ConvertFrom-Json
    if ($request.profile -ne 'morphir-windows-job-v1') { throw 'Invalid job profile' }
    # Acquire the owner handle before compiling the worker. Its identity cannot
    # change through PID reuse while compilation or the supervised command runs.
    $owner = [Diagnostics.Process]::GetProcessById($request.owner)
    $ownerHandle = $owner.Handle
    Add-Type -Path (Join-Path $PSScriptRoot 'WindowsJob.cs')
    $result = [MorphirWindowsJob]::Run($request.program, [string[]]$request.args, $request.cwd, [string[]]$request.environment, $ownerHandle, [long]$request.deadline, $request.stop)
    $json = $result | ConvertTo-Json -Compress
    $temporary = $request.receipt + '.tmp'
    [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary, $request.receipt)
    if ($result.reason -eq 'execution.owner_exited') {
        # The owner cannot read its receipt. This private transport has no model
        # files, and Run has already confirmed there are no active job members.
        [IO.Directory]::Delete([IO.Path]::GetDirectoryName($requestPath), $true)
    }
    $owner.Dispose()
    exit 0
} catch {
    [Console]::Error.WriteLine('execution.windows_job_failed: ' + $_.Exception.Message)
    exit 1
}
