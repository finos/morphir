# Detect the operating system and output a normalized value

if ($IsWindows -or $env:OS -like "*Windows*") {
    Write-Output "windows"
} elseif ($IsLinux) {
    Write-Output "linux"
} elseif ($IsMacOS) {
    Write-Output "darwin"
} else {
    # Fallback detection
    $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)
    if ($os) {
        Write-Output "windows"
    } else {
        $uname = (uname -s 2>$null)
        if ($uname -like "*Linux*") {
            Write-Output "linux"
        } elseif ($uname -like "*Darwin*") {
            Write-Output "darwin"
        } else {
            Write-Output "unknown"
        }
    }
}
