
<#
.SYNOPSIS
    Converts markdown files into HTML, PDF, or EPUB using Pandoc on Windows.

.DESCRIPTION
    This script combines markdown files from a source directory and exports them into chosen formats (HTML, PDF, EPUB).
    It includes logic to handle images, cover images, document metadata, and formatting suitable for print or eBooks.

.PARAMETER html
    Export to HTML

.PARAMETER pdf
    Export to PDF

.PARAMETER epub
    Export to EPUB

.PARAMETER title
    Title of the document

.PARAMETER author
    Author of the document

.PARAMETER cover
    Path to a cover image for EPUB

.PARAMETER source
    Source directory containing markdown files

.PARAMETER destination
    Output file path (without extension)
#>

param(
    [switch]$html,
    [switch]$pdf,
    [switch]$epub,
    [string]$title,
    [string]$author = "Generated by mdExport",
    [string]$cover,
    [Parameter(Mandatory = $true)][string]$source,
    [Parameter(Mandatory = $true)][string]$destination
)

function Sanitize-MDLine($line) {
    return $line -replace '^---+$', '***'
}

function Combine-Markdown {
    param([string]$inputDir, [string]$combinedFile, [bool]$forEpub)

    if (Test-Path $combinedFile) { Remove-Item $combinedFile -Force }

    $dirs = Get-ChildItem -Path $inputDir -Directory -Recurse | Sort-Object FullName
    foreach ($dir in $dirs) {
        $readmes = Get-ChildItem $dir.FullName -Filter "README.md" -File -ErrorAction SilentlyContinue
        foreach ($file in $readmes) {
            (Get-Content $file.FullName) | ForEach-Object { Sanitize-MDLine $_ } | Add-Content $combinedFile
            Add-Content $combinedFile ($forEpub ? "`n<div style='page-break-after: always;'></div>`n" : "`n```{=latex}`n\newpage`n```")
        }

        $mdFiles = Get-ChildItem $dir.FullName -Filter "*.md" -File | Where-Object { $_.Name -ne "README.md" }
        foreach ($file in $mdFiles) {
            (Get-Content $file.FullName) | ForEach-Object { Sanitize-MDLine $_ } | Add-Content $combinedFile
            Add-Content $combinedFile ($forEpub ? "`n<div style='page-break-after: always;'></div>`n" : "`n```{=latex}`n\newpage`n```")
        }
    }
}

function Rewrite-Markdown-Images {
    param([string]$inputFile, [string]$outputFile, [bool]$forEpub)

    if (Test-Path $outputFile) { Remove-Item $outputFile -Force }

    Get-Content $inputFile | ForEach-Object {
        $line = $_
        if ($line -match '!\[.*\]\((.*?)\)') {
            $path = $Matches[1]
            if ($path -match '^https?://') {
                $line | Out-File $outputFile -Append
            } else {
                $filename = [System.IO.Path]::GetFileNameWithoutExtension($path) + ".png"
                $altText = ($line -match '!\[(.*?)\]') ? $Matches[1] : ""
                if ($forEpub) {
                    Add-Content $outputFile "<figure style='text-align: center; margin: 1em 0;'>"
                    Add-Content $outputFile "  <img src='$filename' alt='$altText' style='width: 2.5in; max-width: 100%; height: auto;' />"
                    Add-Content $outputFile "</figure>"
                } else {
                    Add-Content $outputFile ":::{ .center }"
                    Add-Content $outputFile "![${altText}](${filename}){ width=2.5in }"
                    Add-Content $outputFile ":::"
                }
            }
        } else {
            $line | Out-File $outputFile -Append
        }
    }
}

function Export-Pandoc {
    param(
        [string]$inputMd,
        [string]$outputFile,
        [string]$format,
        [string]$resourcePath,
        [string]$coverImage = ""
    )

    $args = @(
        $inputMd
        "-o", $outputFile
        "--toc"
        "--resource-path=$resourcePath"
    )

    if ($format -eq "pdf") {
        $args += "--pdf-engine=pdflatex"
    }

    if ($format -eq "epub" -and $coverImage) {
        $args += "--epub-cover-image=$coverImage"
    }

    pandoc @args
}

$outputDir = Split-Path $destination -Parent
$outputBase = Split-Path $destination -Leaf
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

$combinedMd = Join-Path $outputDir "combined.md"
$rewrittenMd = Join-Path $outputDir "rewritten.md"
$finalMd = Join-Path $outputDir "final.md"
$headerMd = Join-Path $outputDir "header.md"

if ($pdf -or $epub -or $html) {
    $forEpub = $epub.IsPresent
    Combine-Markdown -inputDir $source -combinedFile $combinedMd -forEpub:$forEpub
    Rewrite-Markdown-Images -inputFile $combinedMd -outputFile $rewrittenMd -forEpub:$forEpub

    $metadata = @(
        "---"
        "title: '$title'"
        "author: '$author'"
        "date: '$(Get-Date -Format yyyy-MM-dd)'"
        "toc: true"
        "fontsize: 10pt"
        "documentclass: article"
        "geometry: margin=1in"
        "---`n"
    )
    Set-Content -Path $headerMd -Value $metadata
    Get-Content $headerMd, $rewrittenMd | Set-Content $finalMd
}

if ($pdf) {
    $pdfOut = "$destination.pdf"
    Export-Pandoc -inputMd $finalMd -outputFile $pdfOut -format "pdf" -resourcePath "$source"
    Write-Host "PDF created at: $pdfOut"
}
if ($epub) {
    $epubOut = "$destination.epub"
    Export-Pandoc -inputMd $finalMd -outputFile $epubOut -format "epub" -resourcePath "$source" -coverImage $cover
    Write-Host "EPUB created at: $epubOut"
}
if ($html) {
    $htmlOut = "$destination.html"
    Export-Pandoc -inputMd $combinedMd -outputFile $htmlOut -format "html" -resourcePath "$source"
    Write-Host "HTML created at: $htmlOut"
}

# Cleanup
Remove-Item $combinedMd, $rewrittenMd, $finalMd, $headerMd -ErrorAction SilentlyContinue


function Convert-Images {
    param(
        [string]$inputDir,
        [string]$outputDir,
        [int]$maxWidth = 500
    )

    $imageExtensions = @("*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg")

    foreach ($ext in $imageExtensions) {
        Get-ChildItem -Path $inputDir -Recurse -Include $ext -File | ForEach-Object {
            $relPath = $_.FullName.Substring($inputDir.Length).TrimStart("\/")
            $targetPath = Join-Path $outputDir ([System.IO.Path]::ChangeExtension($relPath, ".png"))
            $targetDir = Split-Path $targetPath -Parent
            if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }

            Write-Host "  + Converting $($_.Name) → $(Split-Path $targetPath -Leaf)"
            & convert $_.FullName -resize "${maxWidth}x${maxWidth}>" $targetPath 2>$null
        }
    }
}

# Setup staging directories
$pdfImageDir = Join-Path $outputDir "_pdf-images"
$epubImageDir = Join-Path $outputDir "_epub-images"

if ($pdf) {
    if (-not (Test-Path $pdfImageDir)) { New-Item -ItemType Directory -Path $pdfImageDir | Out-Null }
    Convert-Images -inputDir $source -outputDir $pdfImageDir -maxWidth 500
}

if ($epub) {
    if (-not (Test-Path $epubImageDir)) { New-Item -ItemType Directory -Path $epubImageDir | Out-Null }
    Convert-Images -inputDir $source -outputDir $epubImageDir -maxWidth 600
}
