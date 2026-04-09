param(
    [string]$RootDir = (Split-Path -Parent $PSScriptRoot),
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_real_loadable_dump")
)

$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Write-Utf8([string]$Path, [string]$Text) {
    Ensure-Dir (Split-Path -Parent $Path)
    [IO.File]::WriteAllText($Path, $Text.Trim() + "`r`n", (New-Object Text.UTF8Encoding($false)))
}

function Get-FullRightsTemplatePath([string]$RootPath) {
    $fullRightsName = [string]::Concat([char]0x41F, [char]0x43E, [char]0x43B, [char]0x43D, [char]0x44B, [char]0x435, [char]0x41F, [char]0x440, [char]0x430, [char]0x432, [char]0x430)
    $rightsSuffix = [string]::Concat([char]0x2E, [char]0x41F, [char]0x440, [char]0x430, [char]0x432, [char]0x430, [char]0x2E, [char]0x78, [char]0x6D, [char]0x6C)
    $candidatesDirs = @(
        (Join-Path $RootPath "rights_templates"),
        (Join-Path $RootPath "_dump_rights_probe"),
        (Join-Path $RootPath "_battle_full_dump_with_rights"),
        (Join-Path $RootPath "_battle_full_rights_dumped_rights")
    )

    foreach ($rightsDir in $candidatesDirs) {
        if (-not (Test-Path -LiteralPath $rightsDir)) {
            continue
        }

        $candidate = Get-ChildItem -Path $rightsDir -Filter '*.xml' -File |
            Where-Object {
                $_.Name.EndsWith($rightsSuffix, [System.StringComparison]::OrdinalIgnoreCase) -and (
                    $_.Name.Contains($fullRightsName) -or
                    $_.Name -match 'FullRights'
                )
            } |
            Select-Object -First 1

        if ($candidate) {
            return $candidate.FullName
        }
    }

    return $null
}

function Build-FullRightsContent([string]$TemplatePath) {
    if (-not $TemplatePath) {
        return $null
    }
    $content = [IO.File]::ReadAllText($TemplatePath, [Text.Encoding]::UTF8)
    $content = $content.Replace("<setForNewObjects>false</setForNewObjects>", "<setForNewObjects>true</setForNewObjects>")
    $content = $content.Replace("<value>false</value>", "<value>true</value>")
    return $content
}

function Stable-Guid([string]$Seed) {
    $md5 = [Security.Cryptography.MD5]::Create()
    try {
        ([guid]::new($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Seed)))).ToString()
    } finally {
        $md5.Dispose()
    }
}

function Fix([string]$Text) {
    return $Text
}

$script:ReservedLineNoName = [string]::Concat([char]0x41D, [char]0x43E, [char]0x43C, [char]0x435, [char]0x440, [char]0x421, [char]0x442, [char]0x440, [char]0x43E, [char]0x43A, [char]0x438)
$script:SafeLineNoName = [string]::Concat([char]0x41D, [char]0x43E, [char]0x43C, [char]0x435, [char]0x440, [char]0x41F, [char]0x43E, [char]0x437, [char]0x438, [char]0x446, [char]0x438, [char]0x438)

function Safe-FieldName([string]$Name) {
    if ($Name -eq $script:ReservedLineNoName) {
        return $script:SafeLineNoName
    }
    return $Name
}

function Fix-BslText([string]$Text) {
    $pattern = [Text.RegularExpressions.Regex]::Escape("." + $script:ReservedLineNoName) + "(?![\p{L}\p{Nd}_])"
    $replacement = "." + $script:SafeLineNoName
    return [Text.RegularExpressions.Regex]::Replace($Text, $pattern, $replacement)
}

function Load-Xml([string]$Path) {
    $xml = New-Object Xml.XmlDocument
    $xml.LoadXml([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8))
    $xml
}

function T($Node, [string]$XPath) {
    $n = $Node.SelectSingleNode($XPath)
    if ($null -eq $n) { return $null }
    Fix $n.InnerText
}

function Ns($Node, [string]$XPath) {
    $Node.SelectNodes($XPath)
}

function Type-Spec($Node) {
    $t = T $Node "./*[local-name()='Type']"
    switch -Regex ($t) {
        "^xsd:string$" {
            $l = T $Node "./*[local-name()='StringQualifiers']/*[local-name()='Length']"
            if (-not $l) { $l = "50" }
            return @{ K = "s"; L = [int]$l }
        }
        "^xsd:decimal$" {
            $d = T $Node "./*[local-name()='NumberQualifiers']/*[local-name()='Digits']"
            $f = T $Node "./*[local-name()='NumberQualifiers']/*[local-name()='FractionDigits']"
            if (-not $d) { $d = "15" }
            if (-not $f) { $f = "0" }
            return @{ K = "n"; D = [int]$d; F = [int]$f }
        }
        "^xsd:date$" { return @{ K = "d" } }
        "^xsd:boolean$" { return @{ K = "b" } }
        "^CatalogRef\.(.+)$" { return @{ K = "cr"; N = (Fix $Matches[1]) } }
        "^DocumentRef\.(.+)$" { return @{ K = "dr"; N = (Fix $Matches[1]) } }
        "^EnumRef\.(.+)$" { return @{ K = "er"; N = (Fix $Matches[1]) } }
        default { throw "Unsupported type: $t" }
    }
}

function Type-Xml($Spec, [string]$I = "`t`t`t`t`t") {
    switch ($Spec.K) {
        "s" { return @("$I<Type>", "$I`t<v8:Type>xs:string</v8:Type>", "$I`t<v8:StringQualifiers>", "$I`t`t<v8:Length>$($Spec.L)</v8:Length>", "$I`t`t<v8:AllowedLength>Variable</v8:AllowedLength>", "$I`t</v8:StringQualifiers>", "$I</Type>") -join "`r`n" }
        "n" { return @("$I<Type>", "$I`t<v8:Type>xs:decimal</v8:Type>", "$I`t<v8:NumberQualifiers>", "$I`t`t<v8:Digits>$($Spec.D)</v8:Digits>", "$I`t`t<v8:FractionDigits>$($Spec.F)</v8:FractionDigits>", "$I`t`t<v8:AllowedSign>Any</v8:AllowedSign>", "$I`t</v8:NumberQualifiers>", "$I</Type>") -join "`r`n" }
        "d" { return @("$I<Type>", "$I`t<v8:Type>xs:dateTime</v8:Type>", "$I`t<v8:DateQualifiers>", "$I`t`t<v8:DateFractions>Date</v8:DateFractions>", "$I`t</v8:DateQualifiers>", "$I</Type>") -join "`r`n" }
        "b" { return @("$I<Type>", "$I`t<v8:Type>xs:boolean</v8:Type>", "$I</Type>") -join "`r`n" }
        "cr" { return @("$I<Type>", "$I`t<v8:Type>cfg:CatalogRef.$($Spec.N)</v8:Type>", "$I</Type>") -join "`r`n" }
        "dr" { return @("$I<Type>", "$I`t<v8:Type>cfg:DocumentRef.$($Spec.N)</v8:Type>", "$I</Type>") -join "`r`n" }
        "er" { return @("$I<Type>", "$I`t<v8:Type>cfg:EnumRef.$($Spec.N)</v8:Type>", "$I</Type>") -join "`r`n" }
    }
}

function Field-Spec($Node) {
    @{
        Name = (Safe-FieldName (T $Node "./*[local-name()='n']"))
        Type = (Type-Spec $Node)
        Req = ((T $Node "./*[local-name()='FillRequired']") -eq "true")
        Idx = if ((T $Node "./*[local-name()='Indexing']") -eq "Index") { "Index" } else { "DontIndex" }
    }
}

function Field-Xml([string]$Element, [string]$Seed, $Spec, [bool]$WithIndex = $true, [string]$I = "`t`t") {
    $fc = if ($Spec.Req) { "ShowError" } else { "DontCheck" }
    @(
        "$I<$Element uuid=""$(Stable-Guid $Seed)"">"
        "$I`t<Properties>"
        "$I`t`t<Name>$($Spec.Name)</Name>"
        "$I`t`t<Synonym/>"
        "$I`t`t<Comment/>"
        (Type-Xml $Spec.Type "$I`t`t")
        "$I`t`t<FillChecking>$fc</FillChecking>"
        $(if ($WithIndex) { "$I`t`t<Indexing>$($Spec.Idx)</Indexing>" } else { "" })
        "$I`t</Properties>"
        "$I</$Element>"
    ) -join "`r`n"
}

function TabularSection-Xml($Node, [string]$OwnerKind, [string]$OwnerName, [string]$I = "`t`t`t") {
    $tabName = Safe-FieldName (T $Node "./*[local-name()='n']")
    $child = @()
    foreach ($a in (Ns $Node "./*[local-name()='Attribute']")) {
        $f = Field-Spec $a
        $child += (Field-Xml "Attribute" "$OwnerKind/$OwnerName/TS/$tabName/$($f.Name)" $f $false "$I`t`t")
    }

    $internalInfo = @(
        "$I`t<InternalInfo>"
        "$I`t`t<xr:GeneratedType name=""$($OwnerKind)TabularSection.$OwnerName.$tabName"" category=""TabularSection"">"
        "$I`t`t`t<xr:TypeId>$(Stable-Guid "$OwnerKind/$OwnerName/TS/$tabName/Type")</xr:TypeId>"
        "$I`t`t`t<xr:ValueId>$(Stable-Guid "$OwnerKind/$OwnerName/TS/$tabName/Value")</xr:ValueId>"
        "$I`t`t</xr:GeneratedType>"
        "$I`t`t<xr:GeneratedType name=""$($OwnerKind)TabularSectionRow.$OwnerName.$tabName"" category=""TabularSectionRow"">"
        "$I`t`t`t<xr:TypeId>$(Stable-Guid "$OwnerKind/$OwnerName/TS/$tabName/RowType")</xr:TypeId>"
        "$I`t`t`t<xr:ValueId>$(Stable-Guid "$OwnerKind/$OwnerName/TS/$tabName/RowValue")</xr:ValueId>"
        "$I`t`t</xr:GeneratedType>"
        "$I`t</InternalInfo>"
    ) -join "`r`n"

    $inner = ""
    if ($child.Count -gt 0) {
        $inner = @(
            "$I`t<ChildObjects>"
            ($child -join "`r`n")
            "$I`t</ChildObjects>"
        ) -join "`r`n"
    } else {
        $inner = "$I`t<ChildObjects/>"
    }

    @(
        "$I<TabularSection uuid=""$(Stable-Guid "$OwnerKind/$OwnerName/TS/$tabName")"">"
        $internalInfo
        "$I`t<Properties>"
        "$I`t`t<Name>$tabName</Name>"
        "$I`t`t<Synonym/>"
        "$I`t`t<Comment/>"
        "$I`t</Properties>"
        $inner
        "$I</TabularSection>"
    ) -join "`r`n"
}

function Build-Info([string]$Kind, [string]$Name, [object[]]$Items) {
    if ($Items.Count -eq 0) { return "" }
    $lines = @("`t`t<InternalInfo>")
    foreach ($it in $Items) {
        $seed = "$Kind/$Name/$($it.T)"
        $lines += @(
            "`t`t`t<xr:GeneratedType name=""$($it.T)"" category=""$($it.C)"">"
            "`t`t`t`t<xr:TypeId>$(Stable-Guid "$seed/T")</xr:TypeId>"
            "`t`t`t`t<xr:ValueId>$(Stable-Guid "$seed/V")</xr:ValueId>"
            "`t`t`t</xr:GeneratedType>"
        )
    }
    $lines += "`t`t</InternalInfo>"
    $lines -join "`r`n"
}

function Top-Xml([string]$Tag, [string]$Name, [string]$Internal, [string[]]$Props, $Child = $null) {
    $lines = @(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<MetaDataObject xmlns="http://v8.1c.ru/8.3/MDClasses" xmlns:app="http://v8.1c.ru/8.2/managed-application/core" xmlns:cfg="http://v8.1c.ru/8.1/data/enterprise/current-config" xmlns:cmi="http://v8.1c.ru/8.2/managed-application/cmi" xmlns:ent="http://v8.1c.ru/8.1/data/enterprise" xmlns:lf="http://v8.1c.ru/8.2/managed-application/logform" xmlns:style="http://v8.1c.ru/8.1/data/ui/style" xmlns:sys="http://v8.1c.ru/8.1/data/ui/fonts/system" xmlns:v8="http://v8.1c.ru/8.1/data/core" xmlns:v8ui="http://v8.1c.ru/8.1/data/ui" xmlns:web="http://v8.1c.ru/8.1/data/ui/colors/web" xmlns:win="http://v8.1c.ru/8.1/data/ui/colors/windows" xmlns:xen="http://v8.1c.ru/8.3/xcf/enums" xmlns:xpr="http://v8.1c.ru/8.3/xcf/predef" xmlns:xr="http://v8.1c.ru/8.3/xcf/readable" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="2.20">'
        "`t<$Tag uuid=""$(Stable-Guid "$Tag/$Name")"">"
        $Internal
        "`t`t<Properties>"
        "`t`t`t<Name>$Name</Name>"
        "`t`t`t<Synonym/>"
        "`t`t`t<Comment/>"
        $Props
        "`t`t</Properties>"
    )
    if ($null -ne $Child) {
        $lines += @("`t`t<ChildObjects>", $Child, "`t`t</ChildObjects>")
    }
    $lines += @("`t</$Tag>", "</MetaDataObject>")
    $lines -join "`r`n"
}

Remove-Item -LiteralPath $OutDir -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $RootDir "_stage_empty_dump") -Destination $OutDir -Recurse

$children = @{ Subsystem = @(); Enum = @(); Catalog = @(); Document = @(); DataProcessor = @(); Report = @(); InformationRegister = @(); Role = @(); CommonModule = @() }
$notes = @(
    "Built for Designer import.",
    "Accumulation register is temporarily omitted."
)

foreach ($d in Get-ChildItem (Join-Path $RootDir "Subsystems") -Directory | Sort-Object Name) {
    $n = $d.Name; $children.Subsystem += $n
    Write-Utf8 (Join-Path $OutDir "Subsystems\$n.xml") (Top-Xml "Subsystem" $n "" @() "")
}

foreach ($d in Get-ChildItem (Join-Path $RootDir "Enums") -Directory | Sort-Object Name) {
    $n = $d.Name; $children.Enum += $n; $px = Load-Xml (Join-Path $RootDir "Enums\$n\$n.xml")
    $vals = @()
    foreach ($v in (Ns $px.DocumentElement "./*[local-name()='EnumValue']")) {
        $vn = T $v "./*[local-name()='n']"; $seed = "Enum/$n/$vn"
        $vals += @("`t`t`t<EnumValue uuid=""$(Stable-Guid $seed)"">", "`t`t`t`t<Properties>", "`t`t`t`t`t<Name>$vn</Name>", "`t`t`t`t`t<Synonym/>", "`t`t`t`t`t<Comment/>", "`t`t`t`t</Properties>", "`t`t`t</EnumValue>")
    }
    $gi = Build-Info "Enum" $n @(@{ T = "EnumRef.$n"; C = "Ref" }, @{ T = "EnumManager.$n"; C = "Manager" }, @{ T = "EnumList.$n"; C = "List" })
    Write-Utf8 (Join-Path $OutDir "Enums\$n.xml") (Top-Xml "Enum" $n $gi @("`t`t`t<UseStandardCommands>false</UseStandardCommands>", "`t`t`t<QuickChoice>true</QuickChoice>", "`t`t`t<ChoiceMode>BothWays</ChoiceMode>", "`t`t`t<DefaultListForm/>", "`t`t`t<DefaultChoiceForm/>", "`t`t`t<AuxiliaryListForm/>", "`t`t`t<AuxiliaryChoiceForm/>", "`t`t`t<ListPresentation/>", "`t`t`t<ExtendedListPresentation/>", "`t`t`t<Explanation/>", "`t`t`t<ChoiceHistoryOnInput>Auto</ChoiceHistoryOnInput>") ($vals -join "`r`n"))
}

foreach ($d in Get-ChildItem (Join-Path $RootDir "Catalogs") -Directory | Sort-Object Name) {
    $n = $d.Name; $children.Catalog += $n; $px = Load-Xml (Join-Path $RootDir "Catalogs\$n\$n.xml")
    $c1 = T $px.DocumentElement "./*[local-name()='CodeLength']"; if (-not $c1) { $c1 = "9" }
    $c2 = T $px.DocumentElement "./*[local-name()='DescriptionLength']"; if (-not $c2) { $c2 = "150" }
    $ch = @()
    foreach ($a in (Ns $px.DocumentElement "./*[local-name()='Attribute']")) { $f = Field-Spec $a; $ch += (Field-Xml "Attribute" "Catalog/$n/$($f.Name)" $f) }
    foreach ($t in (Ns $px.DocumentElement "./*[local-name()='TabularSection']")) { $ch += (TabularSection-Xml $t "Catalog" $n) }
    $gi = Build-Info "Catalog" $n @(@{ T = "CatalogObject.$n"; C = "Object" }, @{ T = "CatalogRef.$n"; C = "Ref" }, @{ T = "CatalogSelection.$n"; C = "Selection" }, @{ T = "CatalogList.$n"; C = "List" }, @{ T = "CatalogManager.$n"; C = "Manager" })
    Write-Utf8 (Join-Path $OutDir "Catalogs\$n.xml") (Top-Xml "Catalog" $n $gi @("`t`t`t<Hierarchical>false</Hierarchical>", "`t`t`t<CodeLength>$c1</CodeLength>", "`t`t`t<DescriptionLength>$c2</DescriptionLength>", "`t`t`t<UseStandardCommands>true</UseStandardCommands>") ($ch -join "`r`n"))
}

foreach ($d in Get-ChildItem (Join-Path $RootDir "Documents") -Directory | Sort-Object Name) {
    $n = $d.Name; $children.Document += $n; $px = Load-Xml (Join-Path $RootDir "Documents\$n\$n.xml")
    $ch = @()
    foreach ($a in (Ns $px.DocumentElement "./*[local-name()='Attribute']")) { $f = Field-Spec $a; $ch += (Field-Xml "Attribute" "Document/$n/$($f.Name)" $f) }
    foreach ($t in (Ns $px.DocumentElement "./*[local-name()='TabularSection']")) { $ch += (TabularSection-Xml $t "Document" $n) }
    $gi = Build-Info "Document" $n @(@{ T = "DocumentObject.$n"; C = "Object" }, @{ T = "DocumentRef.$n"; C = "Ref" }, @{ T = "DocumentSelection.$n"; C = "Selection" }, @{ T = "DocumentList.$n"; C = "List" }, @{ T = "DocumentManager.$n"; C = "Manager" })
    Write-Utf8 (Join-Path $OutDir "Documents\$n.xml") (Top-Xml "Document" $n $gi @("`t`t`t<NumberType>String</NumberType>", "`t`t`t<NumberLength>11</NumberLength>", "`t`t`t<NumberPeriodicity>Year</NumberPeriodicity>", "`t`t`t<UseStandardCommands>true</UseStandardCommands>", "`t`t`t<Posting>Allow</Posting>", "`t`t`t<RealTimePosting>Allow</RealTimePosting>", "`t`t`t<RegisterRecordsDeletion>AutoDeleteOnUnpost</RegisterRecordsDeletion>", "`t`t`t<RegisterRecordsWritingOnPost>WriteSelected</RegisterRecordsWritingOnPost>", "`t`t`t<RegisterRecords/>") ($ch -join "`r`n"))

    $docExtDir = Join-Path $RootDir "Documents\$n\Ext"
    if (Test-Path -LiteralPath $docExtDir) {
        Ensure-Dir (Join-Path $OutDir "Documents\$n\Ext")
        foreach ($moduleFile in @("ObjectModule.bsl", "ManagerModule.bsl")) {
            $sourceModule = Join-Path $docExtDir $moduleFile
            if (Test-Path -LiteralPath $sourceModule) {
                $moduleText = [IO.File]::ReadAllText($sourceModule, [Text.Encoding]::UTF8)
                Write-Utf8 (Join-Path $OutDir "Documents\$n\Ext\$moduleFile") (Fix-BslText $moduleText)
            }
        }
    }
}

foreach ($d in Get-ChildItem (Join-Path $RootDir "InformationRegisters") -Directory | Sort-Object Name) {
    $n = $d.Name; $children.InformationRegister += $n; $px = Load-Xml (Join-Path $RootDir "InformationRegisters\$n\$n.xml")
    $ch = @()
    foreach ($a in (Ns $px.DocumentElement "./*[local-name()='Dimension']")) { $f = Field-Spec $a; $ch += (Field-Xml "Dimension" "IR/$n/D/$($f.Name)" $f) }
    foreach ($a in (Ns $px.DocumentElement "./*[local-name()='Resource']")) { $f = Field-Spec $a; $ch += (Field-Xml "Resource" "IR/$n/R/$($f.Name)" $f $false) }
    foreach ($a in (Ns $px.DocumentElement "./*[local-name()='Attribute']")) { $f = Field-Spec $a; $ch += (Field-Xml "Attribute" "IR/$n/A/$($f.Name)" $f) }
    if ($ch.Count -eq 0) {
        $tmp = @{ Name = "ТехническийРеквизит"; Type = @{ K = "s"; L = 20 }; Req = $false; Idx = "DontIndex" }
        $ch += (Field-Xml "Attribute" "IR/$n/T" $tmp)
    }
    $gi = Build-Info "InformationRegister" $n @(@{ T = "InformationRegisterRecord.$n"; C = "Record" }, @{ T = "InformationRegisterManager.$n"; C = "Manager" }, @{ T = "InformationRegisterSelection.$n"; C = "Selection" }, @{ T = "InformationRegisterList.$n"; C = "List" }, @{ T = "InformationRegisterRecordSet.$n"; C = "RecordSet" }, @{ T = "InformationRegisterRecordKey.$n"; C = "RecordKey" }, @{ T = "InformationRegisterRecordManager.$n"; C = "RecordManager" })
    $periodicity = T $px.DocumentElement "./*[local-name()='Periodicity']"
    if (-not $periodicity) { $periodicity = "None" }
    $writeMode = T $px.DocumentElement "./*[local-name()='WriteMode']"
    if (-not $writeMode) { $writeMode = "Independent" }
    Write-Utf8 (Join-Path $OutDir "InformationRegisters\$n.xml") (Top-Xml "InformationRegister" $n $gi @("`t`t`t<InformationRegisterPeriodicity>$periodicity</InformationRegisterPeriodicity>", "`t`t`t<WriteMode>$writeMode</WriteMode>", "`t`t`t<UseStandardCommands>true</UseStandardCommands>") ($ch -join "`r`n"))
}

foreach ($d in Get-ChildItem (Join-Path $RootDir "Roles") -Directory | Sort-Object Name) {
    $n = $d.Name; $children.Role += $n
    Write-Utf8 (Join-Path $OutDir "Roles\$n.xml") (Top-Xml "Role" $n "" @())
}

foreach ($d in Get-ChildItem (Join-Path $RootDir "CommonModules") -Directory | Sort-Object Name) {
    $n = $d.Name; $children.CommonModule += $n
    Write-Utf8 (Join-Path $OutDir "CommonModules\$n.xml") (Top-Xml "CommonModule" $n "" @("`t`t`t<Global>false</Global>", "`t`t`t<ClientManagedApplication>true</ClientManagedApplication>", "`t`t`t<Server>true</Server>", "`t`t`t<ExternalConnection>true</ExternalConnection>", "`t`t`t<ClientOrdinaryApplication>false</ClientOrdinaryApplication>", "`t`t`t<ServerCall>false</ServerCall>", "`t`t`t<Privileged>false</Privileged>", "`t`t`t<ReturnValuesReuse>DontUse</ReturnValuesReuse>"))
    if (Test-Path (Join-Path $RootDir "CommonModules\$n\$n.bsl")) {
        $moduleText = [IO.File]::ReadAllText((Join-Path $RootDir "CommonModules\$n\$n.bsl"), [Text.Encoding]::UTF8)
        Write-Utf8 (Join-Path $OutDir "CommonModules\$n.bsl") (Fix-BslText $moduleText)
    }
}

foreach ($d in Get-ChildItem (Join-Path $RootDir "Reports") -Directory | Sort-Object Name) {
    $n = $d.Name; $children.Report += $n
    $gi = Build-Info "Report" $n @(@{ T = "ReportObject.$n"; C = "Object" }, @{ T = "ReportManager.$n"; C = "Manager" })
    Write-Utf8 (Join-Path $OutDir "Reports\$n.xml") (Top-Xml "Report" $n $gi @("`t`t`t<UseStandardCommands>true</UseStandardCommands>") "")
    if (Test-Path (Join-Path $RootDir "Reports\$n\$n.bsl")) { Copy-Item (Join-Path $RootDir "Reports\$n\$n.bsl") (Join-Path $OutDir "Reports\$n.bsl") -Force }
}

foreach ($d in Get-ChildItem (Join-Path $RootDir "DataProcessors") -Directory | Sort-Object Name) {
    $n = $d.Name; $children.DataProcessor += $n
    $gi = Build-Info "DataProcessor" $n @(@{ T = "DataProcessorObject.$n"; C = "Object" }, @{ T = "DataProcessorManager.$n"; C = "Manager" })
    Write-Utf8 (Join-Path $OutDir "DataProcessors\$n.xml") (Top-Xml "DataProcessor" $n $gi @("`t`t`t<UseStandardCommands>true</UseStandardCommands>") "")
    if (Test-Path (Join-Path $RootDir "DataProcessors\$n\$n.bsl")) { Copy-Item (Join-Path $RootDir "DataProcessors\$n\$n.bsl") (Join-Path $OutDir "DataProcessors\$n.bsl") -Force }
}

$cfgPath = Join-Path $OutDir "Configuration.xml"
$cfgText = [IO.File]::ReadAllText($cfgPath, [Text.Encoding]::UTF8)
$co = @("`t`t<Language>Русский</Language>")
$co = @("`t`t<Language>Русский</Language>")
$langName = [string]::Concat([char]0x420, [char]0x443, [char]0x441, [char]0x441, [char]0x43A, [char]0x438, [char]0x439)
$co = @("`t`t<Language>$langName</Language>")
foreach ($t in "Subsystem", "Enum", "Catalog", "Document", "DataProcessor", "Report", "InformationRegister", "Role", "CommonModule") {
    foreach ($n in ($children[$t] | Sort-Object)) { $co += "`t`t<$t>$n</$t>" }
}
$cfgText = [Text.RegularExpressions.Regex]::Replace($cfgText, "<ChildObjects>[\s\S]*?</ChildObjects>", "<ChildObjects>`r`n$($co -join "`r`n")`r`n`t</ChildObjects>", [Text.RegularExpressions.RegexOptions]::Singleline)
$cfgText = [Text.RegularExpressions.Regex]::Replace($cfgText, "<Language>.*?</Language>", "<Language>$langName</Language>", [Text.RegularExpressions.RegexOptions]::Singleline)
$cfgText = [Text.RegularExpressions.Regex]::Replace($cfgText, "<DefaultRoles\s*/>", "<DefaultRoles>`r`n`t`t`t<Role>Role.ПолныеПрава</Role>`r`n`t`t</DefaultRoles>", [Text.RegularExpressions.RegexOptions]::Singleline)
Write-Utf8 $cfgPath $cfgText
Write-Utf8 (Join-Path $OutDir "_conversion_notes.txt") ($notes -join "`r`n")

$fullRightsTemplatePath = Get-FullRightsTemplatePath $RootDir
$fullRightsContent = Build-FullRightsContent $fullRightsTemplatePath
if ($fullRightsContent) {
    $roleFilePrefix = [string]::Concat([char]0x420, [char]0x43E, [char]0x43B, [char]0x44C, [char]0x2E)
    $roleFileSuffix = [string]::Concat([char]0x2E, [char]0x41F, [char]0x440, [char]0x430, [char]0x432, [char]0x430, [char]0x2E, [char]0x78, [char]0x6D, [char]0x6C)
    foreach ($roleName in ($children.Role | Sort-Object -Unique)) {
        $roleFileName = [string]::Concat($roleFilePrefix, $roleName, $roleFileSuffix)
        Write-Utf8 (Join-Path $OutDir $roleFileName) $fullRightsContent
    }
}

$uiScript = Join-Path $PSScriptRoot "add_user_forms_to_dump.ps1"
if (Test-Path -LiteralPath $uiScript) {
    & $uiScript -RootDir $RootDir -DumpDir $OutDir | Out-Null
}

[pscustomobject]@{
    OutputDir = $OutDir
    Enums = $children.Enum.Count
    Catalogs = $children.Catalog.Count
    Documents = $children.Document.Count
    InformationRegisters = $children.InformationRegister.Count
    Roles = $children.Role.Count
    CommonModules = $children.CommonModule.Count
    Reports = $children.Report.Count
    DataProcessors = $children.DataProcessor.Count
    Subsystems = $children.Subsystem.Count
    DefaultRole = "Role.ПолныеПрава"
    RightsTemplate = $fullRightsTemplatePath
} | Format-List
