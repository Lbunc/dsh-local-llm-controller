param([string]$Path)
$fs = [System.IO.File]::OpenRead($Path)
$br = New-Object System.IO.BinaryReader($fs)
try {
    [void]$br.ReadBytes(4); [void]$br.ReadUInt32(); [void]$br.ReadUInt64()
    $kvCount = $br.ReadUInt64()
    function Read-Str { param($r); $len = $r.ReadUInt64(); return [System.Text.Encoding]::UTF8.GetString($r.ReadBytes([int]$len)) }
    function Skip-Val { param($r, [int]$t)
        switch ($t) {
            0 { [void]$r.ReadByte() }
            1 { [void]$r.ReadSByte() }
            2 { [void]$r.ReadUInt16() }
            3 { [void]$r.ReadInt16() }
            4 { [void]$r.ReadUInt32() }
            5 { [void]$r.ReadInt32() }
            6 { [void]$r.ReadSingle() }
            7 { [void]$r.ReadByte() }
            8 { $len = $r.ReadUInt64(); [void]$r.ReadBytes([int]$len) }
            10 { [void]$r.ReadUInt64() }
            11 { [void]$r.ReadInt64() }
            12 { [void]$r.ReadDouble() }
            9 { $at = $r.ReadUInt32(); $al = $r.ReadUInt64(); for ($i = 0; $i -lt $al; $i++) { Skip-Val $r $at } }
            default { throw "unknown type $t" }
        }
    }
    $want = @("general.name","general.architecture","general.sampling.temp","general.sampling.top_k","general.sampling.top_p","qwen35moe.block_count","qwen35moe.context_length","qwen35moe.expert_count","qwen35moe.expert_used_count","qwen35moe.full_attention_interval","qwen35moe.embedding_length","qwen35moe.attention.head_count","qwen35moe.attention.head_count_kv","qwen35moe.ssm.state_size","tokenizer.ggml.pre")
    for ($i = 0; $i -lt $kvCount; $i++) {
        $k = Read-Str $br
        $t = $br.ReadUInt32()
        if ($want -contains $k) {
            $v = $null
            switch ($t) {
                0 { $v = $br.ReadByte() }
                1 { $v = $br.ReadSByte() }
                2 { $v = $br.ReadUInt16() }
                3 { $v = $br.ReadInt16() }
                4 { $v = $br.ReadUInt32() }
                5 { $v = $br.ReadInt32() }
                6 { $v = $br.ReadSingle() }
                7 { $v = $br.ReadBoolean() }
                8 { $v = Read-Str $br }
                10 { $v = $br.ReadUInt64() }
                11 { $v = $br.ReadInt64() }
                12 { $v = $br.ReadDouble() }
                9 {
                    $at = $br.ReadUInt32(); $al = $br.ReadUInt64(); $arr = @()
                    for ($j = 0; $j -lt $al; $j++) {
                        switch ($at) {
                            4 { $arr += $br.ReadUInt32() }
                            5 { $arr += $br.ReadInt32() }
                            6 { $arr += $br.ReadSingle() }
                            8 { $arr += Read-Str $br }
                            default { Skip-Val $br $at }
                        }
                    }
                    $v = $arr
                }
            }
            Write-Output ("{0} = {1}" -f $k, ($v -join ", "))
        }
        else { Skip-Val $br $t }
    }
}
finally { $fs.Close() }
