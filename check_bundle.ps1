$content = Get-Content 'e:\anx-reader-develop\assets\foliate-js\dist\bundle.js' -Raw
$strings = @('applyTextEdits', 'getStructuredText', 'requestTextEdits', 'blockquote', 'getChapterContent', 'getAllChapters', 'saveOriginalContent', 'restoreOriginalContent')
foreach ($s in $strings) {
    if ($content -match [regex]::Escape($s)) {
        Write-Host "FOUND: $s"
    } else {
        Write-Host "NOT FOUND: $s"
    }
}
