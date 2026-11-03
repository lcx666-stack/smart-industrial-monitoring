param(
    [switch]$VmPhysicallyDisconnected,
    [string]$Board = 'root@192.168.0.50',
    [string]$Key = "$env:USERPROFILE\.ssh\fan_board_ed25519"
)
$ErrorActionPreference = 'Stop'
if (!$VmPhysicallyDisconnected) {
    throw 'Confirm motor 12 V VM is physically disconnected before activating an untested BOOT.'
}
$script = @'
set -eu
cd /mnt/sdboot
printf '%s\n' \
  'e862723ccec332a2822e6f35f5cf3751f0266e520f18928c71726ea81a6e48f6  BOOT.bin' \
  'b3f1c879f72547b282a79106374945a8ca503470b71d64fcd52592396fa1429c  system.dtb' \
  'e862723ccec332a2822e6f35f5cf3751f0266e520f18928c71726ea81a6e48f6  BOOT_before_rtc_20261018.bin' \
  'b3f1c879f72547b282a79106374945a8ca503470b71d64fcd52592396fa1429c  system_before_rtc_20261018.dtb' \
  '28ac83568a47eb435ced4bcdfd7dfe255b0ec677dbb5c080fec450ec4052f3cc  BOOT_rtc_candidate.bin' \
  'f9ce128b479515777b9aeb3ea07842b01bb65ada10a2c73ff5442f498aa61e72  system_rtc_candidate.dtb' | sha256sum -c -
mount -o remount,rw /mnt/sdboot
committed=0
restore_mount() {
    code=$?
    if [ "$committed" -eq 0 ]; then
        cp -p BOOT_before_rtc_20261018.bin BOOT.bin
        cp -p system_before_rtc_20261018.dtb system.dtb
    fi
    sync
    mount -o remount,ro /mnt/sdboot || code=1
    exit "$code"
}
trap restore_mount EXIT
cp -p BOOT_rtc_candidate.bin BOOT.rtc.new
cp -p system_rtc_candidate.dtb system.rtc.new
sync
mv -f BOOT.rtc.new BOOT.bin
mv -f system.rtc.new system.dtb
printf '%s\n' \
  '28ac83568a47eb435ced4bcdfd7dfe255b0ec677dbb5c080fec450ec4052f3cc  BOOT.bin' \
  'f9ce128b479515777b9aeb3ea07842b01bb65ada10a2c73ff5442f498aa61e72  system.dtb' | sha256sum -c -
committed=1
echo 'RTC BOOT and device tree activated; reboot only after physical safety confirmation.'
'@
($script -replace "`r", '') | & ssh -i $Key -o BatchMode=yes $Board sh -s
if ($LASTEXITCODE -ne 0) { throw 'RTC activation failed; inspect board files and rollback status before reboot' }
