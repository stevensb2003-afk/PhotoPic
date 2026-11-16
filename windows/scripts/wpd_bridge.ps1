param(
    [Parameter(Mandatory=$true)][ValidateSet("list","scan","copy")][string]$Action,
    [string]$DeviceName = "",
    [string]$ItemPath = "",
    [string]$DestDir = ""
)

$ErrorActionPreference = "SilentlyContinue"
$shell = New-Object -ComObject Shell.Application
$thisPC = $shell.Namespace(17)

function Get-DeviceFolder([string]$TargetName) {
    foreach ($item in $thisPC.Items()) {
        if ($item.Name -eq $TargetName) { return $item.GetFolder }
    }
    return $null
}

if ($Action -eq "list") {
    $devices = @()
    foreach ($item in $thisPC.Items()) {
        # Portable MTP/PTP devices are non-filesystem items under This PC
        if (-not $item.IsFileSystem -and $item.Type -match "Portable|Phone|Camera|Dispositivo|MTP|PTP") {
            $devices += @{ Name = $item.Name; Type = $item.Type }
        }
    }
    $devices | ConvertTo-Json -Compress
    exit 0
}

if ($Action -eq "scan") {
    $devFolder = Get-DeviceFolder $DeviceName
    if (-not $devFolder) { "[]"; exit 0 }
    $results = @()
    $stack = New-Object System.Collections.Stack
    $stack.Push(@{ Folder = $devFolder; Prefix = "" })
    while ($stack.Count -gt 0) {
        $curr = $stack.Pop()
        foreach ($child in $curr.Folder.Items()) {
            $rel = if ($curr.Prefix) { "$($curr.Prefix)/$($child.Name)" } else { $child.Name }
            if ($child.IsFolder) {
                if ($child.Name -match "DCIM|Camera|Pictures|Card|Storage|Almacenamiento" -or $curr.Prefix -match "DCIM") {
                    $stack.Push(@{ Folder = $child.GetFolder; Prefix = $rel })
                }
            } else {
                $results += @{ Name = $child.Name; Size = $child.Size; SubPath = $rel }
            }
        }
    }
    $results | ConvertTo-Json -Compress
    exit 0
}

if ($Action -eq "copy") {
    $devFolder = Get-DeviceFolder $DeviceName
    if (-not $devFolder -or -not $DestDir) { exit 1 }
    $parts = $ItemPath.Split("/")
    $curr = $devFolder
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        $nextItem = $curr.ParseName($parts[$i])
        if ($nextItem) { $curr = $nextItem.GetFolder }
    }
    $targetItem = $curr.ParseName($parts[-1])
    $destNS = $shell.Namespace($DestDir)
    if ($targetItem -and $destNS) {
        # 16 = Yes to all, 4 = Hide progress dialog
        $destNS.CopyHere($targetItem, 20)
    }
}
