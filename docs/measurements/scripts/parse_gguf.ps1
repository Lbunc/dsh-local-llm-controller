param(
    [string]$Path = '{llama-home}\Qwen3.5-9B-Uncensored-Q4_K_M.gguf',
    [string]$OutDir = '{work-dir}'
)

$fs = [System.IO.File]::OpenRead($Path)
try {
    $br = New-Object System.IO.BinaryReader($fs)

    $magic = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
    $version = $br.ReadUInt32()
    $tensorCount = $br.ReadUInt64()
    $kvCount = $br.ReadUInt64()

    Write-Host "GGUF magic=$magic version=$version tensors=$tensorCount kv=$kvCount"

    function Read-GGUFString {
        param($reader)
        $len = $reader.ReadUInt64()
        $bytes = $reader.ReadBytes([int]$len)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    # Skip a value without materializing huge arrays. Returns a short summary string.
    function Skip-GGUFValue {
        param($reader, [int]$type)
        switch ($type) {
            0 { [void]$reader.ReadByte(); return 'uint8' }
            1 { [void]$reader.ReadSByte(); return 'int8' }
            2 { [void]$reader.ReadUInt16(); return 'uint16' }
            3 { [void]$reader.ReadInt16(); return 'int16' }
            4 { [void]$reader.ReadUInt32(); return 'uint32' }
            5 { [void]$reader.ReadInt32(); return 'int32' }
            6 { [void]$reader.ReadSingle(); return 'float32' }
            7 { [void]$reader.ReadByte(); return 'bool' }
            8 { $s = Read-GGUFString $reader; return "string($($s.Length))" }
            10 { [void]$reader.ReadUInt64(); return 'uint64' }
            11 { [void]$reader.ReadInt64(); return 'int64' }
            12 { [void]$reader.ReadDouble(); return 'float64' }
            9 {
                $elemType = [int]$reader.ReadUInt32()
                $count = [long]$reader.ReadUInt64()
                # read and discard elements
                $step = switch ($elemType) {
                    0 { 1 }; 1 { 1 }; 2 { 2 }; 3 { 2 }; 4 { 4 }; 5 { 4 }; 6 { 4 }
                    7 { 1 }; 8 { 0 }; 10 { 8 }; 11 { 8 }; 12 { 8 }
                    default { -1 }
                }
                if ($elemType -eq 8) {
                    for ($i = 0; $i -lt $count; $i++) {
                        $len = [long]$reader.ReadUInt64()
                        [void]$reader.ReadBytes([int]$len)
                    }
                } elseif ($step -gt 0) {
                    [void]$reader.BaseStream.Seek($count * $step, [System.IO.SeekOrigin]::Current)
                } else {
                    for ($i = 0; $i -lt $count; $i++) {
                        [void](Skip-GGUFValue $reader $elemType)
                    }
                }
                return "array[$elemType]x$count"
            }
            default { throw "unknown gguf value type: $type" }
        }
    }

    $keys = @()
    $interesting = @()
    for ($i = 0; $i -lt $kvCount; $i++) {
        $key = Read-GGUFString $br
        $type = [int]$br.ReadUInt32()
        $summary = Skip-GGUFValue $br $type
        $keys += "$key ($summary)"

        if ($key -match 'template|chat|system|eos|bos|general\.name|description|instruction') {
            $interesting += "$key ($summary)"
        }
    }

    # Second pass: re-read KV section, capture the chat template string value.
    $fs.Position = 0
    $br2 = New-Object System.IO.BinaryReader($fs)
    [void]$br2.ReadBytes(4); [void]$br2.ReadUInt32(); [void]$br2.ReadUInt64(); [void]$br2.ReadUInt64()
    $template = $null
    for ($i = 0; $i -lt $kvCount; $i++) {
        $key = Read-GGUFString $br2
        $type = [int]$br2.ReadUInt32()
        if ($key -eq 'tokenizer.chat_template' -and $type -eq 8) {
            $template = Read-GGUFString $br2
        } else {
            [void](Skip-GGUFValue $br2 $type)
        }
    }

    $keys | Set-Content -Path (Join-Path $OutDir 'gguf_keys.txt') -Encoding UTF8
    $interesting | Set-Content -Path (Join-Path $OutDir 'gguf_interesting.txt') -Encoding UTF8
    if ($template) {
        Set-Content -Path (Join-Path $OutDir 'gguf_chat_template.txt') -Value $template -Encoding UTF8
        Write-Host "chat_template captured: $($template.Length) chars"
    } else {
        Write-Host 'no tokenizer.chat_template found'
    }
    Write-Host "metadata keys: $($keys.Count)"
}
finally {
    $fs.Dispose()
}
