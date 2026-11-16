param([string]$KindleRoot='E:\', [string]$OutputParent=[Environment]::GetFolderPath('Desktop'))
$ErrorActionPreference='Stop'
$source=Join-Path $KindleRoot 'kindle-system-test'
$names=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'payload-files.txt'))
foreach($name in $names) {
    if(!(Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) { throw "Missing dependency $name" }
}
$hashes=@{}
foreach($row in (Import-Csv -LiteralPath (Join-Path $PSScriptRoot 'payload-sha256.csv'))) {
    $hashes[$row.Name]=$row.SHA256
}
$baseArchive=Join-Path $source 'root-1536m-v35.img.gz'
$expectedArchive='5d20315fcf519284cc5c89581b3e0699cb772791506c08974364723b30fcac5e'
$expectedImage='4caec7c0537e3758c0a812e7dd66ebca336da78dcd9c8e1a3cfe88f8b8277fc6'
if((Get-FileHash -LiteralPath $baseArchive -Algorithm SHA256).Hash -ne $expectedArchive) { throw 'Base archive checksum mismatch' }
if(!(Test-Path -LiteralPath $OutputParent -PathType Container)) { throw 'Output parent must exist' }
$output=Join-Path $OutputParent ('kindle-first-install-candidate-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null
$runtime=Join-Path $output 'kindle-system-test'
New-Item -ItemType Directory -Path $runtime | Out-Null
$report=Join-Path $output 'candidate-manifest.csv'
try {
    foreach($name in $names) {
        Write-Host "Copying $name"
        $inputPath=Join-Path $source $name
        $target=Join-Path $runtime $name
        Copy-Item -LiteralPath $inputPath -Destination $target
        if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hashes[$name]) { throw "Copy checksum mismatch $name" }
    }
    $image=Join-Path $runtime 'kindle-persistent-v62.img'
    $partial="$image.partial"
    $inputFile=[IO.File]::OpenRead((Join-Path $runtime 'root-1536m-v35.img.gz'))
    try {
        $gzip=[IO.Compression.GZipStream]::new($inputFile,[IO.Compression.CompressionMode]::Decompress)
        try {
            $outputFile=[IO.File]::Open($partial,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
            try { $gzip.CopyTo($outputFile) } finally { $outputFile.Dispose() }
        } finally { $gzip.Dispose() }
    } finally { $inputFile.Dispose() }
    if((Get-Item -LiteralPath $partial).Length -ne 1610612736) { throw 'Image size mismatch' }
    if((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $expectedImage) { throw 'Image checksum mismatch' }
    [IO.File]::Move($partial,$image)
    [IO.File]::WriteAllText((Join-Path $runtime 'kindle-persistent-v62.owner'),"kindle-persistent-v62`n",[Text.Encoding]::ASCII)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'documents') -Destination $output -Recurse
    $records=foreach($file in Get-ChildItem -LiteralPath $output -Recurse | Where-Object { !$_.PSIsContainer }) {
        [PSCustomObject]@{Path=$file.FullName.Substring($output.Length+1);Bytes=$file.Length;SHA256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
    }
    $records | Export-Csv -LiteralPath $report -NoTypeInformation -Encoding UTF8
    [IO.File]::WriteAllText((Join-Path $output 'CANDIDATE-ONLY.txt'),'Local assembly candidate. Initial deployment and redistribution review pending.',[Text.Encoding]::ASCII)
    Write-Host "CANDIDATE_READY $output"
    Write-Host "Upload only the report $report"
} catch {
    [IO.File]::WriteAllText((Join-Path $output 'ASSEMBLY-FAILED.txt'),$_.Exception.Message,[Text.Encoding]::UTF8)
    throw
}
