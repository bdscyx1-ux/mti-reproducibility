$ErrorActionPreference = 'Stop'

$projectRoot = 'H:\DDM_Final_Project'
$outputDirectory = Join-Path $projectRoot 'Research\Gate14Re\Execution'
$outputPath = Join-Path $outputDirectory 'Gate14Re_Formal_Block_Plan.v1.json'

if (Test-Path -LiteralPath $outputPath) {
    throw "Refusing to overwrite the Gate 14Re formal block plan: $outputPath"
}

$conditions = @(
    [ordered]@{ conditionId='C01'; scenarioId='core-r02-s1-shared'; path='Research/FormalScenarios/v1/Scenarios/core-r02-s1-shared.scenario.json'; bytes=915360; sha256='7612d4a77374c8920cfd493f19cb07b8ba48065dff89187cefd635eee41dfb94'; footprint=81; anchor=$true },
    [ordered]@{ conditionId='C02'; scenarioId='core-r02-s2-shared'; path='Research/FormalScenarios/v1/Scenarios/core-r02-s2-shared.scenario.json'; bytes=915499; sha256='8cb48030e5c75ef5b4477852188dc1930bff5fba32644335af4edadf81d7f32d'; footprint=81; anchor=$false },
    [ordered]@{ conditionId='C03'; scenarioId='core-r03-s1-shared'; path='Research/FormalScenarios/v1/Scenarios/core-r03-s1-shared.scenario.json'; bytes=776143; sha256='a2272840c88fd70d40b2508dd00d75156c86c37ecb813c04651f09fdeb4223a2'; footprint=9; anchor=$false },
    [ordered]@{ conditionId='C04'; scenarioId='core-r03-s2-shared'; path='Research/FormalScenarios/v1/Scenarios/core-r03-s2-shared.scenario.json'; bytes=776129; sha256='c2eaee5d3c241fe2304c3ad794c77fe02efa1c659e32bbc3caeb8b10344d1bc8'; footprint=9; anchor=$false },
    [ordered]@{ conditionId='C05'; scenarioId='core-r06-s1-shared'; path='Research/FormalScenarios/v1/Scenarios/core-r06-s1-shared.scenario.json'; bytes=2970120; sha256='ff4c38d9761b46cefb584f47b8861e6f50fb0de4155e8bae38654d81baf342fc'; footprint=9; anchor=$false },
    [ordered]@{ conditionId='C06'; scenarioId='core-r06-s2-shared'; path='Research/FormalScenarios/v1/Scenarios/core-r06-s2-shared.scenario.json'; bytes=2969869; sha256='3c4650745359e1a60a71d3a6db32890ffb91482c947657bab9f3de322b510126'; footprint=9; anchor=$false },
    [ordered]@{ conditionId='C07'; scenarioId='core-r07-s1-shared'; path='Research/FormalScenarios/v1/Scenarios/core-r07-s1-shared.scenario.json'; bytes=3109801; sha256='34f206248d0c563c4a2bc8bf7d0cb9a1a86b1e53d345a19968776911b5a07692'; footprint=81; anchor=$true },
    [ordered]@{ conditionId='C08'; scenarioId='core-r07-s2-shared'; path='Research/FormalScenarios/v1/Scenarios/core-r07-s2-shared.scenario.json'; bytes=3109676; sha256='a1227c2b468e7ec06836198257a25efd67ac6e0cc4ff622403b582ee58899f2a'; footprint=81; anchor=$false }
)

$rows = @(
    [ordered]@{ labels=@('A','B','D','C'); ids=@('A*-R','D*L','IDFF','C-FF') },
    [ordered]@{ labels=@('B','C','A','D'); ids=@('D*L','C-FF','A*-R','IDFF') },
    [ordered]@{ labels=@('C','D','B','A'); ids=@('C-FF','IDFF','D*L','A*-R') },
    [ordered]@{ labels=@('D','A','C','B'); ids=@('IDFF','A*-R','C-FF','D*L') }
)

$blocks = [System.Collections.Generic.List[object]]::new()
$sequence = 0

function Add-DesignCell {
    param(
        [string]$Module,
        [hashtable]$Condition,
        [int]$N,
        [string]$Lane
    )
    for ($blockIndex = 1; $blockIndex -le 48; $blockIndex++) {
        $script:sequence++
        $rowIndex = ($blockIndex - 1) % 4
        $row = $rows[$rowIndex]
        $laneSlug = if ($Lane -eq 'movement') { 'MOV' } else { 'M4' }
        $blockId = '{0}-{1}-N{2}-{3}-B{4}' -f $Module,$Condition.conditionId,$N.ToString('D4'),$laneSlug,$blockIndex.ToString('D3')
        $blocks.Add([ordered]@{
            sequence = $script:sequence
            blockId = $blockId
            module = $Module
            lane = $Lane
            conditionId = $Condition.conditionId
            scenarioId = $Condition.scenarioId
            scenarioRelativePath = $Condition.path
            scenarioBytes = [long]$Condition.bytes
            scenarioSha256 = $Condition.sha256
            dynamicFootprintCells = [int]$Condition.footprint
            unitCount = $N
            blockIndex = $blockIndex
            williamsRow = $rowIndex + 1
            algorithmLabelsInOrder = @($row.labels)
            algorithmIdsInOrder = @($row.ids)
            maximumWholeBlockReplacements = 1
        })
    }
}

foreach ($condition in $conditions) {
    Add-DesignCell -Module 'A' -Condition $condition -N 128 -Lane 'movement'
    Add-DesignCell -Module 'A' -Condition $condition -N 128 -Lane 'm4'
}

$quantityLevels = @(1,8,32,512)
foreach ($condition in @($conditions | Where-Object { $_.anchor })) {
    foreach ($n in $quantityLevels) {
        Add-DesignCell -Module 'Q' -Condition $condition -N $n -Lane 'movement'
        Add-DesignCell -Module 'Q' -Condition $condition -N $n -Lane 'm4'
    }
}

if ($blocks.Count -ne 1536 -or $sequence -ne 1536) { throw "Unexpected Gate 14Re block count: $($blocks.Count)" }
if (@($blocks.blockId | Sort-Object -Unique).Count -ne 1536) { throw 'Gate 14Re block ids are not unique.' }
if (@($blocks | Where-Object lane -eq 'movement').Count -ne 768) { throw 'Unexpected movement block count.' }
if (@($blocks | Where-Object lane -eq 'm4').Count -ne 768) { throw 'Unexpected M4 block count.' }
if (@($blocks | Where-Object module -eq 'A').Count -ne 768) { throw 'Unexpected main-module block count.' }
if (@($blocks | Where-Object module -eq 'Q').Count -ne 768) { throw 'Unexpected quantity-module block count.' }

$cells = $blocks | Group-Object -Property { '{0}|{1}|{2}|{3}' -f $_.module,$_.conditionId,$_.unitCount,$_.lane }
if ($cells.Count -ne 32) { throw "Unexpected design-cell count: $($cells.Count)" }
foreach ($cell in $cells) {
    if ($cell.Count -ne 48) { throw "Design cell $($cell.Name) does not contain 48 blocks." }
    foreach ($rowNumber in 1..4) {
        if (@($cell.Group | Where-Object { $_.williamsRow -eq $rowNumber }).Count -ne 12) {
            throw "Design cell $($cell.Name) does not use Williams row $rowNumber exactly 12 times."
        }
    }
}

$plan = [ordered]@{
    schema = 'gate14re-formal-block-plan-v1'
    studyId = 'Gate14Re'
    version = 1
    status = 'FROZEN_NONEXECUTING'
    fixedB = 48
    plannedValidProcesses = 1536
    algorithmLabels = @('A','B','C','D')
    algorithmIds = @('A*-R','D*L','C-FF','IDFF')
    blocks = @($blocks)
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$json = ($plan | ConvertTo-Json -Depth 12).Replace("`r`n","`n").Replace("`r","`n") + "`n"
[System.IO.File]::WriteAllText($outputPath, $json, [System.Text.UTF8Encoding]::new($false))

$item = Get-Item -LiteralPath $outputPath
$hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Output ("PLAN_PATH={0}" -f $outputPath)
Write-Output ("PLAN_BYTES={0}" -f $item.Length)
Write-Output ("PLAN_SHA256={0}" -f $hash)
Write-Output 'PLAN_BLOCKS=1536'
Write-Output 'PLAN_DESIGN_CELLS=32'
Write-Output 'PLAN_STATUS=FROZEN_NONEXECUTING'
