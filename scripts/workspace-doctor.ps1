$ErrorActionPreference = "Stop"

param(
    [string]$Fix = "prompt"
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$passThrough = @()
$overrideFix = $Fix

for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = $args[$i]
    if ($arg -eq "-Fix") {
        if ($i + 1 -lt $args.Count) {
            $overrideFix = $args[$i + 1]
            $i++
        }
        continue
    }
    if ($arg -like "-Fix=*") {
        $overrideFix = $arg.Substring(5)
        continue
    }
    if ($arg -eq "--fix") {
        if ($i + 1 -lt $args.Count) {
            $overrideFix = $args[$i + 1]
            $i++
        }
        continue
    }
    if ($arg -like "--fix=*") {
        $overrideFix = $arg.Substring(6)
        continue
    }
    $passThrough += $arg
}

$pythonArgs = @("$ScriptDir/workspace-doctor.py", "--fix", $overrideFix) + $passThrough
& python @pythonArgs
