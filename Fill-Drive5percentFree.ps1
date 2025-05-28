# Fill C:\ drive, leaving ~5% free space

$drive = Get-PSDrive -Name "C"
$totalSize = $drive.Used + $drive.Free
$targetUsed = $totalSize * 0.95
$fillSize = [math]::Floor($targetUsed - $drive.Used)

if ($fillSize -gt 0) {
    $file = "C:\filler.bin"
    fsutil file createnew $file $fillSize
}
