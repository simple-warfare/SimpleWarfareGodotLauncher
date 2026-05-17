param(
    [string]$Package = "com.deltawater.simplewarfaregodotlauncher",
    [switch]$Clear,
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"

if ($Clear) {
    adb logcat -c
}

$pidText = adb shell pidof $Package
$pidText = $pidText.Trim()

if ([string]::IsNullOrWhiteSpace($pidText)) {
    Write-Host "App is not running: $Package"
    Write-Host "Start the app on the device, then run this script again."
    exit 1
}

$filter = "RustyWarfare|Rust panic|Fatal signal|SIGABRT|SIGSEGV|libgdextension|GDExtension|Godot|ResourceBootstrap|assets|mods|bootstrap|failed"
$command = "adb logcat --pid=$pidText | Select-String -Pattern '$filter'"

Write-Host "Watching logcat for package: $Package"
Write-Host "PID: $pidText"
Write-Host "Filter: $filter"

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    Invoke-Expression $command
} else {
    Invoke-Expression $command | Tee-Object -FilePath $OutFile
}
