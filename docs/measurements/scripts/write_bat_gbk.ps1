# Convert UTF-8 bat source to GBK + CRLF and write to F:, with roundtrip verification
$ErrorActionPreference = 'Stop'
$src = '{work-dir}\bat35_utf8.txt'
$dst = '{llama-home}\Qwen3.6-35B-A3B-Uncensored_llama_webui.bat'

$text = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)
$text = $text -replace "`r?`n", "`r`n"

$gbk = [System.Text.Encoding]::GetEncoding(936)
[System.IO.File]::WriteAllText($dst, $text, $gbk)

# roundtrip verify
$back = [System.IO.File]::ReadAllText($dst, $gbk)
$backNorm = $back -replace "`r?`n", "`r`n"
if ($backNorm -eq $text) {
  Write-Output "OK: wrote $dst ($($text.Length) chars, GBK+CRLF, roundtrip=True)"
} else {
  Write-Output "FAIL: roundtrip mismatch!"
  for ($i = 0; $i -lt [math]::Min($text.Length, $backNorm.Length); $i++) {
    if ($text[$i] -ne $backNorm[$i]) { Write-Output "first diff at char $i"; break }
  }
}
