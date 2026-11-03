param([string]$BootGen = 'D:\Anlogic\FD_2026.1_SP1\tools\bootgen\albg1.exe')
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspace = Split-Path -Parent $here
$fsbl = Join-Path $workspace 'ethernet_fsbl_hp1_candidate_20261013\testing\build\testing_hp1.elf'
$uboot = Join-Path $workspace 'boot_smoke_candidate\uboot_sd.elf'
$oldDtb = Join-Path $here 'board_system_before_rtc.dtb'
$newDtb = Join-Path $here 'system_rtc_candidate.dtb'
$bit = Join-Path $here 'reports_rtc_bit\motor_camera_rtc_4143.bit'
$timing = Join-Path $here 'motor_camera_npu_eth_top_route.timingsummary'
$bif = Join-Path $here 'boot_rtc.bif'
$boot = Join-Path $here 'BOOT_rtc_candidate.bin'

$expected = @{
    $fsbl = '54891525DEBD1D2BC5C73240C790E47BA85692429A3D884EB59DB2BFDDDCE771'
    $uboot = 'B5CC9397E3DA0003AAA1BC6226070A645B133541E1A7FB1A7C098F41AF17653D'
    $oldDtb = 'B3F1C879F72547B282A79106374945A8CA503470B71D64FCD52592396FA1429C'
}
foreach ($path in $expected.Keys) {
    if (!(Test-Path -LiteralPath $path) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $expected[$path]) {
        throw "Known-good input changed: $path"
    }
}
foreach ($path in @($newDtb, $bit, $timing, $bif, $BootGen)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Missing RTC candidate input: $path" }
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $newDtb).Hash -eq $expected[$oldDtb]) {
    throw 'RTC device tree did not change'
}
$text = Get-Content -LiteralPath $timing -Raw
if ($text -notmatch 'Confidence\s*:\s*Routed' -or $text -notmatch 'Top Model\s*:\s*motor_camera_npu_eth_top') {
    throw 'RTC bitstream lacks matching routed timing report'
}
foreach ($metric in @('SWNS', 'STNS', 'HWNS', 'HTNS')) {
    if ($text -notmatch "(?m)(?:^|,)\s*${metric}:\s*(-?\d+(?:\.\d+)?)ns") { throw "Missing $metric" }
    if ([double]$Matches[1] -lt 0) { throw "Negative routed $metric" }
}
if (Test-Path -LiteralPath $boot) { throw "Refusing overwrite: $boot" }
& $BootGen -arch dr1m90 -image $bif -o $boot
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $boot)) { throw 'BOOT packaging failed' }
Write-Output "RTC BOOT: $boot"
Write-Output "BOOT SHA-256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $boot).Hash)"
Write-Output "RTC DTB SHA-256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $newDtb).Hash)"
