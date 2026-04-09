param(
    [string]$RootDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    Ensure-Directory -Path (Split-Path -Parent $Path)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content.Trim() + "`r`n", $encoding)
}

function Get-StableGuid {
    param([string]$Seed)

    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
        $hash = $md5.ComputeHash($bytes)
        return ([guid]::new($hash)).ToString()
    } finally {
        $md5.Dispose()
    }
}

function New-SynonymXml {
    param(
        [string]$Text,
        [string]$Indent = "`t"
    )

    return "$Indent<mdclass:Synonym><core:item><core:lang>ru</core:lang><core:content>$Text</core:content></core:item></mdclass:Synonym>"
}

function New-TypeSpecString { param([int]$Length) return @{ Kind = "string"; Length = $Length } }
function New-TypeSpecNumber { param([int]$Digits, [int]$FractionDigits = 0) return @{ Kind = "number"; Digits = $Digits; FractionDigits = $FractionDigits } }
function New-TypeSpecDate { return @{ Kind = "date" } }
function New-TypeSpecBoolean { return @{ Kind = "boolean" } }
function New-TypeSpecCatalogRef { param([string]$Name) return @{ Kind = "catalogref"; Name = $Name } }
function New-TypeSpecDocumentRef { param([string]$Name) return @{ Kind = "documentref"; Name = $Name } }
function New-TypeSpecEnumRef { param([string]$Name) return @{ Kind = "enumref"; Name = $Name } }

function New-TypeXml {
    param(
        [hashtable]$TypeSpec,
        [string]$Indent = "`t`t"
    )

    switch ($TypeSpec.Kind) {
        "string" {
            return "$Indent<mdclass:Type>xsd:string</mdclass:Type><mdclass:StringQualifiers><mdclass:Length>$($TypeSpec.Length)</mdclass:Length><mdclass:AllowedLength>Variable</mdclass:AllowedLength></mdclass:StringQualifiers>"
        }
        "number" {
            return "$Indent<mdclass:Type>xsd:decimal</mdclass:Type><mdclass:NumberQualifiers><mdclass:Digits>$($TypeSpec.Digits)</mdclass:Digits><mdclass:FractionDigits>$($TypeSpec.FractionDigits)</mdclass:FractionDigits></mdclass:NumberQualifiers>"
        }
        "date" { return "$Indent<mdclass:Type>xsd:date</mdclass:Type>" }
        "boolean" { return "$Indent<mdclass:Type>xsd:boolean</mdclass:Type>" }
        "catalogref" { return "$Indent<mdclass:Type>CatalogRef.$($TypeSpec.Name)</mdclass:Type>" }
        "documentref" { return "$Indent<mdclass:Type>DocumentRef.$($TypeSpec.Name)</mdclass:Type>" }
        "enumref" { return "$Indent<mdclass:Type>EnumRef.$($TypeSpec.Name)</mdclass:Type>" }
        default { throw "Unsupported type kind: $($TypeSpec.Kind)" }
    }
}

function New-FieldXml {
    param(
        [string]$ElementName,
        [string]$ObjectSeed,
        [hashtable]$FieldSpec,
        [string]$Indent = "`t"
    )

    $fieldGuid = Get-StableGuid "$ObjectSeed/$ElementName/$($FieldSpec.Name)"
    $indexing = if ($FieldSpec.ContainsKey("Indexing")) { $FieldSpec.Indexing } elseif ($FieldSpec.ContainsKey("Index")) { if ($FieldSpec.Index) { "Index" } else { $null } } else { $null }
    $lines = @()
    $lines += "$Indent<mdclass:$ElementName uuid=""$fieldGuid"">"
    $lines += "$Indent`t<mdclass:n>$($FieldSpec.Name)</mdclass:n>"
    $lines += (New-SynonymXml -Text $FieldSpec.Synonym -Indent "$Indent`t")
    $lines += (New-TypeXml -TypeSpec $FieldSpec.Type -Indent "$Indent`t")

    if ($FieldSpec.ContainsKey("FillRequired")) {
        $fillValue = if ($FieldSpec.FillRequired) { "true" } else { "false" }
        $lines += "$Indent`t<mdclass:FillRequired>$fillValue</mdclass:FillRequired>"
    }

    if ($indexing) {
        $lines += "$Indent`t<mdclass:Indexing>$indexing</mdclass:Indexing>"
    }

    $lines += "$Indent</mdclass:$ElementName>"
    return ($lines -join "`r`n")
}

function New-TabularSectionXml {
    param(
        [string]$ObjectSeed,
        [hashtable]$TabularSection,
        [string]$Indent = "`t"
    )

    $sectionGuid = Get-StableGuid "$ObjectSeed/TabularSection/$($TabularSection.Name)"
    $lines = @()
    $lines += "$Indent<mdclass:TabularSection uuid=""$sectionGuid"">"
    $lines += "$Indent`t<mdclass:n>$($TabularSection.Name)</mdclass:n>"
    $lines += (New-SynonymXml -Text $TabularSection.Synonym -Indent "$Indent`t")

    foreach ($attribute in $TabularSection.Attributes) {
        $lines += (New-FieldXml -ElementName "Attribute" -ObjectSeed "$ObjectSeed/TabularSection/$($TabularSection.Name)" -FieldSpec $attribute -Indent "$Indent`t")
    }

    $lines += "$Indent</mdclass:TabularSection>"
    return ($lines -join "`r`n")
}

function New-XmlDocument {
    param(
        [string]$TypeName,
        [string]$Name,
        [string]$Synonym,
        [string[]]$BodyLines
    )

    $uuid = Get-StableGuid "$TypeName/$Name"
    $lines = @()
    $lines += '<?xml version="1.0" encoding="UTF-8"?>'
    $lines += "<mdclass:$TypeName xmlns:mdclass=""http://v8.1c.ru/8.3/MDClasses"" xmlns:core=""http://v8.1c.ru/8.1/data/core"" xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xsi:type=""mdclass:$TypeName"" uuid=""$uuid"">"
    $lines += "`t<mdclass:n>$Name</mdclass:n>"
    $lines += (New-SynonymXml -Text $Synonym)
    $lines += $BodyLines
    $lines += "</mdclass:$TypeName>"
    return ($lines -join "`r`n")
}

function Write-Enum {
    param([hashtable]$Definition)

    $body = @("`t<mdclass:UseStandardCommands>true</mdclass:UseStandardCommands>")
    foreach ($value in $Definition.Values) {
        $valueGuid = Get-StableGuid "Enum/$($Definition.Name)/$($value.Name)"
        $body += @(
            "`t<mdclass:EnumValue uuid=""$valueGuid"">",
            "`t`t<mdclass:n>$($value.Name)</mdclass:n>",
            (New-SynonymXml -Text $value.Synonym -Indent "`t`t"),
            "`t</mdclass:EnumValue>"
        )
    }

    $content = New-XmlDocument -TypeName "Enum" -Name $Definition.Name -Synonym $Definition.Synonym -BodyLines $body
    $path = Join-Path $RootDir "Enums\$($Definition.Name)\$($Definition.Name).xml"
    Write-Utf8NoBom -Path $path -Content $content
}

function Write-Catalog {
    param([hashtable]$Definition)

    $body = @(
        "`t<mdclass:Hierarchical>false</mdclass:Hierarchical>",
        "`t<mdclass:CodeLength>$($Definition.CodeLength)</mdclass:CodeLength>",
        "`t<mdclass:DescriptionLength>$($Definition.DescriptionLength)</mdclass:DescriptionLength>",
        "`t<mdclass:UseStandardCommands>true</mdclass:UseStandardCommands>"
    )

    foreach ($attribute in $Definition.Attributes) {
        $body += (New-FieldXml -ElementName "Attribute" -ObjectSeed "Catalog/$($Definition.Name)" -FieldSpec $attribute)
    }

    if ($Definition.ContainsKey("TabularSections")) {
        foreach ($tabularSection in $Definition.TabularSections) {
            $body += (New-TabularSectionXml -ObjectSeed "Catalog/$($Definition.Name)" -TabularSection $tabularSection)
        }
    }

    $content = New-XmlDocument -TypeName "Catalog" -Name $Definition.Name -Synonym $Definition.Synonym -BodyLines $body
    $path = Join-Path $RootDir "Catalogs\$($Definition.Name)\$($Definition.Name).xml"
    Write-Utf8NoBom -Path $path -Content $content
}

function Write-DocumentMetadata {
    param([hashtable]$Definition)

    $body = @(
        "`t<mdclass:NumberLength>11</mdclass:NumberLength>",
        "`t<mdclass:NumberType>String</mdclass:NumberType>",
        "`t<mdclass:NumberPeriodicity>Year</mdclass:NumberPeriodicity>",
        "`t<mdclass:UseStandardCommands>true</mdclass:UseStandardCommands>"
    )

    foreach ($attribute in $Definition.Attributes) {
        $body += (New-FieldXml -ElementName "Attribute" -ObjectSeed "Document/$($Definition.Name)" -FieldSpec $attribute)
    }

    foreach ($tabularSection in $Definition.TabularSections) {
        $body += (New-TabularSectionXml -ObjectSeed "Document/$($Definition.Name)" -TabularSection $tabularSection)
    }

    $content = New-XmlDocument -TypeName "Document" -Name $Definition.Name -Synonym $Definition.Synonym -BodyLines $body
    $path = Join-Path $RootDir "Documents\$($Definition.Name)\$($Definition.Name).xml"
    Write-Utf8NoBom -Path $path -Content $content
}

function Write-InformationRegisterMetadata {
    param([hashtable]$Definition)

    $body = @(
        "`t<mdclass:Periodicity>Second</mdclass:Periodicity>",
        "`t<mdclass:WriteMode>Independent</mdclass:WriteMode>",
        "`t<mdclass:UseStandardCommands>true</mdclass:UseStandardCommands>"
    )

    foreach ($dimension in $Definition.Dimensions) {
        $body += (New-FieldXml -ElementName "Dimension" -ObjectSeed "InformationRegister/$($Definition.Name)" -FieldSpec $dimension)
    }

    foreach ($resource in $Definition.Resources) {
        $body += (New-FieldXml -ElementName "Resource" -ObjectSeed "InformationRegister/$($Definition.Name)" -FieldSpec $resource)
    }

    foreach ($attribute in $Definition.Attributes) {
        $body += (New-FieldXml -ElementName "Attribute" -ObjectSeed "InformationRegister/$($Definition.Name)" -FieldSpec $attribute)
    }

    $content = New-XmlDocument -TypeName "InformationRegister" -Name $Definition.Name -Synonym $Definition.Synonym -BodyLines $body
    $path = Join-Path $RootDir "InformationRegisters\$($Definition.Name)\$($Definition.Name).xml"
    Write-Utf8NoBom -Path $path -Content $content
}

function Write-Role {
    param([string]$Name, [string]$Synonym)

    $content = New-XmlDocument -TypeName "Role" -Name $Name -Synonym $Synonym -BodyLines @()
    $path = Join-Path $RootDir "Roles\$Name\$Name.xml"
    Write-Utf8NoBom -Path $path -Content $content
}

function Write-CommonModule {
    param(
        [string]$Name,
        [string]$Synonym,
        [string]$ModuleBody
    )

    $body = @(
        "`t<mdclass:Global>false</mdclass:Global>",
        "`t<mdclass:ClientManagedApplication>true</mdclass:ClientManagedApplication>",
        "`t<mdclass:Server>true</mdclass:Server>",
        "`t<mdclass:ExternalConnection>true</mdclass:ExternalConnection>"
    )

    $content = New-XmlDocument -TypeName "CommonModule" -Name $Name -Synonym $Synonym -BodyLines $body
    $basePath = Join-Path $RootDir "CommonModules\$Name"
    Write-Utf8NoBom -Path (Join-Path $basePath "$Name.xml") -Content $content
    Write-Utf8NoBom -Path (Join-Path $basePath "$Name.bsl") -Content $ModuleBody
}

function Write-Report {
    param([string]$Name, [string]$Synonym)

    $content = New-XmlDocument -TypeName "Report" -Name $Name -Synonym $Synonym -BodyLines @(
        "`t<mdclass:UseStandardCommands>true</mdclass:UseStandardCommands>"
    )

    $path = Join-Path $RootDir "Reports\$Name\$Name.xml"
    Write-Utf8NoBom -Path $path -Content $content
}

function Write-DataProcessor {
    param(
        [string]$Name,
        [string]$Synonym,
        [string]$ModuleBody
    )

    $content = New-XmlDocument -TypeName "DataProcessor" -Name $Name -Synonym $Synonym -BodyLines @(
        "`t<mdclass:UseStandardCommands>true</mdclass:UseStandardCommands>"
    )

    $basePath = Join-Path $RootDir "DataProcessors\$Name"
    Write-Utf8NoBom -Path (Join-Path $basePath "$Name.xml") -Content $content
    Write-Utf8NoBom -Path (Join-Path $basePath "$Name.bsl") -Content $ModuleBody
}

function Write-Subsystem {
    param([string]$Name, [string]$Synonym)

    $content = New-XmlDocument -TypeName "Subsystem" -Name $Name -Synonym $Synonym -BodyLines @()
    $path = Join-Path $RootDir "Subsystems\$Name\$Name.xml"
    Write-Utf8NoBom -Path $path -Content $content
}

function Insert-BeforeClosingTag {
    param(
        [string]$Path,
        [string]$TagName,
        [string]$Fragment,
        [string]$Marker
    )

    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ($content.Contains($Marker)) {
        return
    }

    $updated = $content.Replace("</mdclass:$TagName>", "$Fragment`r`n</mdclass:$TagName>")
    Write-Utf8NoBom -Path $Path -Content $updated
}

function Insert-BeforeMarker {
    param(
        [string]$Path,
        [string]$SearchMarker,
        [string]$Fragment,
        [string]$Marker
    )

    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ($content.Contains($Marker)) {
        return
    }

    $updated = $content.Replace($SearchMarker, "$Fragment`r`n$SearchMarker")
    Write-Utf8NoBom -Path $Path -Content $updated
}

function Replace-Once {
    param(
        [string]$Path,
        [string]$OldValue,
        [string]$NewValue
    )

    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if (-not $content.Contains($OldValue)) {
        return
    }

    $updated = $content.Replace($OldValue, $NewValue)
    Write-Utf8NoBom -Path $Path -Content $updated
}

function Sync-ConfigurationChildObjects {
    $folderMap = @(
        @{ Folder = "Subsystems"; Element = "Subsystem" },
        @{ Folder = "Enums"; Element = "Enum" },
        @{ Folder = "Catalogs"; Element = "Catalog" },
        @{ Folder = "Documents"; Element = "Document" },
        @{ Folder = "DataProcessors"; Element = "DataProcessor" },
        @{ Folder = "Reports"; Element = "Report" },
        @{ Folder = "InformationRegisters"; Element = "InformationRegister" },
        @{ Folder = "AccumulationRegisters"; Element = "AccumulationRegister" },
        @{ Folder = "Roles"; Element = "Role" },
        @{ Folder = "CommonModules"; Element = "CommonModule" }
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("`t<mdclass:ChildObjects>")

    foreach ($entry in $folderMap) {
        $folderPath = Join-Path $RootDir $entry.Folder
        if (-not (Test-Path -LiteralPath $folderPath)) {
            continue
        }

        Get-ChildItem -LiteralPath $folderPath -Directory |
            Sort-Object Name |
            ForEach-Object {
                $lines.Add("`t`t<mdclass:$($entry.Element)>$($entry.Element).$($_.Name)</mdclass:$($entry.Element)>")
            }
    }

    $lines.Add("`t</mdclass:ChildObjects>")
    $childObjectsBlock = [string]::Join("`r`n", $lines)

    $configPath = Join-Path $RootDir "Configuration.xml"
    $content = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)
    $updated = [System.Text.RegularExpressions.Regex]::Replace(
        $content,
        '<mdclass:ChildObjects>[\s\S]*?</mdclass:ChildObjects>',
        $childObjectsBlock,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    Write-Utf8NoBom -Path $configPath -Content $updated
}

$enums = @(
    @{
        Name = "Р РѕР»СЊРџРѕР»СЊР·РѕРІР°С‚РµР»СЏ"
        Synonym = "Р РѕР»СЊ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ"
        Values = @(
            @{ Name = "РњРµРЅРµРґР¶РµСЂ"; Synonym = "РњРµРЅРµРґР¶РµСЂ РїРѕ РїСЂРѕРґР°Р¶Р°Рј" },
            @{ Name = "Р›РѕРіРёСЃС‚"; Synonym = "Р›РѕРіРёСЃС‚" },
            @{ Name = "Р¤РёРЅР°РЅСЃРёСЃС‚"; Synonym = "Р¤РёРЅР°РЅСЃРёСЃС‚ / Р±СѓС…РіР°Р»С‚РµСЂ" },
            @{ Name = "Р СѓРєРѕРІРѕРґРёС‚РµР»СЊ"; Synonym = "Р СѓРєРѕРІРѕРґРёС‚РµР»СЊ" },
            @{ Name = "РђРґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂ"; Synonym = "РђРґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂ" }
        )
    },
    @{
        Name = "РўРёРїРЈРІРµРґРѕРјР»РµРЅРёСЏ"
        Synonym = "РўРёРї СѓРІРµРґРѕРјР»РµРЅРёСЏ"
        Values = @(
            @{ Name = "РР·РјРµРЅРµРЅРёРµРЎС‚Р°С‚СѓСЃР°"; Synonym = "РР·РјРµРЅРµРЅРёРµ СЃС‚Р°С‚СѓСЃР°" },
            @{ Name = "РџСЂРѕСЃСЂРѕС‡РєР°РћРїР»Р°С‚С‹"; Synonym = "РџСЂРѕСЃСЂРѕС‡РєР° РѕРїР»Р°С‚С‹" },
            @{ Name = "Р—Р°РґРµСЂР¶РєР°Р”РѕСЃС‚Р°РІРєРё"; Synonym = "Р—Р°РґРµСЂР¶РєР° РґРѕСЃС‚Р°РІРєРё" },
            @{ Name = "РќРµС‚Р”РѕРєСѓРјРµРЅС‚Р°"; Synonym = "РќРµС‚ РґРѕРєСѓРјРµРЅС‚Р°" }
        )
    },
    @{
        Name = "РўРёРїРњР°СЂС€СЂСѓС‚РЅРѕР№РўРѕС‡РєРё"
        Synonym = "РўРёРї РјР°СЂС€СЂСѓС‚РЅРѕР№ С‚РѕС‡РєРё"
        Values = @(
            @{ Name = "РџРѕСЃС‚Р°РІС‰РёРє"; Synonym = "РџРѕСЃС‚Р°РІС‰РёРє" },
            @{ Name = "РЎРєР»Р°Рґ"; Synonym = "РЎРєР»Р°Рґ" },
            @{ Name = "РўР°РјРѕР¶РЅСЏ"; Synonym = "РўР°РјРѕР¶РЅСЏ" },
            @{ Name = "РўСЂР°РЅСЃРїРѕСЂС‚РЅР°СЏРљРѕРјРїР°РЅРёСЏ"; Synonym = "РўСЂР°РЅСЃРїРѕСЂС‚РЅР°СЏ РєРѕРјРїР°РЅРёСЏ" },
            @{ Name = "РљР»РёРµРЅС‚"; Synonym = "РљР»РёРµРЅС‚" }
        )
    },
    @{
        Name = "РўРёРїРЎРѕР±С‹С‚РёСЏРўСЂРµРєРёРЅРіР°"
        Synonym = "РўРёРї СЃРѕР±С‹С‚РёСЏ С‚СЂРµРєРёРЅРіР°"
        Values = @(
            @{ Name = "РЎРѕР·РґР°РЅРѕ"; Synonym = "РЎРѕР·РґР°РЅРѕ" },
            @{ Name = "РџСЂРёРЅСЏС‚РѕРљРџРµСЂРµРІРѕР·РєРµ"; Synonym = "РџСЂРёРЅСЏС‚Рѕ Рє РїРµСЂРµРІРѕР·РєРµ" },
            @{ Name = "РќР°РњР°СЂС€СЂСѓС‚Рµ"; Synonym = "РќР° РјР°СЂС€СЂСѓС‚Рµ" },
            @{ Name = "РќР°РўР°РјРѕР¶РЅРµ"; Synonym = "РќР° С‚Р°РјРѕР¶РЅРµ" },
            @{ Name = "Р”РѕСЃС‚Р°РІР»РµРЅРѕ"; Synonym = "Р”РѕСЃС‚Р°РІР»РµРЅРѕ" }
        )
    }
)

$catalogs = @(
    @{
        Name = "РўР°СЂРёС„С‹Р”РѕСЃС‚Р°РІРєРё"
        Synonym = "РўР°СЂРёС„С‹ РґРѕСЃС‚Р°РІРєРё"
        CodeLength = 9
        DescriptionLength = 150
        Attributes = @(
            @{ Name = "РџРµСЂРµРІРѕР·С‡РёРє"; Synonym = "РџРµСЂРµРІРѕР·С‡РёРє"; Type = (New-TypeSpecCatalogRef "РџРµСЂРµРІРѕР·С‡РёРєРё"); FillRequired = $false; Index = $true },
            @{ Name = "РњР°СЂС€СЂСѓС‚Р”РѕСЃС‚Р°РІРєРё"; Synonym = "РњР°СЂС€СЂСѓС‚ РґРѕСЃС‚Р°РІРєРё"; Type = (New-TypeSpecCatalogRef "РњР°СЂС€СЂСѓС‚С‹Р”РѕСЃС‚Р°РІРєРё"); FillRequired = $false; Index = $true },
            @{ Name = "РўРёРїР”РѕСЃС‚Р°РІРєРё"; Synonym = "РўРёРї РґРѕСЃС‚Р°РІРєРё"; Type = (New-TypeSpecEnumRef "РўРёРїР”РѕСЃС‚Р°РІРєРё"); FillRequired = $false; Index = $true },
            @{ Name = "РњРµС‚РѕРґР Р°СЃС‡РµС‚Р°"; Synonym = "РњРµС‚РѕРґ СЂР°СЃС‡РµС‚Р°"; Type = (New-TypeSpecEnumRef "РњРµС‚РѕРґР Р°СЃС‡РµС‚Р°Р”РѕСЃС‚Р°РІРєРё"); FillRequired = $true; Index = $true },
            @{ Name = "Р’Р°Р»СЋС‚Р°"; Synonym = "Р’Р°Р»СЋС‚Р°"; Type = (New-TypeSpecString 3); FillRequired = $true; Index = $true },
            @{ Name = "РўР°СЂРёС„Р—Р°РљРі"; Synonym = "РўР°СЂРёС„ Р·Р° РєРі"; Type = (New-TypeSpecNumber 15 2); FillRequired = $false },
            @{ Name = "РўР°СЂРёС„Р¤Р°РєС‚"; Synonym = "РўР°СЂРёС„ С„Р°РєС‚"; Type = (New-TypeSpecNumber 15 2); FillRequired = $false },
            @{ Name = "РўР°СЂРёС„РћР±СЉРµРј"; Synonym = "РўР°СЂРёС„ РѕР±СЉРµРј"; Type = (New-TypeSpecNumber 15 2); FillRequired = $false },
            @{ Name = "Р¤РёРєСЃРЎР±РѕСЂ"; Synonym = "Р¤РёРєСЃРёСЂРѕРІР°РЅРЅС‹Р№ СЃР±РѕСЂ"; Type = (New-TypeSpecNumber 15 2); FillRequired = $false },
            @{ Name = "РљРѕСЌС„"; Synonym = "РљРѕСЌС„С„РёС†РёРµРЅС‚"; Type = (New-TypeSpecNumber 15 6); FillRequired = $false },
            @{ Name = "РљРѕСЌС„РћР±СЉРµРјРЅРѕРіРѕР’РµСЃР°"; Synonym = "РљРѕСЌС„. РѕР±СЉРµРјРЅРѕРіРѕ РІРµСЃР°"; Type = (New-TypeSpecNumber 15 2); FillRequired = $false },
            @{ Name = "РњРёРЅРёРјР°Р»СЊРЅС‹Р№Р’РµСЃРљРі"; Synonym = "РњРёРЅРёРјР°Р»СЊРЅС‹Р№ РІРµСЃ РєРі"; Type = (New-TypeSpecNumber 15 3); FillRequired = $false },
            @{ Name = "РўСЂРµР±СѓРµС‚РўР°РјРѕР¶РЅСЋ"; Synonym = "РўСЂРµР±СѓРµС‚ С‚Р°РјРѕР¶РЅСЋ"; Type = (New-TypeSpecBoolean); FillRequired = $false },
            @{ Name = "РЎРѕРїСѓС‚СЃС‚РІСѓСЋС‰РёРµР Р°СЃС…РѕРґС‹РџСЂРѕС†РµРЅС‚"; Synonym = "РЎРѕРїСѓС‚СЃС‚РІСѓСЋС‰РёРµ СЂР°СЃС…РѕРґС‹ %"; Type = (New-TypeSpecNumber 5 2); FillRequired = $false },
            @{ Name = "Р”Р°С‚Р°РќР°С‡Р°Р»Р°Р”РµР№СЃС‚РІРёСЏ"; Synonym = "Р”Р°С‚Р° РЅР°С‡Р°Р»Р° РґРµР№СЃС‚РІРёСЏ"; Type = (New-TypeSpecDate); FillRequired = $false; Index = $true },
            @{ Name = "Р”Р°С‚Р°РћРєРѕРЅС‡Р°РЅРёСЏР”РµР№СЃС‚РІРёСЏ"; Synonym = "Р”Р°С‚Р° РѕРєРѕРЅС‡Р°РЅРёСЏ РґРµР№СЃС‚РІРёСЏ"; Type = (New-TypeSpecDate); FillRequired = $false; Index = $true },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
    },
    @{
        Name = "РњР°СЂС€СЂСѓС‚С‹Р”РѕСЃС‚Р°РІРєРё"
        Synonym = "РњР°СЂС€СЂСѓС‚С‹ РґРѕСЃС‚Р°РІРєРё"
        CodeLength = 9
        DescriptionLength = 150
        Attributes = @(
            @{ Name = "РџРµСЂРµРІРѕР·С‡РёРє"; Synonym = "РџРµСЂРµРІРѕР·С‡РёРє"; Type = (New-TypeSpecCatalogRef "РџРµСЂРµРІРѕР·С‡РёРєРё"); FillRequired = $false; Index = $true },
            @{ Name = "РЎС‚СЂР°РЅР°РћС‚РїСЂР°РІР»РµРЅРёСЏ"; Synonym = "РЎС‚СЂР°РЅР° РѕС‚РїСЂР°РІР»РµРЅРёСЏ"; Type = (New-TypeSpecString 100); FillRequired = $false; Index = $true },
            @{ Name = "РЎС‚СЂР°РЅР°РќР°Р·РЅР°С‡РµРЅРёСЏ"; Synonym = "РЎС‚СЂР°РЅР° РЅР°Р·РЅР°С‡РµРЅРёСЏ"; Type = (New-TypeSpecString 100); FillRequired = $false; Index = $true },
            @{ Name = "РўРёРїР”РѕСЃС‚Р°РІРєРё"; Synonym = "РўРёРї РґРѕСЃС‚Р°РІРєРё"; Type = (New-TypeSpecEnumRef "РўРёРїР”РѕСЃС‚Р°РІРєРё"); FillRequired = $false; Index = $true },
            @{ Name = "РќРѕСЂРјР°С‚РёРІР”РЅРµР№"; Synonym = "РќРѕСЂРјР°С‚РёРІ РґРЅРµР№"; Type = (New-TypeSpecNumber 10 0); FillRequired = $false },
            @{ Name = "РСЃРїРѕР»СЊР·РѕРІР°С‚СЊРџРѕРЈРјРѕР»С‡Р°РЅРёСЋ"; Synonym = "РСЃРїРѕР»СЊР·РѕРІР°С‚СЊ РїРѕ СѓРјРѕР»С‡Р°РЅРёСЋ"; Type = (New-TypeSpecBoolean); FillRequired = $false },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
    },
    @{
        Name = "РўРѕС‡РєРёРњР°СЂС€СЂСѓС‚Р°"
        Synonym = "РўРѕС‡РєРё РјР°СЂС€СЂСѓС‚Р°"
        CodeLength = 9
        DescriptionLength = 150
        Attributes = @(
            @{ Name = "РњР°СЂС€СЂСѓС‚Р”РѕСЃС‚Р°РІРєРё"; Synonym = "РњР°СЂС€СЂСѓС‚ РґРѕСЃС‚Р°РІРєРё"; Type = (New-TypeSpecCatalogRef "РњР°СЂС€СЂСѓС‚С‹Р”РѕСЃС‚Р°РІРєРё"); FillRequired = $true; Index = $true },
            @{ Name = "РџРѕСЂСЏРґРѕРє"; Synonym = "РџРѕСЂСЏРґРѕРє"; Type = (New-TypeSpecNumber 10 0); FillRequired = $true; Index = $true },
            @{ Name = "РўРёРїРўРѕС‡РєРё"; Synonym = "РўРёРї С‚РѕС‡РєРё"; Type = (New-TypeSpecEnumRef "РўРёРїРњР°СЂС€СЂСѓС‚РЅРѕР№РўРѕС‡РєРё"); FillRequired = $true; Index = $true },
            @{ Name = "РЎС‚СЂР°РЅР°"; Synonym = "РЎС‚СЂР°РЅР°"; Type = (New-TypeSpecString 100); FillRequired = $false },
            @{ Name = "Р“РѕСЂРѕРґ"; Synonym = "Р“РѕСЂРѕРґ"; Type = (New-TypeSpecString 100); FillRequired = $false },
            @{ Name = "РђРґСЂРµСЃ"; Synonym = "РђРґСЂРµСЃ"; Type = (New-TypeSpecString 250); FillRequired = $false },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
    },
    @{
        Name = "РЈРїР°РєРѕРІРєРё"
        Synonym = "РЈРїР°РєРѕРІРєРё"
        CodeLength = 9
        DescriptionLength = 150
        Attributes = @(
            @{ Name = "РўРёРїРЈРїР°РєРѕРІРєРё"; Synonym = "РўРёРї СѓРїР°РєРѕРІРєРё"; Type = (New-TypeSpecString 100); FillRequired = $true; Index = $true },
            @{ Name = "РљРѕР»РёС‡РµСЃС‚РІРѕРњРµСЃС‚"; Synonym = "РљРѕР»РёС‡РµСЃС‚РІРѕ РјРµСЃС‚"; Type = (New-TypeSpecNumber 10 0); FillRequired = $false },
            @{ Name = "Р’РµСЃР¤Р°РєС‚"; Synonym = "Р’РµСЃ С„Р°РєС‚ РєРі"; Type = (New-TypeSpecNumber 15 3); FillRequired = $false },
            @{ Name = "Р”Р»РёРЅР°"; Synonym = "Р”Р»РёРЅР° СЃРј"; Type = (New-TypeSpecNumber 15 3); FillRequired = $false },
            @{ Name = "РЁРёСЂРёРЅР°"; Synonym = "РЁРёСЂРёРЅР° СЃРј"; Type = (New-TypeSpecNumber 15 3); FillRequired = $false },
            @{ Name = "Р’С‹СЃРѕС‚Р°"; Synonym = "Р’С‹СЃРѕС‚Р° СЃРј"; Type = (New-TypeSpecNumber 15 3); FillRequired = $false },
            @{ Name = "РћР±СЉРµРј"; Synonym = "РћР±СЉРµРј Рј3"; Type = (New-TypeSpecNumber 15 3); FillRequired = $false },
            @{ Name = "РСЃРїРѕР»СЊР·РѕРІР°С‚СЊРџРѕРЈРјРѕР»С‡Р°РЅРёСЋ"; Synonym = "РСЃРїРѕР»СЊР·РѕРІР°С‚СЊ РїРѕ СѓРјРѕР»С‡Р°РЅРёСЋ"; Type = (New-TypeSpecBoolean); FillRequired = $false },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
    }
)

$documents = @(
    @{
        Name = "Р—Р°РєР°Р·РџРѕСЃС‚Р°РІС‰РёРєСѓ"
        Synonym = "Р—Р°РєР°Р· РїРѕСЃС‚Р°РІС‰РёРєСѓ"
        Attributes = @(
            @{ Name = "Р—Р°РєР°Р·РћСЃРЅРѕРІР°РЅРёРµ"; Synonym = "Р—Р°РєР°Р·-РѕСЃРЅРѕРІР°РЅРёРµ"; Type = (New-TypeSpecDocumentRef "Р—Р°РєР°Р·"); FillRequired = $true; Index = $true },
            @{ Name = "РџРѕСЃС‚Р°РІС‰РёРє"; Synonym = "РџРѕСЃС‚Р°РІС‰РёРє"; Type = (New-TypeSpecCatalogRef "РџРѕСЃС‚Р°РІС‰РёРєРё"); FillRequired = $true; Index = $true },
            @{ Name = "РњРµРЅРµРґР¶РµСЂ"; Synonym = "РњРµРЅРµРґР¶РµСЂ"; Type = (New-TypeSpecCatalogRef "РЎРѕС‚СЂСѓРґРЅРёРєРё"); FillRequired = $false; Index = $true },
            @{ Name = "РЎС‚Р°С‚СѓСЃР—Р°РєР°Р·Р°РџРѕСЃС‚Р°РІС‰РёРєСѓ"; Synonym = "РЎС‚Р°С‚СѓСЃ Р·Р°РєР°Р·Р° РїРѕСЃС‚Р°РІС‰РёРєСѓ"; Type = (New-TypeSpecCatalogRef "РЎС‚Р°С‚СѓСЃС‹"); FillRequired = $false; Index = $true },
            @{ Name = "Р’Р°Р»СЋС‚Р°"; Synonym = "Р’Р°Р»СЋС‚Р°"; Type = (New-TypeSpecString 3); FillRequired = $false; Index = $true },
            @{ Name = "РљСѓСЂСЃР’Р°Р»СЋС‚С‹"; Synonym = "РљСѓСЂСЃ РІР°Р»СЋС‚С‹"; Type = (New-TypeSpecNumber 15 6); FillRequired = $false },
            @{ Name = "Р”Р°С‚Р°РџР»Р°РЅРћРїР»Р°С‚С‹"; Synonym = "Р”Р°С‚Р° РїР»Р°РЅ РѕРїР»Р°С‚С‹"; Type = (New-TypeSpecDate); FillRequired = $false },
            @{ Name = "Р”Р°С‚Р°Р¤Р°РєС‚РћРїР»Р°С‚С‹"; Synonym = "Р”Р°С‚Р° С„Р°РєС‚ РѕРїР»Р°С‚С‹"; Type = (New-TypeSpecDate); FillRequired = $false },
            @{ Name = "Р”Р°С‚Р°РџР»Р°РЅРћС‚РіСЂСѓР·РєРё"; Synonym = "Р”Р°С‚Р° РїР»Р°РЅ РѕС‚РіСЂСѓР·РєРё"; Type = (New-TypeSpecDate); FillRequired = $false },
            @{ Name = "Р”Р°С‚Р°Р¤Р°РєС‚РћС‚РіСЂСѓР·РєРё"; Synonym = "Р”Р°С‚Р° С„Р°РєС‚ РѕС‚РіСЂСѓР·РєРё"; Type = (New-TypeSpecDate); FillRequired = $false },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
        TabularSections = @(
            @{
                Name = "РџРѕР·РёС†РёРё"
                Synonym = "РџРѕР·РёС†РёРё Р·Р°РєР°Р·Р° РїРѕСЃС‚Р°РІС‰РёРєСѓ"
                Attributes = @(
                    @{ Name = "Р—Р°РєР°Р·"; Synonym = "Р—Р°РєР°Р·"; Type = (New-TypeSpecDocumentRef "Р—Р°РєР°Р·"); FillRequired = $false; Index = $true },
                    @{ Name = "РќРѕРјРµСЂРЎС‚СЂРѕРєРёР—Р°РєР°Р·Р°"; Synonym = "в„– СЃС‚СЂРѕРєРё Р·Р°РєР°Р·Р°"; Type = (New-TypeSpecNumber 10 0); FillRequired = $false; Index = $true },
                    @{ Name = "РўРѕРІР°СЂ"; Synonym = "РўРѕРІР°СЂ"; Type = (New-TypeSpecCatalogRef "РўРѕРІР°СЂС‹"); FillRequired = $true; Index = $true },
                    @{ Name = "РљРѕР»РёС‡РµСЃС‚РІРѕ"; Synonym = "РљРѕР»РёС‡РµСЃС‚РІРѕ"; Type = (New-TypeSpecNumber 15 3); FillRequired = $true },
                    @{ Name = "Р¦РµРЅР°Р—Р°РєСѓРїРєРё"; Synonym = "Р¦РµРЅР° Р·Р°РєСѓРїРєРё"; Type = (New-TypeSpecNumber 15 2); FillRequired = $false },
                    @{ Name = "РџР»Р°РЅР”Р°С‚Р°РџРѕСЃС‚Р°РІРєРё"; Synonym = "РџР»Р°РЅ РґР°С‚Р° РїРѕСЃС‚Р°РІРєРё"; Type = (New-TypeSpecDate); FillRequired = $false },
                    @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 150); FillRequired = $false }
                )
            }
        )
    },
    @{
        Name = "РЎРѕРїСѓС‚СЃС‚РІСѓСЋС‰РёР№Р Р°СЃС…РѕРґ"
        Synonym = "РЎРѕРїСѓС‚СЃС‚РІСѓСЋС‰РёР№ СЂР°СЃС…РѕРґ"
        Attributes = @(
            @{ Name = "Р—Р°РєР°Р·"; Synonym = "Р—Р°РєР°Р·"; Type = (New-TypeSpecDocumentRef "Р—Р°РєР°Р·"); FillRequired = $false; Index = $true },
            @{ Name = "РћС‚РїСЂР°РІРєР°"; Synonym = "РћС‚РїСЂР°РІРєР°"; Type = (New-TypeSpecDocumentRef "РћС‚РїСЂР°РІРєР°"); FillRequired = $false; Index = $true },
            @{ Name = "РЎС‚Р°С‚СЊСЏР Р°СЃС…РѕРґРѕРІ"; Synonym = "РЎС‚Р°С‚СЊСЏ СЂР°СЃС…РѕРґРѕРІ"; Type = (New-TypeSpecCatalogRef "РЎС‚Р°С‚СЊРёР Р°СЃС…РѕРґРѕРІ"); FillRequired = $true; Index = $true },
            @{ Name = "РЎРїРѕСЃРѕР±Р Р°СЃРїСЂРµРґРµР»РµРЅРёСЏ"; Synonym = "РЎРїРѕСЃРѕР± СЂР°СЃРїСЂРµРґРµР»РµРЅРёСЏ"; Type = (New-TypeSpecEnumRef "РЎРїРѕСЃРѕР±Р Р°СЃРїСЂРµРґРµР»РµРЅРёСЏ"); FillRequired = $true; Index = $true },
            @{ Name = "Р’Р°Р»СЋС‚Р°"; Synonym = "Р’Р°Р»СЋС‚Р°"; Type = (New-TypeSpecString 3); FillRequired = $false; Index = $true },
            @{ Name = "РЎСѓРјРјР°"; Synonym = "РЎСѓРјРјР°"; Type = (New-TypeSpecNumber 15 2); FillRequired = $true },
            @{ Name = "РЎСѓРјРјР°Р СѓР±"; Synonym = "РЎСѓРјРјР° СЂСѓР±"; Type = (New-TypeSpecNumber 15 2); FillRequired = $false },
            @{ Name = "Р”Р°С‚Р°РџР»Р°РЅ"; Synonym = "РџР»Р°РЅРѕРІР°СЏ РґР°С‚Р°"; Type = (New-TypeSpecDate); FillRequired = $false },
            @{ Name = "Р”Р°С‚Р°Р¤Р°РєС‚"; Synonym = "Р¤Р°РєС‚РёС‡РµСЃРєР°СЏ РґР°С‚Р°"; Type = (New-TypeSpecDate); FillRequired = $false },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
        TabularSections = @(
            @{
                Name = "РџРѕР·РёС†РёРё"
                Synonym = "РџРѕР·РёС†РёРё СЂР°СЃРїСЂРµРґРµР»РµРЅРёСЏ СЂР°СЃС…РѕРґРѕРІ"
                Attributes = @(
                    @{ Name = "Р—Р°РєР°Р·"; Synonym = "Р—Р°РєР°Р·"; Type = (New-TypeSpecDocumentRef "Р—Р°РєР°Р·"); FillRequired = $false; Index = $true },
                    @{ Name = "РќРѕРјРµСЂРЎС‚СЂРѕРєРёР—Р°РєР°Р·Р°"; Synonym = "в„– СЃС‚СЂРѕРєРё Р·Р°РєР°Р·Р°"; Type = (New-TypeSpecNumber 10 0); FillRequired = $false; Index = $true },
                    @{ Name = "РЎСѓРјРјР°Р Р°СЃРїСЂРµРґРµР»РµРЅРёСЏ"; Synonym = "РЎСѓРјРјР° СЂР°СЃРїСЂРµРґРµР»РµРЅРёСЏ"; Type = (New-TypeSpecNumber 15 2); FillRequired = $false },
                    @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 150); FillRequired = $false }
                )
            }
        )
    },
    @{
        Name = "Р РµРіРёСЃС‚СЂР°С†РёСЏР”РѕРєСѓРјРµРЅС‚Р°"
        Synonym = "Р РµРіРёСЃС‚СЂР°С†РёСЏ РґРѕРєСѓРјРµРЅС‚Р°"
        Attributes = @(
            @{ Name = "Р—Р°РєР°Р·"; Synonym = "Р—Р°РєР°Р·"; Type = (New-TypeSpecDocumentRef "Р—Р°РєР°Р·"); FillRequired = $false; Index = $true },
            @{ Name = "РћС‚РїСЂР°РІРєР°"; Synonym = "РћС‚РїСЂР°РІРєР°"; Type = (New-TypeSpecDocumentRef "РћС‚РїСЂР°РІРєР°"); FillRequired = $false; Index = $true },
            @{ Name = "РўРёРїР”РѕРєСѓРјРµРЅС‚Р°"; Synonym = "РўРёРї РґРѕРєСѓРјРµРЅС‚Р°"; Type = (New-TypeSpecEnumRef "РўРёРїР”РѕРєСѓРјРµРЅС‚Р°Р’Р»РѕР¶РµРЅРёСЏ"); FillRequired = $true; Index = $true },
            @{ Name = "РќРѕРјРµСЂР”РѕРєСѓРјРµРЅС‚Р°"; Synonym = "РќРѕРјРµСЂ РґРѕРєСѓРјРµРЅС‚Р°"; Type = (New-TypeSpecString 50); FillRequired = $false; Index = $true },
            @{ Name = "Р”Р°С‚Р°Р”РѕРєСѓРјРµРЅС‚Р°"; Synonym = "Р”Р°С‚Р° РґРѕРєСѓРјРµРЅС‚Р°"; Type = (New-TypeSpecDate); FillRequired = $false; Index = $true },
            @{ Name = "РРјСЏР¤Р°Р№Р»Р°"; Synonym = "РРјСЏ С„Р°Р№Р»Р°"; Type = (New-TypeSpecString 150); FillRequired = $false },
            @{ Name = "РџСѓС‚СЊРљР¤Р°Р№Р»Сѓ"; Synonym = "РџСѓС‚СЊ Рє С„Р°Р№Р»Сѓ"; Type = (New-TypeSpecString 250); FillRequired = $false },
            @{ Name = "РђРІС‚РѕСЂР—Р°РіСЂСѓР·РєРё"; Synonym = "РђРІС‚РѕСЂ Р·Р°РіСЂСѓР·РєРё"; Type = (New-TypeSpecCatalogRef "РЎРѕС‚СЂСѓРґРЅРёРєРё"); FillRequired = $false; Index = $true },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
        TabularSections = @()
    }
)

$informationRegisters = @(
    @{
        Name = "Р­С‚Р°РїС‹Р”РѕСЃС‚Р°РІРєРё"
        Synonym = "Р­С‚Р°РїС‹ РґРѕСЃС‚Р°РІРєРё"
        Dimensions = @(
            @{ Name = "РћС‚РїСЂР°РІРєР°"; Synonym = "РћС‚РїСЂР°РІРєР°"; Type = (New-TypeSpecDocumentRef "РћС‚РїСЂР°РІРєР°"); FillRequired = $true; Index = $true },
            @{ Name = "РџРѕСЂСЏРґРѕРєР­С‚Р°РїР°"; Synonym = "РџРѕСЂСЏРґРѕРє СЌС‚Р°РїР°"; Type = (New-TypeSpecNumber 10 0); FillRequired = $true; Index = $true }
        )
        Resources = @()
        Attributes = @(
            @{ Name = "РќР°РёРјРµРЅРѕРІР°РЅРёРµР­С‚Р°РїР°"; Synonym = "РќР°РёРјРµРЅРѕРІР°РЅРёРµ СЌС‚Р°РїР°"; Type = (New-TypeSpecString 100); FillRequired = $true; Index = $true },
            @{ Name = "РЎС‚Р°С‚СѓСЃР­С‚Р°РїР°"; Synonym = "РЎС‚Р°С‚СѓСЃ СЌС‚Р°РїР°"; Type = (New-TypeSpecEnumRef "РЎС‚Р°С‚СѓСЃР­С‚Р°РїР°Р”РѕСЃС‚Р°РІРєРё"); FillRequired = $false; Index = $true },
            @{ Name = "Р”Р°С‚Р°РџР»Р°РЅ"; Synonym = "РџР»Р°РЅРѕРІР°СЏ РґР°С‚Р°"; Type = (New-TypeSpecDate); FillRequired = $false },
            @{ Name = "Р”Р°С‚Р°Р¤Р°РєС‚"; Synonym = "Р¤Р°РєС‚РёС‡РµСЃРєР°СЏ РґР°С‚Р°"; Type = (New-TypeSpecDate); FillRequired = $false },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
    },
    @{
        Name = "РЎРѕР±С‹С‚РёСЏРўСЂРµРєРёРЅРіР°"
        Synonym = "РЎРѕР±С‹С‚РёСЏ С‚СЂРµРєРёРЅРіР°"
        Dimensions = @(
            @{ Name = "РћС‚РїСЂР°РІРєР°"; Synonym = "РћС‚РїСЂР°РІРєР°"; Type = (New-TypeSpecDocumentRef "РћС‚РїСЂР°РІРєР°"); FillRequired = $true; Index = $true },
            @{ Name = "РљРѕРґРЎРѕР±С‹С‚РёСЏ"; Synonym = "РљРѕРґ СЃРѕР±С‹С‚РёСЏ"; Type = (New-TypeSpecString 40); FillRequired = $true; Index = $true }
        )
        Resources = @()
        Attributes = @(
            @{ Name = "Р”Р°С‚Р°РЎРѕР±С‹С‚РёСЏ"; Synonym = "Р”Р°С‚Р° СЃРѕР±С‹С‚РёСЏ"; Type = (New-TypeSpecDate); FillRequired = $false; Index = $true },
            @{ Name = "РўРёРїРЎРѕР±С‹С‚РёСЏ"; Synonym = "РўРёРї СЃРѕР±С‹С‚РёСЏ"; Type = (New-TypeSpecEnumRef "РўРёРїРЎРѕР±С‹С‚РёСЏРўСЂРµРєРёРЅРіР°"); FillRequired = $false; Index = $true },
            @{ Name = "Р›РѕРєР°С†РёСЏ"; Synonym = "Р›РѕРєР°С†РёСЏ"; Type = (New-TypeSpecString 150); FillRequired = $false },
            @{ Name = "РСЃС‚РѕС‡РЅРёРє"; Synonym = "РСЃС‚РѕС‡РЅРёРє"; Type = (New-TypeSpecString 100); FillRequired = $false },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
    },
    @{
        Name = "РџРµСЂРµС…РѕРґС‹РЎС‚Р°С‚СѓСЃРѕРІ"
        Synonym = "РџРµСЂРµС…РѕРґС‹ СЃС‚Р°С‚СѓСЃРѕРІ"
        Dimensions = @(
            @{ Name = "РљР°С‚РµРіРѕСЂРёСЏ"; Synonym = "РљР°С‚РµРіРѕСЂРёСЏ"; Type = (New-TypeSpecEnumRef "РљР°С‚РµРіРѕСЂРёСЏРЎС‚Р°С‚СѓСЃР°"); FillRequired = $true; Index = $true },
            @{ Name = "РЎС‚Р°С‚СѓСЃРСЃС‚РѕС‡РЅРёРє"; Synonym = "РЎС‚Р°С‚СѓСЃ РёСЃС‚РѕС‡РЅРёРє"; Type = (New-TypeSpecCatalogRef "РЎС‚Р°С‚СѓСЃС‹"); FillRequired = $true; Index = $true },
            @{ Name = "РЎС‚Р°С‚СѓСЃРќР°Р·РЅР°С‡РµРЅРёРµ"; Synonym = "РЎС‚Р°С‚СѓСЃ РЅР°Р·РЅР°С‡РµРЅРёРµ"; Type = (New-TypeSpecCatalogRef "РЎС‚Р°С‚СѓСЃС‹"); FillRequired = $true; Index = $true }
        )
        Resources = @()
        Attributes = @(
            @{ Name = "Р РѕР»СЊРСЃРїРѕР»РЅРёС‚РµР»СЏ"; Synonym = "Р РѕР»СЊ РёСЃРїРѕР»РЅРёС‚РµР»СЏ"; Type = (New-TypeSpecEnumRef "Р РѕР»СЊРџРѕР»СЊР·РѕРІР°С‚РµР»СЏ"); FillRequired = $false; Index = $true },
            @{ Name = "РђРІС‚РѕРјР°С‚РёС‡РµСЃРєРёР№РџРµСЂРµС…РѕРґ"; Synonym = "РђРІС‚РѕРјР°С‚РёС‡РµСЃРєРёР№ РїРµСЂРµС…РѕРґ"; Type = (New-TypeSpecBoolean); FillRequired = $false },
            @{ Name = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Synonym = "РљРѕРјРјРµРЅС‚Р°СЂРёР№"; Type = (New-TypeSpecString 250); FillRequired = $false }
        )
    }
)

$commonModules = @(
    @{
        Name = "Р›РѕРіРёРєР°РЎС‚Р°С‚СѓСЃРѕРІ"
        Synonym = "Р›РѕРіРёРєР° СЃС‚Р°С‚СѓСЃРѕРІ"
        Body = @'
#РћР±Р»Р°СЃС‚СЊ РџРµСЂРµС…РѕРґС‹РЎС‚Р°С‚СѓСЃРѕРІ

Р¤СѓРЅРєС†РёСЏ РџСЂРѕРІРµСЂРёС‚СЊРџРµСЂРµС…РѕРґРЎС‚Р°С‚СѓСЃР°(РљР°С‚РµРіРѕСЂРёСЏ, РЎС‚Р°С‚СѓСЃРСЃС‚РѕС‡РЅРёРє, РЎС‚Р°С‚СѓСЃРќР°Р·РЅР°С‡РµРЅРёРµ, Р РѕР»СЊРџРѕР»СЊР·РѕРІР°С‚РµР»СЏ = РќРµРѕРїСЂРµРґРµР»РµРЅРѕ) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РСЃС‚РёРЅР°;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

РџСЂРѕС†РµРґСѓСЂР° Р—Р°РїРёСЃР°С‚СЊРСЃС‚РѕСЂРёСЋРЎС‚Р°С‚СѓСЃР°(Р—Р°РєР°Р·РЎСЃС‹Р»РєР°, РљР°С‚РµРіРѕСЂРёСЏ, РќРѕРІС‹Р№РЎС‚Р°С‚СѓСЃ, РљРѕРјРјРµРЅС‚Р°СЂРёР№ = "") Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

Р¤СѓРЅРєС†РёСЏ РџРѕР»СѓС‡РёС‚СЊР”РѕСЃС‚СѓРїРЅС‹РµРџРµСЂРµС…РѕРґС‹(РљР°С‚РµРіРѕСЂРёСЏ, РўРµРєСѓС‰РёР№РЎС‚Р°С‚СѓСЃ, Р РѕР»СЊРџРѕР»СЊР·РѕРІР°С‚РµР»СЏ = РќРµРѕРїСЂРµРґРµР»РµРЅРѕ) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РќРѕРІС‹Р№ РњР°СЃСЃРёРІ;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

#РљРѕРЅРµС†РћР±Р»Р°СЃС‚Рё
'@
    },
    @{
        Name = "Р›РѕРіРёРєР°Р¤РёРЅР°РЅСЃРѕРІ"
        Synonym = "Р›РѕРіРёРєР° С„РёРЅР°РЅСЃРѕРІ"
        Body = @'
#РћР±Р»Р°СЃС‚СЊ Р¤РёРЅР°РЅСЃС‹Р—Р°РєР°Р·РѕРІ

Р¤СѓРЅРєС†РёСЏ Р Р°СЃСЃС‡РёС‚Р°С‚СЊРћСЃС‚Р°С‚РєРёРџРѕР—Р°РєР°Р·Сѓ(Р—Р°РєР°Р·РЎСЃС‹Р»РєР°) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РќРѕРІС‹Р№ РЎС‚СЂСѓРєС‚СѓСЂР°;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

РџСЂРѕС†РµРґСѓСЂР° Р—Р°РїРёСЃР°С‚СЊР”РІРёР¶РµРЅРёРµР”Р”РЎ(Р”РѕРєСѓРјРµРЅС‚РЎСЃС‹Р»РєР°, РЎС‚Р°С‚СЊСЏР”Р”РЎ, РЎСѓРјРјР°Р СѓР±, Р’РёРґРћРїР»Р°С‚С‹) Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

РџСЂРѕС†РµРґСѓСЂР° РћР±РЅРѕРІРёС‚СЊРЎС‚Р°С‚СѓСЃРћРїР»Р°С‚С‹Р—Р°РєР°Р·Р°(Р—Р°РєР°Р·РЎСЃС‹Р»РєР°) Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

#РљРѕРЅРµС†РћР±Р»Р°СЃС‚Рё
'@
    },
    @{
        Name = "Р›РѕРіРёРєР°Р›РѕРіРёСЃС‚РёРєРё"
        Synonym = "Р›РѕРіРёРєР° Р»РѕРіРёСЃС‚РёРєРё"
        Body = @'
#РћР±Р»Р°СЃС‚СЊ Р›РѕРіРёСЃС‚РёРєР°

РџСЂРѕС†РµРґСѓСЂР° РЎРѕР·РґР°С‚СЊР­С‚Р°РїС‹РџРѕРњР°СЂС€СЂСѓС‚Сѓ(РћС‚РїСЂР°РІРєР°РЎСЃС‹Р»РєР°, РњР°СЂС€СЂСѓС‚Р”РѕСЃС‚Р°РІРєРё) Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

РџСЂРѕС†РµРґСѓСЂР° Р—Р°РїРёСЃР°С‚СЊРЎРѕР±С‹С‚РёРµРўСЂРµРєРёРЅРіР°(РћС‚РїСЂР°РІРєР°РЎСЃС‹Р»РєР°, РљРѕРґРЎРѕР±С‹С‚РёСЏ, РўРёРїРЎРѕР±С‹С‚РёСЏ, Р›РѕРєР°С†РёСЏ = "", РљРѕРјРјРµРЅС‚Р°СЂРёР№ = "") Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

РџСЂРѕС†РµРґСѓСЂР° РџРµСЂРµСЃС‡РёС‚Р°С‚СЊРџР»Р°РЅРѕРІС‹РµР”Р°С‚С‹РћС‚РїСЂР°РІРєРё(РћС‚РїСЂР°РІРєР°РћР±СЉРµРєС‚) Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

#РљРѕРЅРµС†РћР±Р»Р°СЃС‚Рё
'@
    },
    @{
        Name = "Р›РѕРіРёРєР°РЈРІРµРґРѕРјР»РµРЅРёР№"
        Synonym = "Р›РѕРіРёРєР° СѓРІРµРґРѕРјР»РµРЅРёР№"
        Body = @'
#РћР±Р»Р°СЃС‚СЊ РЈРІРµРґРѕРјР»РµРЅРёСЏ

РџСЂРѕС†РµРґСѓСЂР° РЎРѕР·РґР°С‚СЊРЈРІРµРґРѕРјР»РµРЅРёРµ(РџРѕР»СѓС‡Р°С‚РµР»СЊ, РўРёРїРЈРІРµРґРѕРјР»РµРЅРёСЏ, РўРµРєСЃС‚, Р—Р°РєР°Р· = РќРµРѕРїСЂРµРґРµР»РµРЅРѕ, РћС‚РїСЂР°РІРєР° = РќРµРѕРїСЂРµРґРµР»РµРЅРѕ) Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

РџСЂРѕС†РµРґСѓСЂР° РЎРѕР·РґР°С‚СЊРЈРІРµРґРѕРјР»РµРЅРёСЏРџРѕРџСЂРѕСЃСЂРѕС‡РєР°Рј() Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

РџСЂРѕС†РµРґСѓСЂР° РџРѕРјРµС‚РёС‚СЊРџСЂРѕС‡РёС‚Р°РЅРЅС‹Рј(РРґРµРЅС‚РёС„РёРєР°С‚РѕСЂРЈРІРµРґРѕРјР»РµРЅРёСЏ) Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

#РљРѕРЅРµС†РћР±Р»Р°СЃС‚Рё
'@
    },
    @{
        Name = "РРЅРёС†РёР°Р»РёР·Р°С†РёСЏРќРЎР"
        Synonym = "РРЅРёС†РёР°Р»РёР·Р°С†РёСЏ РќРЎР"
        Body = @'
#РћР±Р»Р°СЃС‚СЊ РРЅРёС†РёР°Р»РёР·Р°С†РёСЏ

РџСЂРѕС†РµРґСѓСЂР° Р—Р°РїРѕР»РЅРёС‚СЊРџСЂРµРґРѕРїСЂРµРґРµР»РµРЅРЅС‹РµРЎС‚Р°С‚СѓСЃС‹() Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

РџСЂРѕС†РµРґСѓСЂР° Р—Р°РїРѕР»РЅРёС‚СЊРўРёРїРѕРІС‹РµР¤РѕСЂРјС‹РћРїР»Р°С‚С‹() Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

РџСЂРѕС†РµРґСѓСЂР° Р—Р°РїРѕР»РЅРёС‚СЊРўРёРїРѕРІС‹РµРЎРїРѕСЃРѕР±С‹Р”РѕСЃС‚Р°РІРєРё() Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

#РљРѕРЅРµС†РћР±Р»Р°СЃС‚Рё
'@
    },
    @{
        Name = "РњРёРіСЂР°С†РёСЏРР·Excel"
        Synonym = "РњРёРіСЂР°С†РёСЏ РёР· Excel"
        Body = @'
#РћР±Р»Р°СЃС‚СЊ РРјРїРѕСЂС‚Excel

Р¤СѓРЅРєС†РёСЏ РџРѕРґРіРѕС‚РѕРІРёС‚СЊРџСЂР°РІРёР»Р°РРјРїРѕСЂС‚Р°() Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РќРѕРІС‹Р№ РЎС‚СЂСѓРєС‚СѓСЂР°;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

РџСЂРѕС†РµРґСѓСЂР° РРјРїРѕСЂС‚РёСЂРѕРІР°С‚СЊРќРЎРРР·Excel(РџСѓС‚СЊРљР¤Р°Р№Р»Сѓ) Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

РџСЂРѕС†РµРґСѓСЂР° РРјРїРѕСЂС‚РёСЂРѕРІР°С‚СЊР—Р°РєР°Р·С‹РР·Excel(РџСѓС‚СЊРљР¤Р°Р№Р»Сѓ) Р­РєСЃРїРѕСЂС‚
РљРѕРЅРµС†РџСЂРѕС†РµРґСѓСЂС‹

#РљРѕРЅРµС†РћР±Р»Р°СЃС‚Рё
'@
    },
    @{
        Name = "РџСЂР°РІР°Р”РѕСЃС‚СѓРїР°"
        Synonym = "РџСЂР°РІР° РґРѕСЃС‚СѓРїР°"
        Body = @'
#РћР±Р»Р°СЃС‚СЊ РџСЂР°РІР°

Р¤СѓРЅРєС†РёСЏ РњРѕР¶РµС‚РР·РјРµРЅСЏС‚СЊР¤РёРЅР°РЅСЃС‹(РЎРѕС‚СЂСѓРґРЅРёРє) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ Р›РѕР¶СЊ;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

Р¤СѓРЅРєС†РёСЏ РњРѕР¶РµС‚РР·РјРµРЅСЏС‚СЊР›РѕРіРёСЃС‚РёРєСѓ(РЎРѕС‚СЂСѓРґРЅРёРє) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ Р›РѕР¶СЊ;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

Р¤СѓРЅРєС†РёСЏ РњРѕР¶РµС‚РњРµРЅСЏС‚СЊРЎС‚Р°С‚СѓСЃ(РЎРѕС‚СЂСѓРґРЅРёРє, РљР°С‚РµРіРѕСЂРёСЏРЎС‚Р°С‚СѓСЃР°) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ Р›РѕР¶СЊ;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

#РљРѕРЅРµС†РћР±Р»Р°СЃС‚Рё
'@
    },
    @{
        Name = "РћС‚С‡РµС‚С‹Р—Р°РєР°Р·РѕРІ"
        Synonym = "РћС‚С‡РµС‚С‹ Р·Р°РєР°Р·РѕРІ"
        Body = @'
#РћР±Р»Р°СЃС‚СЊ РћС‚С‡РµС‚С‹

Р¤СѓРЅРєС†РёСЏ РџРѕР»СѓС‡РёС‚СЊР”Р°РЅРЅС‹РµР РµРµСЃС‚СЂР°Р—Р°РєР°Р·РѕРІ(РџР°СЂР°РјРµС‚СЂС‹РћС‚Р±РѕСЂР° = РќРµРѕРїСЂРµРґРµР»РµРЅРѕ) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РќРѕРІС‹Р№ РўР°Р±Р»РёС†Р°Р—РЅР°С‡РµРЅРёР№;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

Р¤СѓРЅРєС†РёСЏ РџРѕР»СѓС‡РёС‚СЊР”Р°РЅРЅС‹РµРљРѕРЅС‚СЂРѕР»СЏРћРїР»Р°С‚(РџР°СЂР°РјРµС‚СЂС‹РћС‚Р±РѕСЂР° = РќРµРѕРїСЂРµРґРµР»РµРЅРѕ) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РќРѕРІС‹Р№ РўР°Р±Р»РёС†Р°Р—РЅР°С‡РµРЅРёР№;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

Р¤СѓРЅРєС†РёСЏ РџРѕР»СѓС‡РёС‚СЊР”Р°РЅРЅС‹РµР›РѕРіРёСЃС‚РёС‡РµСЃРєРѕРіРѕРћС‚С‡РµС‚Р°(РџР°СЂР°РјРµС‚СЂС‹РћС‚Р±РѕСЂР° = РќРµРѕРїСЂРµРґРµР»РµРЅРѕ) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РќРѕРІС‹Р№ РўР°Р±Р»РёС†Р°Р—РЅР°С‡РµРЅРёР№;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

#РљРѕРЅРµС†РћР±Р»Р°СЃС‚Рё
'@
    }
)

$reports = @(
    @{ Name = "Р РµРµСЃС‚СЂР—Р°РєР°Р·РѕРІ"; Synonym = "Р РµРµСЃС‚СЂ Р·Р°РєР°Р·РѕРІ" },
    @{ Name = "РљРѕРЅС‚СЂРѕР»СЊРћРїР»Р°С‚"; Synonym = "РљРѕРЅС‚СЂРѕР»СЊ РѕРїР»Р°С‚" },
    @{ Name = "Р›РѕРіРёСЃС‚РёС‡РµСЃРєРёР№РћС‚С‡РµС‚"; Synonym = "Р›РѕРіРёСЃС‚РёС‡РµСЃРєРёР№ РѕС‚С‡РµС‚" },
    @{ Name = "РњР°СЂР¶РёРЅР°Р»СЊРЅРѕСЃС‚СЊР—Р°РєР°Р·РѕРІ"; Synonym = "РњР°СЂР¶РёРЅР°Р»СЊРЅРѕСЃС‚СЊ Р·Р°РєР°Р·РѕРІ" },
    @{ Name = "Р”РІРёР¶РµРЅРёРµР”РµРЅРµР¶РЅС‹С…РЎСЂРµРґСЃС‚РІРџРѕР—Р°РєР°Р·Р°Рј"; Synonym = "Р”Р”РЎ РїРѕ Р·Р°РєР°Р·Р°Рј" },
    @{ Name = "РќРµР·Р°РІРµСЂС€РµРЅРЅС‹РµР—Р°РєР°Р·С‹"; Synonym = "РќРµР·Р°РІРµСЂС€РµРЅРЅС‹Рµ Р·Р°РєР°Р·С‹" }
)

$subsystems = @(
    @{ Name = "РќРЎР"; Synonym = "РќРЎР" },
    @{ Name = "Р—Р°РєР°Р·С‹"; Synonym = "Р—Р°РєР°Р·С‹" },
    @{ Name = "Р¤РёРЅР°РЅСЃС‹"; Synonym = "Р¤РёРЅР°РЅСЃС‹" },
    @{ Name = "Р›РѕРіРёСЃС‚РёРєР°"; Synonym = "Р›РѕРіРёСЃС‚РёРєР°" },
    @{ Name = "РћС‚С‡РµС‚С‹"; Synonym = "РћС‚С‡РµС‚С‹" },
    @{ Name = "РђРґРјРёРЅРёСЃС‚СЂРёСЂРѕРІР°РЅРёРµ"; Synonym = "РђРґРјРёРЅРёСЃС‚СЂРёСЂРѕРІР°РЅРёРµ" }
)

foreach ($enum in $enums) {
    Write-Enum -Definition $enum
}

foreach ($catalog in $catalogs) {
    Write-Catalog -Definition $catalog
}

foreach ($document in $documents) {
    Write-DocumentMetadata -Definition $document
}

foreach ($register in $informationRegisters) {
    Write-InformationRegisterMetadata -Definition $register
}

Write-Role -Name "Р СѓРєРѕРІРѕРґРёС‚РµР»СЊ" -Synonym "Р СѓРєРѕРІРѕРґРёС‚РµР»СЊ"
Write-Role -Name "РђРґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂ" -Synonym "РђРґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂ"

foreach ($module in $commonModules) {
    Write-CommonModule -Name $module.Name -Synonym $module.Synonym -ModuleBody $module.Body
}

foreach ($report in $reports) {
    Write-Report -Name $report.Name -Synonym $report.Synonym
}

Write-DataProcessor -Name "Р Р°Р±РѕС‡РёР№РЎС‚РѕР»РњРµРЅРµРґР¶РµСЂР°" -Synonym "Р Р°Р±РѕС‡РёР№ СЃС‚РѕР» РјРµРЅРµРґР¶РµСЂР°" -ModuleBody @'
#РћР±Р»Р°СЃС‚СЊ Р Р°Р±РѕС‡РёР№РЎС‚РѕР»

Р¤СѓРЅРєС†РёСЏ РџРѕР»СѓС‡РёС‚СЊРњРѕРёР—Р°РєР°Р·С‹(РЎРѕС‚СЂСѓРґРЅРёРє, РџР°СЂР°РјРµС‚СЂС‹РћС‚Р±РѕСЂР° = РќРµРѕРїСЂРµРґРµР»РµРЅРѕ) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РќРѕРІС‹Р№ РўР°Р±Р»РёС†Р°Р—РЅР°С‡РµРЅРёР№;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

Р¤СѓРЅРєС†РёСЏ РџРѕР»СѓС‡РёС‚СЊРџРѕРєР°Р·Р°С‚РµР»РёРџР°РЅРµР»Рё(РЎРѕС‚СЂСѓРґРЅРёРє) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РќРѕРІС‹Р№ РЎС‚СЂСѓРєС‚СѓСЂР°;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

Р¤СѓРЅРєС†РёСЏ РџРѕР»СѓС‡РёС‚СЊРђРєС‚РёРІРЅС‹РµРЈРІРµРґРѕРјР»РµРЅРёСЏ(РЎРѕС‚СЂСѓРґРЅРёРє) Р­РєСЃРїРѕСЂС‚
	Р’РѕР·РІСЂР°С‚ РќРѕРІС‹Р№ РўР°Р±Р»РёС†Р°Р—РЅР°С‡РµРЅРёР№;
РљРѕРЅРµС†Р¤СѓРЅРєС†РёРё

#РљРѕРЅРµС†РћР±Р»Р°СЃС‚Рё
'@

foreach ($subsystem in $subsystems) {
    Write-Subsystem -Name $subsystem.Name -Synonym $subsystem.Synonym
}

$employeePath = Join-Path $RootDir "Catalogs\РЎРѕС‚СЂСѓРґРЅРёРєРё\РЎРѕС‚СЂСѓРґРЅРёРєРё.xml"
Replace-Once -Path $employeePath `
    -OldValue '<mdclass:Type>xsd:string</mdclass:Type><mdclass:StringQualifiers><mdclass:Length>30</mdclass:Length><mdclass:AllowedLength>Variable</mdclass:AllowedLength></mdclass:StringQualifiers>' `
    -NewValue '<mdclass:Type>EnumRef.Р РѕР»СЊРџРѕР»СЊР·РѕРІР°С‚РµР»СЏ</mdclass:Type>'

$customersPath = Join-Path $RootDir "Catalogs\Р—Р°РєР°Р·С‡РёРєРё\Р—Р°РєР°Р·С‡РёРєРё.xml"
Insert-BeforeClosingTag -Path $customersPath -TagName "Catalog" -Marker "<mdclass:n>РљРѕРЅС‚Р°РєС‚РЅРѕРµР›РёС†Рѕ</mdclass:n>" -Fragment @"
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Catalog/Р—Р°РєР°Р·С‡РёРєРё/РљРѕРЅС‚Р°РєС‚РЅРѕРµР›РёС†Рѕ')"">
			<mdclass:n>РљРѕРЅС‚Р°РєС‚РЅРѕРµР›РёС†Рѕ</mdclass:n>
$(New-SynonymXml -Text "РљРѕРЅС‚Р°РєС‚РЅРѕРµ Р»РёС†Рѕ" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecString 120) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Catalog/Р—Р°РєР°Р·С‡РёРєРё/РџР»Р°С‚РµР¶РЅС‹РµР РµРєРІРёР·РёС‚С‹')"">
			<mdclass:n>РџР»Р°С‚РµР¶РЅС‹РµР РµРєРІРёР·РёС‚С‹</mdclass:n>
$(New-SynonymXml -Text "РџР»Р°С‚РµР¶РЅС‹Рµ СЂРµРєРІРёР·РёС‚С‹" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecString 250) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
"@

$suppliersPath = Join-Path $RootDir "Catalogs\РџРѕСЃС‚Р°РІС‰РёРєРё\РџРѕСЃС‚Р°РІС‰РёРєРё.xml"
Insert-BeforeClosingTag -Path $suppliersPath -TagName "Catalog" -Marker "<mdclass:n>РљРѕРЅС‚Р°РєС‚РЅРѕРµР›РёС†Рѕ</mdclass:n>" -Fragment @"
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Catalog/РџРѕСЃС‚Р°РІС‰РёРєРё/РљРѕРЅС‚Р°РєС‚РЅРѕРµР›РёС†Рѕ')"">
			<mdclass:n>РљРѕРЅС‚Р°РєС‚РЅРѕРµР›РёС†Рѕ</mdclass:n>
$(New-SynonymXml -Text "РљРѕРЅС‚Р°РєС‚РЅРѕРµ Р»РёС†Рѕ" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecString 120) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Catalog/РџРѕСЃС‚Р°РІС‰РёРєРё/РџР»Р°С‚РµР¶РЅС‹РµР РµРєРІРёР·РёС‚С‹')"">
			<mdclass:n>РџР»Р°С‚РµР¶РЅС‹РµР РµРєРІРёР·РёС‚С‹</mdclass:n>
$(New-SynonymXml -Text "РџР»Р°С‚РµР¶РЅС‹Рµ СЂРµРєРІРёР·РёС‚С‹" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecString 250) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
"@

$goodsPath = Join-Path $RootDir "Catalogs\РўРѕРІР°СЂС‹\РўРѕРІР°СЂС‹.xml"
Insert-BeforeClosingTag -Path $goodsPath -TagName "Catalog" -Marker "<mdclass:n>Р•РґРёРЅРёС†Р°РР·РјРµСЂРµРЅРёСЏ</mdclass:n>" -Fragment @"
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Catalog/РўРѕРІР°СЂС‹/Р•РґРёРЅРёС†Р°РР·РјРµСЂРµРЅРёСЏ')"">
			<mdclass:n>Р•РґРёРЅРёС†Р°РР·РјРµСЂРµРЅРёСЏ</mdclass:n>
$(New-SynonymXml -Text "Р•РґРёРЅРёС†Р° РёР·РјРµСЂРµРЅРёСЏ" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecString 20) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Catalog/РўРѕРІР°СЂС‹/РћР±СЉРµРј')"">
			<mdclass:n>РћР±СЉРµРј</mdclass:n>
$(New-SynonymXml -Text "РћР±СЉРµРј Рј3" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecNumber 15 3) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
"@

$orderPath = Join-Path $RootDir "Documents\Р—Р°РєР°Р·\Р—Р°РєР°Р·.xml"
Insert-BeforeMarker -Path $orderPath -SearchMarker "`t<mdclass:TabularSection" -Marker "<mdclass:n>РЎС‚Р°С‚СѓСЃР—Р°РєР°Р·Р°</mdclass:n>" -Fragment @"
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РЎС‚Р°С‚СѓСЃР—Р°РєР°Р·Р°')"">
			<mdclass:n>РЎС‚Р°С‚СѓСЃР—Р°РєР°Р·Р°</mdclass:n>
$(New-SynonymXml -Text "РЎС‚Р°С‚СѓСЃ Р·Р°РєР°Р·Р°" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecCatalogRef 'РЎС‚Р°С‚СѓСЃС‹') -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
			<mdclass:Indexing>Index</mdclass:Indexing>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РЎС‚Р°С‚СѓСЃР”РѕСЃС‚Р°РІРєРё')"">
			<mdclass:n>РЎС‚Р°С‚СѓСЃР”РѕСЃС‚Р°РІРєРё</mdclass:n>
$(New-SynonymXml -Text "РЎС‚Р°С‚СѓСЃ РґРѕСЃС‚Р°РІРєРё" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecCatalogRef 'РЎС‚Р°С‚СѓСЃС‹') -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
			<mdclass:Indexing>Index</mdclass:Indexing>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РђРґСЂРµСЃР”РѕСЃС‚Р°РІРєРё')"">
			<mdclass:n>РђРґСЂРµСЃР”РѕСЃС‚Р°РІРєРё</mdclass:n>
$(New-SynonymXml -Text "РђРґСЂРµСЃ РґРѕСЃС‚Р°РІРєРё" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecString 250) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РЎРѕРіР»Р°СЃРѕРІР°РЅРЅР°СЏР”Р°С‚Р°РџРѕСЃС‚Р°РІРєРё')"">
			<mdclass:n>РЎРѕРіР»Р°СЃРѕРІР°РЅРЅР°СЏР”Р°С‚Р°РџРѕСЃС‚Р°РІРєРё</mdclass:n>
$(New-SynonymXml -Text "РЎРѕРіР»Р°СЃРѕРІР°РЅРЅР°СЏ РґР°С‚Р° РїРѕСЃС‚Р°РІРєРё" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecDate) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
			<mdclass:Indexing>Index</mdclass:Indexing>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РЎСѓРјРјР°Р—Р°РєР°Р·Р°Р СѓР±')"">
			<mdclass:n>РЎСѓРјРјР°Р—Р°РєР°Р·Р°Р СѓР±</mdclass:n>
$(New-SynonymXml -Text "РЎСѓРјРјР° Р·Р°РєР°Р·Р° СЂСѓР±" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecNumber 15 2) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РЎСѓРјРјР°РњР°СЂР¶РёР СѓР±')"">
			<mdclass:n>РЎСѓРјРјР°РњР°СЂР¶РёР СѓР±</mdclass:n>
$(New-SynonymXml -Text "РЎСѓРјРјР° РјР°СЂР¶Рё СЂСѓР±" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecNumber 15 2) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РњР°СЂР¶Р°РџСЂРѕС†РµРЅС‚')"">
			<mdclass:n>РњР°СЂР¶Р°РџСЂРѕС†РµРЅС‚</mdclass:n>
$(New-SynonymXml -Text "РњР°СЂР¶Р° %" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecNumber 5 2) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
"@

Insert-BeforeMarker -Path $orderPath -SearchMarker '<mdclass:Attribute uuid="9f6ef6eb-6ada-4677-8914-46b2fff6f309">' -Marker "<mdclass:n>РџСЂРѕРёР·РІРѕРґРёС‚РµР»СЊ</mdclass:n>" -Fragment @"
			<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РџРѕР·РёС†РёРё/РџСЂРѕРёР·РІРѕРґРёС‚РµР»СЊ')"">
				<mdclass:n>РџСЂРѕРёР·РІРѕРґРёС‚РµР»СЊ</mdclass:n>
$(New-SynonymXml -Text "РџСЂРѕРёР·РІРѕРґРёС‚РµР»СЊ" -Indent "				")
$(New-TypeXml -TypeSpec (New-TypeSpecString 100) -Indent "				")
				<mdclass:FillRequired>false</mdclass:FillRequired>
				<mdclass:Indexing>Index</mdclass:Indexing>
			</mdclass:Attribute>
			<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РџРѕР·РёС†РёРё/РџСЂРёР±С‹Р»СЊРЎСѓРјРјР°')"">
				<mdclass:n>РџСЂРёР±С‹Р»СЊРЎСѓРјРјР°</mdclass:n>
$(New-SynonymXml -Text "РџСЂРёР±С‹Р»СЊ СЃСѓРјРјР° СЂСѓР±" -Indent "				")
$(New-TypeXml -TypeSpec (New-TypeSpecNumber 15 2) -Indent "				")
				<mdclass:FillRequired>false</mdclass:FillRequired>
			</mdclass:Attribute>
			<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/Р—Р°РєР°Р·/РџРѕР·РёС†РёРё/РС‚РѕРіРѕРІР°СЏРЎСѓРјРјР°Р СѓР±')"">
				<mdclass:n>РС‚РѕРіРѕРІР°СЏРЎСѓРјРјР°Р СѓР±</mdclass:n>
$(New-SynonymXml -Text "РС‚РѕРіРѕРІР°СЏ СЃСѓРјРјР° СЂСѓР±" -Indent "				")
$(New-TypeXml -TypeSpec (New-TypeSpecNumber 15 2) -Indent "				")
				<mdclass:FillRequired>false</mdclass:FillRequired>
			</mdclass:Attribute>
"@

$shipmentPath = Join-Path $RootDir "Documents\РћС‚РїСЂР°РІРєР°\РћС‚РїСЂР°РІРєР°.xml"
Insert-BeforeMarker -Path $shipmentPath -SearchMarker '<mdclass:Attribute uuid="28a2e521-f48b-4591-9f96-ee14a9fc70d9">' -Marker "<mdclass:n>РњР°СЂС€СЂСѓС‚Р”РѕСЃС‚Р°РІРєРё</mdclass:n>" -Fragment @"
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/РћС‚РїСЂР°РІРєР°/РњР°СЂС€СЂСѓС‚Р”РѕСЃС‚Р°РІРєРё')"">
			<mdclass:n>РњР°СЂС€СЂСѓС‚Р”РѕСЃС‚Р°РІРєРё</mdclass:n>
$(New-SynonymXml -Text "РњР°СЂС€СЂСѓС‚ РґРѕСЃС‚Р°РІРєРё" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecCatalogRef 'РњР°СЂС€СЂСѓС‚С‹Р”РѕСЃС‚Р°РІРєРё') -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
			<mdclass:Indexing>Index</mdclass:Indexing>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/РћС‚РїСЂР°РІРєР°/РџР»Р°РЅРЎС‚РѕРёРјРѕСЃС‚СЊР”РѕСЃС‚Р°РІРєРё')"">
			<mdclass:n>РџР»Р°РЅРЎС‚РѕРёРјРѕСЃС‚СЊР”РѕСЃС‚Р°РІРєРё</mdclass:n>
$(New-SynonymXml -Text "РџР»Р°РЅ СЃС‚РѕРёРјРѕСЃС‚СЊ РґРѕСЃС‚Р°РІРєРё" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecNumber 15 2) -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
		</mdclass:Attribute>
"@

Insert-BeforeClosingTag -Path $shipmentPath -TagName "Document" -Marker "<mdclass:n>Р“СЂСѓР·РѕРјРµСЃС‚Р°</mdclass:n>" -Fragment @"
	<mdclass:TabularSection uuid=""$(Get-StableGuid 'Document/РћС‚РїСЂР°РІРєР°/Р“СЂСѓР·РѕРјРµСЃС‚Р°')"">
		<mdclass:n>Р“СЂСѓР·РѕРјРµСЃС‚Р°</mdclass:n>
$(New-SynonymXml -Text "Р“СЂСѓР·РѕРјРµСЃС‚Р°" -Indent "		")
$(New-FieldXml -ElementName "Attribute" -ObjectSeed 'Document/РћС‚РїСЂР°РІРєР°/Р“СЂСѓР·РѕРјРµСЃС‚Р°' -FieldSpec @{ Name = 'РЈРїР°РєРѕРІРєР°'; Synonym = 'РЈРїР°РєРѕРІРєР°'; Type = (New-TypeSpecCatalogRef 'РЈРїР°РєРѕРІРєРё'); FillRequired = $false; Index = $true } -Indent "		")
$(New-FieldXml -ElementName "Attribute" -ObjectSeed 'Document/РћС‚РїСЂР°РІРєР°/Р“СЂСѓР·РѕРјРµСЃС‚Р°' -FieldSpec @{ Name = 'РљРѕР»РёС‡РµСЃС‚РІРѕРњРµСЃС‚'; Synonym = 'РљРѕР»РёС‡РµСЃС‚РІРѕ РјРµСЃС‚'; Type = (New-TypeSpecNumber 10 0); FillRequired = $false } -Indent "		")
$(New-FieldXml -ElementName "Attribute" -ObjectSeed 'Document/РћС‚РїСЂР°РІРєР°/Р“СЂСѓР·РѕРјРµСЃС‚Р°' -FieldSpec @{ Name = 'Р’РµСЃР¤Р°РєС‚'; Synonym = 'Р’РµСЃ С„Р°РєС‚ РєРі'; Type = (New-TypeSpecNumber 15 3); FillRequired = $false } -Indent "		")
$(New-FieldXml -ElementName "Attribute" -ObjectSeed 'Document/РћС‚РїСЂР°РІРєР°/Р“СЂСѓР·РѕРјРµСЃС‚Р°' -FieldSpec @{ Name = 'РћР±СЉРµРј'; Synonym = 'РћР±СЉРµРј Рј3'; Type = (New-TypeSpecNumber 15 3); FillRequired = $false } -Indent "		")
$(New-FieldXml -ElementName "Attribute" -ObjectSeed 'Document/РћС‚РїСЂР°РІРєР°/Р“СЂСѓР·РѕРјРµСЃС‚Р°' -FieldSpec @{ Name = 'РљРѕРјРјРµРЅС‚Р°СЂРёР№'; Synonym = 'РљРѕРјРјРµРЅС‚Р°СЂРёР№'; Type = (New-TypeSpecString 150); FillRequired = $false } -Indent "		")
	</mdclass:TabularSection>
"@

$paymentPath = Join-Path $RootDir "Documents\РћРїР»Р°С‚Р°Р—Р°РєР°Р·Р°\РћРїР»Р°С‚Р°Р—Р°РєР°Р·Р°.xml"
Insert-BeforeMarker -Path $paymentPath -SearchMarker '<mdclass:Attribute uuid="' -Marker "<mdclass:n>РЎС‚Р°С‚СѓСЃРћРїР»Р°С‚С‹</mdclass:n>" -Fragment @"
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/РћРїР»Р°С‚Р°Р—Р°РєР°Р·Р°/РЎС‚Р°С‚СѓСЃРћРїР»Р°С‚С‹')"">
			<mdclass:n>РЎС‚Р°С‚СѓСЃРћРїР»Р°С‚С‹</mdclass:n>
$(New-SynonymXml -Text "РЎС‚Р°С‚СѓСЃ РѕРїР»Р°С‚С‹" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecCatalogRef 'РЎС‚Р°С‚СѓСЃС‹') -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
			<mdclass:Indexing>Index</mdclass:Indexing>
		</mdclass:Attribute>
		<mdclass:Attribute uuid=""$(Get-StableGuid 'Document/РћРїР»Р°С‚Р°Р—Р°РєР°Р·Р°/Р¤РѕСЂРјР°РћРїР»Р°С‚С‹')"">
			<mdclass:n>Р¤РѕСЂРјР°РћРїР»Р°С‚С‹</mdclass:n>
$(New-SynonymXml -Text "Р¤РѕСЂРјР° РѕРїР»Р°С‚С‹" -Indent "			")
$(New-TypeXml -TypeSpec (New-TypeSpecEnumRef 'Р¤РѕСЂРјР°РћРїР»Р°С‚С‹') -Indent "			")
			<mdclass:FillRequired>false</mdclass:FillRequired>
			<mdclass:Indexing>Index</mdclass:Indexing>
		</mdclass:Attribute>
"@

$docsPath = Join-Path $RootDir "docs\РљРѕРЅС„РёРіСѓСЂР°С†РёРѕРЅРЅС‹Р№РљР°СЂРєР°СЃ.md"
Write-Utf8NoBom -Path $docsPath -Content @'
# РљРѕРЅС„РёРіСѓСЂР°С†РёРѕРЅРЅС‹Р№ РєР°СЂРєР°СЃ РїРѕ РўР—

## РџСЂРёРЅСЏС‚С‹Рµ РґРѕРїСѓС‰РµРЅРёСЏ

- РљРѕРЅС„РёРіСѓСЂР°С†РёСЏ СЃРѕР±РёСЂР°РµС‚СЃСЏ РєР°Рє СѓРїСЂР°РІР»РµРЅС‡РµСЃРєР°СЏ РєР°СЃС‚РѕРјРЅР°СЏ РјРѕРґРµР»СЊ РІРѕРєСЂСѓРі РґРѕРєСѓРјРµРЅС‚Р° `Р—Р°РєР°Р·`.
- РњСѓР»СЊС‚РёРІР°Р»СЋС‚РЅРѕСЃС‚СЊ РѕСЃС‚Р°РІР»РµРЅР° РЅР° СѓСЂРѕРІРЅРµ СЂРµРєРІРёР·РёС‚РѕРІ `Р’Р°Р»СЋС‚Р°` Рё `РљСѓСЂСЃР’Р°Р»СЋС‚С‹`; РѕС‚РґРµР»СЊРЅС‹Р№ СЃРїСЂР°РІРѕС‡РЅРёРє РІР°Р»СЋС‚ РїРѕРєР° РЅРµ РІРІРѕРґРёР»СЃСЏ.
- Р”Р»СЏ РїСЂРѕС†РµСЃСЃР° Р·Р°РєСѓРїРєРё РґРѕР±Р°РІР»РµРЅ РѕС‚РґРµР»СЊРЅС‹Р№ РґРѕРєСѓРјРµРЅС‚ `Р—Р°РєР°Р·РџРѕСЃС‚Р°РІС‰РёРєСѓ` РєР°Рє РѕРїС†РёРѕРЅР°Р»СЊРЅС‹Р№, РЅРѕ РІРєР»СЋС‡РµРЅРЅС‹Р№ РІ РєР°СЂРєР°СЃ.
- Р¤РѕСЂРјС‹ Рё СЂР°Р±РѕС‡РёРµ РјРµСЃС‚Р° РѕРїРёСЃР°РЅС‹ РЅР° СѓСЂРѕРІРЅРµ РїРѕРґСЃРёСЃС‚РµРј, РѕС‚С‡РµС‚РѕРІ, РїСЂРѕС†РµСЃСЃРѕСЂР° `Р Р°Р±РѕС‡РёР№РЎС‚РѕР»РњРµРЅРµРґР¶РµСЂР°` Рё РѕР±С‰РёС… РјРѕРґСѓР»РµР№.

## Р”РѕР±Р°РІР»РµРЅРЅС‹Рµ РѕР±СЉРµРєС‚С‹

### РџРµСЂРµС‡РёСЃР»РµРЅРёСЏ

- `Р РѕР»СЊРџРѕР»СЊР·РѕРІР°С‚РµР»СЏ`
- `РўРёРїРЈРІРµРґРѕРјР»РµРЅРёСЏ`
- `РўРёРїРњР°СЂС€СЂСѓС‚РЅРѕР№РўРѕС‡РєРё`
- `РўРёРїРЎРѕР±С‹С‚РёСЏРўСЂРµРєРёРЅРіР°`

### РЎРїСЂР°РІРѕС‡РЅРёРєРё

- `РўР°СЂРёС„С‹Р”РѕСЃС‚Р°РІРєРё`
- `РњР°СЂС€СЂСѓС‚С‹Р”РѕСЃС‚Р°РІРєРё`
- `РўРѕС‡РєРёРњР°СЂС€СЂСѓС‚Р°`
- `РЈРїР°РєРѕРІРєРё`

### Р”РѕРєСѓРјРµРЅС‚С‹

- `Р—Р°РєР°Р·РџРѕСЃС‚Р°РІС‰РёРєСѓ`
- `РЎРѕРїСѓС‚СЃС‚РІСѓСЋС‰РёР№Р Р°СЃС…РѕРґ`
- `Р РµРіРёСЃС‚СЂР°С†РёСЏР”РѕРєСѓРјРµРЅС‚Р°`

### Р РµРіРёСЃС‚СЂС‹ СЃРІРµРґРµРЅРёР№

- `Р­С‚Р°РїС‹Р”РѕСЃС‚Р°РІРєРё`
- `РЎРѕР±С‹С‚РёСЏРўСЂРµРєРёРЅРіР°`
- `РџРµСЂРµС…РѕРґС‹РЎС‚Р°С‚СѓСЃРѕРІ`

### Р РѕР»Рё

- `Р СѓРєРѕРІРѕРґРёС‚РµР»СЊ`
- `РђРґРјРёРЅРёСЃС‚СЂР°С‚РѕСЂ`

### РћР±С‰РёРµ РјРѕРґСѓР»Рё

- `Р›РѕРіРёРєР°РЎС‚Р°С‚СѓСЃРѕРІ`
- `Р›РѕРіРёРєР°Р¤РёРЅР°РЅСЃРѕРІ`
- `Р›РѕРіРёРєР°Р›РѕРіРёСЃС‚РёРєРё`
- `Р›РѕРіРёРєР°РЈРІРµРґРѕРјР»РµРЅРёР№`
- `РРЅРёС†РёР°Р»РёР·Р°С†РёСЏРќРЎР`
- `РњРёРіСЂР°С†РёСЏРР·Excel`
- `РџСЂР°РІР°Р”РѕСЃС‚СѓРїР°`
- `РћС‚С‡РµС‚С‹Р—Р°РєР°Р·РѕРІ`

### РћС‚С‡РµС‚С‹

- `Р РµРµСЃС‚СЂР—Р°РєР°Р·РѕРІ`
- `РљРѕРЅС‚СЂРѕР»СЊРћРїР»Р°С‚`
- `Р›РѕРіРёСЃС‚РёС‡РµСЃРєРёР№РћС‚С‡РµС‚`
- `РњР°СЂР¶РёРЅР°Р»СЊРЅРѕСЃС‚СЊР—Р°РєР°Р·РѕРІ`
- `Р”РІРёР¶РµРЅРёРµР”РµРЅРµР¶РЅС‹С…РЎСЂРµРґСЃС‚РІРџРѕР—Р°РєР°Р·Р°Рј`
- `РќРµР·Р°РІРµСЂС€РµРЅРЅС‹РµР—Р°РєР°Р·С‹`

### Р Р°Р±РѕС‡РёРµ РјРµСЃС‚Р° Рё РїРѕРґСЃРёСЃС‚РµРјС‹

- `Р Р°Р±РѕС‡РёР№РЎС‚РѕР»РњРµРЅРµРґР¶РµСЂР°`
- `РќРЎР`
- `Р—Р°РєР°Р·С‹`
- `Р¤РёРЅР°РЅСЃС‹`
- `Р›РѕРіРёСЃС‚РёРєР°`
- `РћС‚С‡РµС‚С‹`
- `РђРґРјРёРЅРёСЃС‚СЂРёСЂРѕРІР°РЅРёРµ`

## Р”РѕСЂР°Р±РѕС‚Р°РЅРЅС‹Рµ РѕР±СЉРµРєС‚С‹

- `Р—Р°РєР°Р·С‡РёРєРё`: РґРѕР±Р°РІР»РµРЅС‹ РєРѕРЅС‚Р°РєС‚РЅРѕРµ Р»РёС†Рѕ Рё РїР»Р°С‚РµР¶РЅС‹Рµ СЂРµРєРІРёР·РёС‚С‹.
- `РџРѕСЃС‚Р°РІС‰РёРєРё`: РґРѕР±Р°РІР»РµРЅС‹ РєРѕРЅС‚Р°РєС‚РЅРѕРµ Р»РёС†Рѕ Рё РїР»Р°С‚РµР¶РЅС‹Рµ СЂРµРєРІРёР·РёС‚С‹.
- `РЎРѕС‚СЂСѓРґРЅРёРєРё`: СЂРѕР»СЊ РїРµСЂРµРІРµРґРµРЅР° РЅР° РїРµСЂРµС‡РёСЃР»РµРЅРёРµ `Р РѕР»СЊРџРѕР»СЊР·РѕРІР°С‚РµР»СЏ`.
- `РўРѕРІР°СЂС‹`: РґРѕР±Р°РІР»РµРЅС‹ РµРґРёРЅРёС†Р° РёР·РјРµСЂРµРЅРёСЏ Рё РѕР±СЉРµРј.
- `Р—Р°РєР°Р·`: РґРѕР±Р°РІР»РµРЅС‹ СЃС‚Р°С‚СѓСЃ Р·Р°РєР°Р·Р°, СЃС‚Р°С‚СѓСЃ РґРѕСЃС‚Р°РІРєРё, Р°РґСЂРµСЃ РґРѕСЃС‚Р°РІРєРё, СЃРѕРіР»Р°СЃРѕРІР°РЅРЅР°СЏ РґР°С‚Р° РїРѕСЃС‚Р°РІРєРё, РјР°СЂР¶РёРЅР°Р»СЊРЅС‹Рµ РёС‚РѕРіРё.
- `РћС‚РїСЂР°РІРєР°`: РґРѕР±Р°РІР»РµРЅ РјР°СЂС€СЂСѓС‚ РґРѕСЃС‚Р°РІРєРё, РїР»Р°РЅРѕРІР°СЏ СЃС‚РѕРёРјРѕСЃС‚СЊ РґРѕСЃС‚Р°РІРєРё Рё С‚Р°Р±Р»РёС‡РЅР°СЏ С‡Р°СЃС‚СЊ `Р“СЂСѓР·РѕРјРµСЃС‚Р°`.
- `РћРїР»Р°С‚Р°Р—Р°РєР°Р·Р°`: РґРѕР±Р°РІР»РµРЅС‹ СЃС‚Р°С‚СѓСЃ РѕРїР»Р°С‚С‹ Рё С„РѕСЂРјР° РѕРїР»Р°С‚С‹.
'@

Sync-ConfigurationChildObjects

[pscustomobject]@{
    NewEnums = $enums.Count
    NewCatalogs = $catalogs.Count
    NewDocuments = $documents.Count
    NewInformationRegisters = $informationRegisters.Count
    NewRoles = 2
    NewCommonModules = $commonModules.Count
    NewReports = $reports.Count
    NewSubsystems = $subsystems.Count
    DocsFile = $docsPath
} | Format-List

