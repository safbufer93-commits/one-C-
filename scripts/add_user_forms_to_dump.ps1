param(
    [string]$RootDir = (Split-Path -Parent $PSScriptRoot),
    [string]$DumpDir = (Join-Path (Split-Path -Parent $PSScriptRoot) "_real_loadable_dump"),
    [string[]]$OnlyCatalogs = @(),
    [string[]]$OnlyDocuments = @(),
    [switch]$SkipSubsystems
)

$ErrorActionPreference = "Stop"

function Assert-InsideRoot([string]$RootPath, [string]$TargetPath) {
    $root = [IO.Path]::GetFullPath($RootPath)
    $target = [IO.Path]::GetFullPath($TargetPath)
    if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside workspace: $target"
    }
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Write-Utf8([string]$Path, [string]$Text) {
    Ensure-Dir (Split-Path -Parent $Path)
    [IO.File]::WriteAllText($Path, $Text.Trim() + "`r`n", (New-Object Text.UTF8Encoding($false)))
}

function Stable-Guid([string]$Seed) {
    $md5 = [Security.Cryptography.MD5]::Create()
    try {
        ([guid]::new($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($Seed)))).ToString()
    } finally {
        $md5.Dispose()
    }
}

function X([string]$Text) {
    return [Security.SecurityElement]::Escape($Text)
}

function Read-XmlDoc([string]$Path) {
    $xml = New-Object Xml.XmlDocument
    $xml.LoadXml([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8))
    return $xml
}

function Node-Text($Node, [string]$XPath) {
    $n = $Node.SelectSingleNode($XPath)
    if ($null -eq $n) { return $null }
    return $n.InnerText
}

function Direct-ChildNodes($Node, [string]$ParentName, [string]$ChildName) {
    return $Node.SelectNodes("./*[local-name()='$ParentName']/*[local-name()='$ChildName']")
}

function Get-ObjectInfo([string]$Kind, [string]$Path) {
    $xml = Read-XmlDoc $Path
    $root = $xml.DocumentElement.SelectSingleNode("./*[local-name()='$Kind']")
    $name = Node-Text $root "./*[local-name()='Properties']/*[local-name()='Name']"
    $childObjects = $root.SelectSingleNode("./*[local-name()='ChildObjects']")

    $attributes = @()
    foreach ($a in (Direct-ChildNodes $root "ChildObjects" "Attribute")) {
        $attrName = Node-Text $a "./*[local-name()='Properties']/*[local-name()='Name']"
        $typeName = Node-Text $a "./*[local-name()='Properties']/*[local-name()='Type']/*[local-name()='Type']"
        $attributes += [pscustomobject]@{
            Name = $attrName
            Type = $typeName
            Kind = "Attribute"
        }
    }

    $tabs = @()
    foreach ($ts in (Direct-ChildNodes $root "ChildObjects" "TabularSection")) {
        $tabName = Node-Text $ts "./*[local-name()='Properties']/*[local-name()='Name']"
        $tabAttrs = @()
        foreach ($a in (Direct-ChildNodes $ts "ChildObjects" "Attribute")) {
            $attrName = Node-Text $a "./*[local-name()='Properties']/*[local-name()='Name']"
            $typeName = Node-Text $a "./*[local-name()='Properties']/*[local-name()='Type']/*[local-name()='Type']"
            $tabAttrs += [pscustomobject]@{
                Name = $attrName
                Type = $typeName
                Kind = "Attribute"
            }
        }
        $tabs += [pscustomobject]@{
            Name = $tabName
            Attributes = $tabAttrs
        }
    }

    return [pscustomobject]@{
        Kind = $Kind
        Name = $name
        Path = $Path
        Attributes = $attributes
        TabularSections = $tabs
        HasChildObjects = ($null -ne $childObjects)
    }
}

function New-FormMetaXml([string]$FormName, [string]$Synonym) {
    $uuid = Stable-Guid "FormMeta/$FormName/$Synonym"
@"
<?xml version="1.0" encoding="UTF-8"?>
<MetaDataObject xmlns="http://v8.1c.ru/8.3/MDClasses" xmlns:app="http://v8.1c.ru/8.2/managed-application/core" xmlns:cfg="http://v8.1c.ru/8.1/data/enterprise/current-config" xmlns:cmi="http://v8.1c.ru/8.2/managed-application/cmi" xmlns:ent="http://v8.1c.ru/8.1/data/enterprise" xmlns:lf="http://v8.1c.ru/8.2/managed-application/logform" xmlns:style="http://v8.1c.ru/8.1/data/ui/style" xmlns:sys="http://v8.1c.ru/8.1/data/ui/fonts/system" xmlns:v8="http://v8.1c.ru/8.1/data/core" xmlns:v8ui="http://v8.1c.ru/8.1/data/ui" xmlns:web="http://v8.1c.ru/8.1/data/ui/colors/web" xmlns:win="http://v8.1c.ru/8.1/data/ui/colors/windows" xmlns:xen="http://v8.1c.ru/8.3/xcf/enums" xmlns:xpr="http://v8.1c.ru/8.3/xcf/predef" xmlns:xr="http://v8.1c.ru/8.3/xcf/readable" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="2.20">
	<Form uuid="$uuid">
		<Properties>
			<Name>$(X $FormName)</Name>
			<Synonym>
				<v8:item>
					<v8:lang>ru</v8:lang>
					<v8:content>$(X $Synonym)</v8:content>
				</v8:item>
			</Synonym>
			<Comment/>
			<FormType>Managed</FormType>
			<IncludeHelpInContents>false</IncludeHelpInContents>
			<UsePurposes>
				<v8:Value xsi:type="app:ApplicationUsePurpose">PersonalComputer</v8:Value>
			</UsePurposes>
		</Properties>
	</Form>
</MetaDataObject>
"@
}

function Add-Context([string]$BaseName, [ref]$Id, [string]$Indent = "`t`t`t") {
    $ctx = $Id.Value; $Id.Value++
    $tip = $Id.Value; $Id.Value++
@"
$Indent<ContextMenu name="$(X $BaseName)КонтекстноеМеню" id="$ctx"/>
$Indent<ExtendedTooltip name="$(X $BaseName)РасширеннаяПодсказка" id="$tip"/>
"@
}

function New-FieldXml([string]$Name, [string]$DataPath, [string]$TypeName, [ref]$Id, [bool]$Readonly = $false, [string]$Indent = "`t`t") {
    $fieldId = $Id.Value; $Id.Value++
    $safeName = ($Name -replace '[^\p{L}\p{Nd}_]', '')
    if (-not $safeName) { $safeName = "Поле$fieldId" }
    $context = Add-Context $safeName $Id ("$Indent`t")
    if ($TypeName -eq "xs:boolean") {
@"
$Indent<CheckBoxField name="$(X $safeName)" id="$fieldId">
$Indent`t<DataPath>$(X $DataPath)</DataPath>
$Indent`t<CheckBoxType>Auto</CheckBoxType>
$context
$Indent</CheckBoxField>
"@
    } elseif ($Readonly) {
@"
$Indent<LabelField name="$(X $safeName)" id="$fieldId">
$Indent`t<DataPath>$(X $DataPath)</DataPath>
$context
$Indent</LabelField>
"@
    } else {
@"
$Indent<InputField name="$(X $safeName)" id="$fieldId">
$Indent`t<DataPath>$(X $DataPath)</DataPath>
$Indent`t<EditMode>EnterOnInput</EditMode>
$context
$Indent</InputField>
"@
    }
}

function New-TableXml($Tab, [ref]$Id) {
    $tableId = $Id.Value; $Id.Value++
    $name = $Tab.Name
    $safeName = ($name -replace '[^\p{L}\p{Nd}_]', '')
    $contextId = $Id.Value; $Id.Value++
    $barId = $Id.Value; $Id.Value++
    $tipId = $Id.Value; $Id.Value++
    $items = @()
    $items += (New-FieldXml "$safeName`НомерСтроки" "Объект.$name.LineNumber" "" $Id $true "`t`t`t")
    foreach ($attr in $Tab.Attributes) {
        $items += (New-FieldXml "$safeName$($attr.Name)" "Объект.$name.$($attr.Name)" $attr.Type $Id $false "`t`t`t")
    }
@"
		<Table name="$(X $safeName)" id="$tableId">
			<Representation>List</Representation>
			<AutoInsertNewRow>true</AutoInsertNewRow>
			<EnableStartDrag>true</EnableStartDrag>
			<EnableDrag>true</EnableDrag>
			<DataPath>Объект.$(X $name)</DataPath>
			<RowFilter xsi:nil="true"/>
			<ContextMenu name="$(X $safeName)КонтекстноеМеню" id="$contextId"/>
			<AutoCommandBar name="$(X $safeName)КоманднаяПанель" id="$barId"/>
			<ExtendedTooltip name="$(X $safeName)РасширеннаяПодсказка" id="$tipId"/>
			<ChildItems>
$($items -join "`r`n")
			</ChildItems>
		</Table>
"@
}

function New-ObjectFormXml($Info, [string]$KindPrefix) {
    $id = 1
    $idRef = [ref]$id
    $items = @()
    if ($Info.Kind -eq "Document") {
        $items += (New-FieldXml "Номер" "Объект.Number" "xs:string" $idRef $false)
        $items += (New-FieldXml "Дата" "Объект.Date" "xs:dateTime" $idRef $false)
    } else {
        $items += (New-FieldXml "Код" "Объект.Code" "xs:string" $idRef $false)
        $items += (New-FieldXml "Наименование" "Объект.Description" "xs:string" $idRef $false)
    }
    foreach ($attr in $Info.Attributes) {
        $items += (New-FieldXml $attr.Name "Объект.$($attr.Name)" $attr.Type $idRef $false)
    }
    foreach ($tab in $Info.TabularSections) {
        $items += (New-TableXml $tab $idRef)
    }
    $type = "cfg:$KindPrefix`Object.$($Info.Name)"
@"
<?xml version="1.0" encoding="UTF-8"?>
<Form xmlns="http://v8.1c.ru/8.3/xcf/logform" xmlns:app="http://v8.1c.ru/8.2/managed-application/core" xmlns:cfg="http://v8.1c.ru/8.1/data/enterprise/current-config" xmlns:dcscor="http://v8.1c.ru/8.1/data-composition-system/core" xmlns:dcsset="http://v8.1c.ru/8.1/data-composition-system/settings" xmlns:ent="http://v8.1c.ru/8.1/data/enterprise" xmlns:lf="http://v8.1c.ru/8.2/managed-application/logform" xmlns:style="http://v8.1c.ru/8.1/data/ui/style" xmlns:sys="http://v8.1c.ru/8.1/data/ui/fonts/system" xmlns:v8="http://v8.1c.ru/8.1/data/core" xmlns:v8ui="http://v8.1c.ru/8.1/data/ui" xmlns:web="http://v8.1c.ru/8.1/data/ui/colors/web" xmlns:win="http://v8.1c.ru/8.1/data/ui/colors/windows" xmlns:xr="http://v8.1c.ru/8.3/xcf/readable" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="2.20">
	<AutoCommandBar name="" id="-1"/>
	<ChildItems>
$($items -join "`r`n")
	</ChildItems>
	<Attributes>
		<Attribute name="Объект" id="1">
			<Type>
				<v8:Type>$type</v8:Type>
			</Type>
			<MainAttribute>true</MainAttribute>
			<SavedData>true</SavedData>
		</Attribute>
	</Attributes>
</Form>
"@
}

function New-ListFormXml($Info, [string]$KindPrefix) {
    $id = 1
    $idRef = [ref]$id
    $columns = @()
    $columns += (New-FieldXml "Ссылка" "Список.Ref" "" $idRef $true "`t`t`t")
    if ($Info.Kind -eq "Document") {
        $columns += (New-FieldXml "Дата" "Список.Date" "" $idRef $true "`t`t`t")
        $columns += (New-FieldXml "Номер" "Список.Number" "" $idRef $true "`t`t`t")
    } else {
        $columns += (New-FieldXml "Код" "Список.Code" "" $idRef $true "`t`t`t")
        $columns += (New-FieldXml "Наименование" "Список.Description" "" $idRef $true "`t`t`t")
    }
    foreach ($attr in ($Info.Attributes | Select-Object -First 10)) {
        $columns += (New-FieldXml $attr.Name "Список.$($attr.Name)" $attr.Type $idRef $true "`t`t`t")
    }
    $mainTable = "$KindPrefix.$($Info.Name)"
@"
<?xml version="1.0" encoding="UTF-8"?>
<Form xmlns="http://v8.1c.ru/8.3/xcf/logform" xmlns:app="http://v8.1c.ru/8.2/managed-application/core" xmlns:cfg="http://v8.1c.ru/8.1/data/enterprise/current-config" xmlns:dcscor="http://v8.1c.ru/8.1/data-composition-system/core" xmlns:dcsset="http://v8.1c.ru/8.1/data-composition-system/settings" xmlns:ent="http://v8.1c.ru/8.1/data/enterprise" xmlns:lf="http://v8.1c.ru/8.2/managed-application/logform" xmlns:style="http://v8.1c.ru/8.1/data/ui/style" xmlns:sys="http://v8.1c.ru/8.1/data/ui/fonts/system" xmlns:v8="http://v8.1c.ru/8.1/data/core" xmlns:v8ui="http://v8.1c.ru/8.1/data/ui" xmlns:web="http://v8.1c.ru/8.1/data/ui/colors/web" xmlns:win="http://v8.1c.ru/8.1/data/ui/colors/windows" xmlns:xr="http://v8.1c.ru/8.3/xcf/readable" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" version="2.20">
	<AutoCommandBar name="" id="-1"/>
	<ChildItems>
		<Table name="Список" id="1">
			<Representation>List</Representation>
			<DefaultItem>true</DefaultItem>
			<UseAlternationRowColor>true</UseAlternationRowColor>
			<DataPath>Список</DataPath>
			<RowPictureDataPath>Список.DefaultPicture</RowPictureDataPath>
			<AutoRefresh>false</AutoRefresh>
			<AutoRefreshPeriod>60</AutoRefreshPeriod>
			<UpdateOnDataChange>Auto</UpdateOnDataChange>
			<ContextMenu name="СписокКонтекстноеМеню" id="2"/>
			<AutoCommandBar name="СписокКоманднаяПанель" id="3"/>
			<ExtendedTooltip name="СписокРасширеннаяПодсказка" id="4"/>
			<ChildItems>
$($columns -join "`r`n")
			</ChildItems>
		</Table>
	</ChildItems>
	<Attributes>
		<Attribute name="Список" id="1">
			<Type>
				<v8:Type>cfg:DynamicList</v8:Type>
			</Type>
			<MainAttribute>true</MainAttribute>
			<Settings xsi:type="DynamicList">
				<ManualQuery>false</ManualQuery>
				<DynamicDataRead>true</DynamicDataRead>
				<MainTable>$mainTable</MainTable>
			</Settings>
		</Attribute>
	</Attributes>
</Form>
"@
}

function Ensure-ObjectForms($Info) {
    $kindPrefix = if ($Info.Kind -eq "Document") { "Document" } else { "Catalog" }
    $objectForm = if ($Info.Kind -eq "Document") { "ФормаДокумента" } else { "ФормаЭлемента" }
    $listForm = "ФормаСписка"
    $baseDir = Join-Path (Split-Path -Parent $Info.Path) $Info.Name
    $formsDir = Join-Path $baseDir "Forms"

    $objectFormSynonym = if ($Info.Kind -eq "Document") {
        "Форма документа $($Info.Name)"
    } else {
        "Форма элемента $($Info.Name)"
    }
    $formDefinitions = @(
        @{ Name = $objectForm; Syn = $objectFormSynonym; Xml = (New-ObjectFormXml $Info $kindPrefix) },
        @{ Name = $listForm; Syn = "Форма списка $($Info.Name)"; Xml = (New-ListFormXml $Info $kindPrefix) }
    )

    if ($Info.Kind -eq "Document" -and $Info.Name -eq "Заказ") {
        $formDefinitions += @{ Name = "ФормаСогласования"; Syn = "Форма согласования заказа"; Xml = (New-ObjectFormXml $Info $kindPrefix) }
    }

    foreach ($form in $formDefinitions) {
        $formMetaPath = Join-Path $formsDir "$($form.Name).xml"
        $formXmlPath = Join-Path (Join-Path $formsDir $form.Name) "Ext\Form.xml"
        Write-Utf8 $formMetaPath (New-FormMetaXml $form.Name $form.Syn)
        Write-Utf8 $formXmlPath $form.Xml
    }

    $text = [IO.File]::ReadAllText($Info.Path, [Text.Encoding]::UTF8)
    $defaultObjectTag = "DefaultObjectForm"
    if ($Info.Kind -eq "Catalog") {
        $defaultObjectValue = "Catalog.$($Info.Name).Form.$objectForm"
        $defaultListValue = "Catalog.$($Info.Name).Form.$listForm"
    } else {
        $defaultObjectValue = "Document.$($Info.Name).Form.$objectForm"
        $defaultListValue = "Document.$($Info.Name).Form.$listForm"
    }

    if ($text -match "<DefaultObjectForm>") {
        $text = [Text.RegularExpressions.Regex]::Replace($text, "<DefaultObjectForm>.*?</DefaultObjectForm>", "<DefaultObjectForm>$defaultObjectValue</DefaultObjectForm>", [Text.RegularExpressions.RegexOptions]::Singleline)
    } elseif ($text -match "<DefaultObjectForm\s*/>") {
        $text = [Text.RegularExpressions.Regex]::Replace($text, "<DefaultObjectForm\s*/>", "<DefaultObjectForm>$defaultObjectValue</DefaultObjectForm>", [Text.RegularExpressions.RegexOptions]::Singleline)
    } else {
        $text = $text.Replace("<UseStandardCommands>true</UseStandardCommands>", "<UseStandardCommands>true</UseStandardCommands>`r`n`t`t`t<DefaultObjectForm>$defaultObjectValue</DefaultObjectForm>")
    }

    if ($text -match "<DefaultListForm>") {
        $text = [Text.RegularExpressions.Regex]::Replace($text, "<DefaultListForm>.*?</DefaultListForm>", "<DefaultListForm>$defaultListValue</DefaultListForm>", [Text.RegularExpressions.RegexOptions]::Singleline)
    } elseif ($text -match "<DefaultListForm\s*/>") {
        $text = [Text.RegularExpressions.Regex]::Replace($text, "<DefaultListForm\s*/>", "<DefaultListForm>$defaultListValue</DefaultListForm>", [Text.RegularExpressions.RegexOptions]::Singleline)
    } else {
        $text = $text.Replace("<DefaultObjectForm>$defaultObjectValue</DefaultObjectForm>", "<DefaultObjectForm>$defaultObjectValue</DefaultObjectForm>`r`n`t`t`t<DefaultListForm>$defaultListValue</DefaultListForm>")
    }

    $allFormNames = @($objectForm, $listForm)
    if ($Info.Kind -eq "Document" -and $Info.Name -eq "Заказ") {
        $allFormNames += "ФормаСогласования"
    }

    # Удаляем ранее добавленные теги <Form>, чтобы не накапливать дубли
    # при повторной генерации и при объектах с несколькими табличными частями.
    $text = [Text.RegularExpressions.Regex]::Replace(
        $text,
        "\r?\n\s*<Form>.*?</Form>",
        "",
        [Text.RegularExpressions.RegexOptions]::Singleline)

    $formRefs = foreach ($formName in $allFormNames) {
        "`t`t`t<Form>$formName</Form>"
    }
    $formsBlock = "`r`n" + ($formRefs -join "`r`n") + "`r`n"

    if ($text -match "<ChildObjects>") {
        if ($text -match "`r?`n\s*<TabularSection ") {
            $tabularRegex = New-Object Text.RegularExpressions.Regex(
                "(`r?`n\s*<TabularSection )",
                [Text.RegularExpressions.RegexOptions]::Singleline)
            $text = $tabularRegex.Replace($text, "$formsBlock`$1", 1)
        } else {
            $text = $text.Replace("`r`n`t`t</ChildObjects>", "$formsBlock`t`t</ChildObjects>")
        }
    }

    [IO.File]::WriteAllText($Info.Path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Set-SubsystemContent([string]$SubsystemName, [string[]]$Refs) {
    $path = Join-Path $DumpDir "Subsystems\$SubsystemName.xml"
    if (-not (Test-Path -LiteralPath $path)) { return }
    $items = foreach ($ref in $Refs) {
        "`t`t`t`t<xr:Item xsi:type=""xr:MDObjectRef"">$ref</xr:Item>"
    }
    $contentBlock = @(
        "`t`t`t<Content>"
        ($items -join "`r`n")
        "`t`t`t</Content>"
    ) -join "`r`n"
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($text -match "<Content[\s\S]*?</Content>") {
        $text = [Text.RegularExpressions.Regex]::Replace($text, "<Content[\s\S]*?</Content>", $contentBlock, [Text.RegularExpressions.RegexOptions]::Singleline)
    } elseif ($text -match "<Content\s*/>") {
        $text = [Text.RegularExpressions.Regex]::Replace($text, "<Content\s*/>", $contentBlock, [Text.RegularExpressions.RegexOptions]::Singleline)
    } else {
        $text = $text.Replace("<Comment/>", "<Comment/>`r`n$contentBlock")
    }
    if ($text -notmatch "<IncludeInCommandInterface>") {
        $text = $text.Replace("<Comment/>", "<Comment/>`r`n`t`t`t<IncludeHelpInContents>true</IncludeHelpInContents>`r`n`t`t`t<IncludeInCommandInterface>true</IncludeInCommandInterface>`r`n`t`t`t<UseOneCommand>false</UseOneCommand>`r`n`t`t`t<Explanation/>`r`n`t`t`t<Picture/>")
    }
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Fix-DefaultRole() {
    $cfgPath = Join-Path $DumpDir "Configuration.xml"
    $text = [IO.File]::ReadAllText($cfgPath, [Text.Encoding]::UTF8)
    if ($text -match "<DefaultRoles>[\s\S]*?</DefaultRoles>") {
        $text = [Text.RegularExpressions.Regex]::Replace($text, "<DefaultRoles>[\s\S]*?</DefaultRoles>", "<DefaultRoles>`r`n`t`t`t<Role>Role.ПолныеПрава</Role>`r`n`t`t</DefaultRoles>", [Text.RegularExpressions.RegexOptions]::Singleline)
    } elseif ($text -match "<DefaultRoles\s*/>") {
        $text = [Text.RegularExpressions.Regex]::Replace($text, "<DefaultRoles\s*/>", "<DefaultRoles>`r`n`t`t`t<Role>Role.ПолныеПрава</Role>`r`n`t`t</DefaultRoles>", [Text.RegularExpressions.RegexOptions]::Singleline)
    }
    [IO.File]::WriteAllText($cfgPath, $text, (New-Object Text.UTF8Encoding($false)))
}

Assert-InsideRoot $RootDir $DumpDir
if (-not (Test-Path -LiteralPath (Join-Path $DumpDir "Configuration.xml"))) {
    throw "Configuration.xml not found in $DumpDir"
}

$catalogs = Get-ChildItem -Path (Join-Path $DumpDir "Catalogs") -Filter "*.xml" -File | Sort-Object Name
$documents = Get-ChildItem -Path (Join-Path $DumpDir "Documents") -Filter "*.xml" -File | Sort-Object Name
if ($OnlyCatalogs.Count -gt 0) {
    $catalogs = $catalogs | Where-Object { $OnlyCatalogs -contains $_.BaseName }
}
if ($OnlyDocuments.Count -gt 0) {
    $documents = $documents | Where-Object { $OnlyDocuments -contains $_.BaseName }
}

foreach ($file in $catalogs) {
    Ensure-ObjectForms (Get-ObjectInfo "Catalog" $file.FullName)
}
foreach ($file in $documents) {
    Ensure-ObjectForms (Get-ObjectInfo "Document" $file.FullName)
}

if (-not $SkipSubsystems) {
Set-SubsystemContent "Администрирование" @(
    "DataProcessor.РабочийСтолМенеджера",
    "Catalog.Сотрудники",
    "Catalog.Статусы"
)
Set-SubsystemContent "Заказы" @(
    "Document.Заказ",
    "Document.ЗаказПоставщику",
    "Document.ФинальнаяСправка",
    "Catalog.Заказчики",
    "Catalog.Товары",
    "Report.РеестрЗаказов",
    "Report.МаржинальностьЗаказов"
)
Set-SubsystemContent "Логистика" @(
    "Document.Отправка",
    "Catalog.Перевозчики",
    "Catalog.МаршрутыДоставки",
    "Catalog.ТочкиМаршрута",
    "Catalog.Упаковки",
    "Report.ЛогистическийОтчет"
)
Set-SubsystemContent "НСИ" @(
    "Catalog.ВидыЭтаповДоставки",
    "Catalog.Заказчики",
    "Catalog.МаршрутыДоставки",
    "Catalog.НормативыДоставки",
    "Catalog.Перевозчики",
    "Catalog.Поставщики",
    "Catalog.Сотрудники",
    "Catalog.Статусы",
    "Catalog.СтатьиДДС",
    "Catalog.СтатьиРасходов",
    "Catalog.ТарифыДоставки",
    "Catalog.Товары",
    "Catalog.ТочкиМаршрута",
    "Catalog.Упаковки"
)
Set-SubsystemContent "Отчеты" @(
    "Report.ДвижениеДенежныхСредствПоЗаказам",
    "Report.КонтрольОплат",
    "Report.ЛогистическийОтчет",
    "Report.МаржинальностьЗаказов",
    "Report.НезавершенныеЗаказы",
    "Report.РеестрЗаказов",
    "Document.ФинальнаяСправка"
)
Set-SubsystemContent "Финансы" @(
    "Document.ОплатаЗаказа",
    "Document.СопутствующийРасход",
    "Document.ФинальнаяСправка",
    "Catalog.СтатьиДДС",
    "Catalog.СтатьиРасходов",
    "Report.КонтрольОплат",
    "Report.ДвижениеДенежныхСредствПоЗаказам"
)
}
Fix-DefaultRole

[pscustomobject]@{
    DumpDir = $DumpDir
    CatalogForms = $catalogs.Count * 2
    DocumentForms = $documents.Count * 2
    SubsystemsUpdated = if ($SkipSubsystems) { 0 } else { 6 }
} | Format-List


