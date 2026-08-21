param(
    [string]$Path = '{llama-home}\Qwen3.5-9B-Uncensored-Q4_K_M.gguf'
)

$fs = [System.IO.File]::OpenRead($Path)
try {
    $br = New-Object System.IO.BinaryReader($fs)
    [void]$br.ReadBytes(4)               # magic
    [void]$br.ReadUInt32()               # version
    [void]$br.ReadUInt64()               # tensor count
    $kv = [long]$br.ReadUInt64()         # kv count

    function Read-GGUFString {
        param($reader)
        $len = [long]$reader.ReadUInt64()
        $bytes = $reader.ReadBytes([int]$len)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }

    function Skip-GGUFValue {
        param($reader, [int]$type)
        switch ($type) {
            0 { [void]$reader.ReadByte() }
            1 { [void]$reader.ReadSByte() }
            2 { [void]$reader.ReadUInt16() }
            3 { [void]$reader.ReadInt16() }
            4 { [void]$reader.ReadUInt32() }
            5 { [void]$reader.ReadInt32() }
            6 { [void]$reader.ReadSingle() }
            7 { [void]$reader.ReadByte() }
            8 { [void](Read-GGUFString $reader) }
            10 { [void]$reader.ReadUInt64() }
            11 { [void]$reader.ReadInt64() }
            12 { [void]$reader.ReadDouble() }
            9 {
                $elemType = [int]$reader.ReadUInt32()
                $count = [long]$reader.ReadUInt64()
                if ($elemType -eq 8) {
                    for ($i = 0; $i -lt $count; $i++) { [void](Read-GGUFString $reader) }
                } else {
                    $step = switch ($elemType) {
                        0 { 1 }; 1 { 1 }; 2 { 2 }; 3 { 2 }; 4 { 4 }; 5 { 4 }; 6 { 4 }
                        7 { 1 }; 10 { 8 }; 11 { 8 }; 12 { 8 }; default { -1 }
                    }
                    if ($step -gt 0) { [void]$reader.BaseStream.Seek($count * $step, [System.IO.SeekOrigin]::Current) }
                    else { for ($i = 0; $i -lt $count; $i++) { Skip-GGUFValue $reader $elemType } }
                }
            }
            default { throw "unknown gguf value type: $type" }
        }
    }

    $want = @('general.name','general.basename','general.size_label','general.type','tokenizer.ggml.pre','tokenizer.ggml.model','general.architecture')
    for ($i = 0; $i -lt $kv; $i++) {
        $key = Read-GGUFString $br
        $type = [int]$br.ReadUInt32()
        if ($want -contains $key -and $type -eq 8) {
            Write-Host "$key = $(Read-GGUFString $br)"
        } else {
            Skip-GGUFValue $br $type
        }
    }
}
finally {
    $fs.Dispose()
}
