param(
    [string]$Path = '{llama-home}\Qwen3.6-35B-A3B\Qwen3.6-35B-A3B-Uncensored-IQ4_NL.gguf'
)
$fs = [System.IO.File]::OpenRead($Path)
try {
    $br = New-Object System.IO.BinaryReader($fs)
    [void]$br.ReadBytes(4); [void]$br.ReadUInt32(); [void]$br.ReadUInt64()
    $kvCount = $br.ReadUInt64()

    function Read-GGUFString {
        param($reader)
        $len = $reader.ReadUInt64()
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
            8 { $s = Read-GGUFString $reader }
            10 { [void]$reader.ReadUInt64() }
            11 { [void]$reader.ReadInt64() }
            12 { [void]$reader.ReadDouble() }
            9 {
                $elemType = [int]$reader.ReadUInt32()
                $count = [long]$reader.ReadUInt64()
                $step = switch ($elemType) { 0 { 1 }; 1 { 1 }; 2 { 2 }; 3 { 2 }; 4 { 4 }; 5 { 4 }; 6 { 4 }; 7 { 1 }; 8 { 0 }; 10 { 8 }; 11 { 8 }; 12 { 8 }; default { -1 } }
                if ($elemType -eq 8) { for ($i = 0; $i -lt $count; $i++) { $len = [long]$reader.ReadUInt64(); [void]$reader.ReadBytes([int]$len) } }
                elseif ($step -gt 0) { [void]$reader.BaseStream.Seek($count * $step, [System.IO.SeekOrigin]::Current) }
                else { for ($i = 0; $i -lt $count; $i++) { [void](Skip-GGUFValue $reader $elemType) } }
            }
            default { throw "unknown type $type" }
        }
    }

    $wanted = @('general.architecture', 'llama.context_length', 'llama.rope.scaling.type', 'llama.rope.scaling.factor', 'llama.rope.freq_base',
        'qwen35moe.block_count', 'qwen35moe.embedding_length', 'qwen35moe.full_attention_interval',
        'qwen35moe.attention.head_count', 'qwen35moe.attention.head_count_kv',
        'qwen35moe.attention.key_length', 'qwen35moe.attention.value_length',
        'qwen35moe.ssm.inner_size', 'qwen35moe.expert_count', 'qwen35moe.expert_used_count')

    for ($i = 0; $i -lt $kvCount; $i++) {
        $key = Read-GGUFString $br
        $type = [int]$br.ReadUInt32()
        if ($key -in $wanted) {
            if ($type -in @(4, 5, 10, 11)) {
                $v = switch ($type) { 4 { $br.ReadUInt32() }; 5 { $br.ReadInt32() }; 10 { $br.ReadUInt64() }; 11 { $br.ReadInt64() } }
                Write-Output "$key = $v"
            } elseif ($type -eq 8) {
                Write-Output "$key = $(Read-GGUFString $br)"
            } else {
                Write-Output "$key (type $type)"
                [void](Skip-GGUFValue $br $type)
            }
        } else {
            [void](Skip-GGUFValue $br $type)
        }
    }
}
finally { $fs.Dispose() }
