param(
    [string]$Board = 'root@192.168.0.50',
    [string]$Key = "$env:USERPROFILE\.ssh\fan_board_ed25519"
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$boot = Join-Path $here 'BOOT_rtc_candidate.bin'
$dtb = Join-Path $here 'system_rtc_candidate.dtb'
foreach ($path in @($boot, $dtb, $Key)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Missing staging input: $path" }
}
$expectedBoot = 'e862723ccec332a2822e6f35f5cf3751f0266e520f18928c71726ea81a6e48f6'
$expectedDtb = 'b3f1c879f72547b282a79106374945a8ca503470b71d64fcd52592396fa1429c'
$remote = & ssh -i $Key -o BatchMode=yes $Board 'sha256sum /mnt/sdboot/BOOT.bin /mnt/sdboot/system.dtb'
if ($LASTEXITCODE -ne 0 -or $remote[0] -notmatch "^$expectedBoot " -or $remote[1] -notmatch "^$expectedDtb ") {
    throw 'Board boot files differ from the reviewed baseline'
}
$writable = $false
try {
    & ssh -i $Key -o BatchMode=yes $Board 'mount -o remount,rw /mnt/sdboot'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot temporarily remount SD boot partition writable' }
    $writable = $true
    $backup = & ssh -i $Key -o BatchMode=yes $Board 'cp -n /mnt/sdboot/BOOT.bin /mnt/sdboot/BOOT_before_rtc_20261018.bin && cp -n /mnt/sdboot/system.dtb /mnt/sdboot/system_before_rtc_20261018.dtb && sha256sum /mnt/sdboot/BOOT_before_rtc_20261018.bin /mnt/sdboot/system_before_rtc_20261018.dtb'
    if ($LASTEXITCODE -ne 0 -or $backup[0] -notmatch "^$expectedBoot " -or $backup[1] -notmatch "^$expectedDtb ") {
        throw 'Board backup hash check failed'
    }
    & scp -i $Key -o BatchMode=yes $boot "${Board}:/mnt/sdboot/BOOT_rtc_candidate.bin"
    if ($LASTEXITCODE -ne 0) { throw 'BOOT staging failed' }
    & scp -i $Key -o BatchMode=yes $dtb "${Board}:/mnt/sdboot/system_rtc_candidate.dtb"
    if ($LASTEXITCODE -ne 0) { throw 'DTB staging failed' }
    $staged = & ssh -i $Key -o BatchMode=yes $Board 'sha256sum /mnt/sdboot/BOOT_rtc_candidate.bin /mnt/sdboot/system_rtc_candidate.dtb'
    if ($LASTEXITCODE -ne 0 -or
        $staged[0] -notmatch ('^' + (Get-FileHash -Algorithm SHA256 -LiteralPath $boot).Hash.ToLower() + ' ') -or
        $staged[1] -notmatch ('^' + (Get-FileHash -Algorithm SHA256 -LiteralPath $dtb).Hash.ToLower() + ' ')) {
        throw 'Staged file hashes do not match local artifacts'
    }
}
finally {
    if ($writable) {
        & ssh -i $Key -o BatchMode=yes $Board 'sync && mount -o remount,ro /mnt/sdboot'
        if ($LASTEXITCODE -ne 0) { throw 'SD boot partition could not be restored to read-only' }
    }
}
Write-Output 'RTC BOOT and DTB staged on SD; active BOOT.bin and system.dtb untouched.'
