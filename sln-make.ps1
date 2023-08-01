# Copyright (C) 2022 Giuseppe Emanuele Messina - https://github.com/emanuelemessina
# This code is licensed under the MIT License (see https://github.com/emanuelemessina/sln-make/blob/master/LICENSE)

# Documentation: https://github.com/emanuelemessina/sln-make

# sln-make.inix file must be placed next to CMakeLists.txt, as the project root directory is set to the inix location
# The solution must have already been generated at with CMake and the CMakeCache must be present.

# Philosophy: no distinction between debug/release configuration per se, that is done with macros, especially $(Configuration)

#########################################################

# PARAMS

param(
    [Parameter(
    HelpMessage="Project Root Directory where sln-make.inix is located, alongside CMakeLists.txt. If left blank it's assumed to be PWD. Will be available as the solution macro `$(ProjectRootDir).")
    ]
    [string]
    $projectRootDir = (Get-Location).Path,

    [Parameter(
    HelpMessage="Keep the console open and wait for key press before exiting.")
    ]
    [switch]
    $keepOpen = $false
)

#########################################################

# helper functions

$tags = @{
    error = "Error"
    loaded = "Loaded"
    info = "Info"
    saved = "Saved"
    warning = "Warning"
}

function log ($tag, $msg){

    $foregroundColor = (get-host).ui.rawui.ForegroundColor
    $backgroundColor = (get-host).ui.rawui.BackgroundColor
    
    switch($tag){
        $tags.error {
            $foregroundColor = "red"
            Break
        }
        $tags.loaded {
            $foregroundColor = "green"
            Break
        }
        $tags.info {
            $foregroundColor = "cyan"
            Break
        }
        $tags.saved {
            $foregroundColor = "magenta"
            Break
        }
    }

    if(($foregroundColor -eq -1) -or ($backgroundColor -eq -1)){
        Write-Host -NoNewline "[$($tag)] " 
    }
    else {
        Write-Host -NoNewline "[$($tag)] " -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor -ErrorAction Ignore
    }
    Write-Host "$($msg)"
}

Function pause ($message)
{
    # Check if running Powershell ISE
    if ($psISE)
    {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("$message")
    }
    else
    {
        Write-Host "$message" -ForegroundColor Yellow
        $host.ui.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

function end(){
    if($keepOpen){
        pause "Press any key to continue"
    }
    Exit
}

# from $xml object returns the name space manager ([ref]$outNsm)
function getXmlNSM($xml, [ref]$outNsm){
    $ns = $xml.DocumentElement.NamespaceURI
    $outNsm.Value = New-Object Xml.XmlNamespaceManager($xml.NameTable)
    $outNsm.Value.AddNamespace('ns', $ns)
    # because xml is namespaced, selecting node is done like this
    # $element = $xml.SelectSingleNode('//ns:NodeName', $nsm)
}

function loadXml($path, [ref]$xml, [ref]$nsm){
    $xml_ = New-Object XML
    $xml_.Load($path)

    $nsm_ = $null
    getXmlNSM $xml_ ([ref]$nsm_)
    
    $xml.Value = $xml_
    $nsm.Value = $nsm_
}

function xml_deleteAllChildren($parent, $childName, $nsm){
    $ChildNodes = $parent.SelectNodes("//$($childName)", $nsm)
    foreach($Child in $ChildNodes){
        $Child.ParentNode.RemoveChild($Child)
    }
}

function file_exists($path){
    return (Test-Path -Path "$($path)" -PathType Leaf)
}

function parse_boolean($string){
    return [System.Convert]::ToBoolean($string)
}

#########################################################

# GET INI

function Get-InixContent ($file){
    
    $ini = [ordered]@{
        root = [ordered]@{
            comments = @()
        }
    }
    
    $section = $null
    
    $insideBlock = $false
    
    switch -regex -file $file
    {
        "<([^/].+)>" # block section
        {
            $insideBlock = $true
    
            $section = $matches[1]
            $ini[$section] = ""

            Continue
        }
        "</($($section))>" # end block section
        {
            $insideBlock = $false
            Continue
        }
        "(.*)" # inside block line
        {
            if($insideBlock){
                $ini[$section] += ("$($matches[1])`r`n")
                Continue
            }
        }

        "^\[(.+)\]$" # Section
        {
            if($insideBlock){ Continue }

            $section = $matches[1]
            $ini[$section] = [ordered]@{}
            $ini[$section].comments = @()

            Continue
        }
        "^;(.+)$" # Comment
        {
            if($insideBlock){ Continue }

            $value = $matches[1]
            if($null -eq $section){
                $ini.root.comments += $value
            }
            else{
                $ini[$section].comments += $value
            }
        }
        "^([^;\n\r]\w+)\s*=\s*(.+)$" # Key
        {

            if($insideBlock){ Continue }

            $name,$value = $matches[1..2]

            if($null -eq $section){
                $ini['root'][$name] = $value
            }
            else{
                $ini[$section][$name] = $value
            }
        }


        Default{
        }
    }
    return $ini
}

$iniPath = "$($projectRootDir)\sln-make.inix"

if( -not (file_exists $iniPath)){
    log $tags.error "No sln-make.inix found in $($projectRootDir)"
    end
}

$ini = Get-InixContent $iniPath

#########################################################

# GET INI VARS

function get($ini_var, [ref]$out, $log_name){
    $empty = ($null -eq $ini_var) -or ("" -eq $ini_var)
    if( -not $empty){
        log $tags.info "$($log_name): $($ini_var)"
    }
    $out.Value = $ini_var
    return -not $empty
}

#--- Root Vars---#

$projectName = $null
if( -not (get $ini.root['projectName'] ([ref]$projectName) "Project Name")){
    log $tags.error "projectName not set, aborted."
    end
}

# solution directory relative to the project root dir
$slnDir = $null
if( -not (get $ini.root['slnDir'] ([ref]$slnDir) "Solution directory")){
    log $tags.error "slnDir not set, aborted."
    end
}
# set solution directory to absolute
$slnDir = Join-Path $projectRootDir $slnDir

# TRY TO DELETE .VS FOLDER

$vsDir = "$($slnDir)\.vs"

if (Test-Path -Path $vsDir) {
    log $tags.info "Found $($vsDir), trying to delete..."
    try{
        Remove-Item $vsDir -Force -Recurse -ErrorAction Stop
        log $tags.saved "$($vsDir) deleted, fresh start."
    }
    catch{
        log $tags.warning "Cannot delete $($vsDir), it's probably in use or the script doesn't have permission.`r`nPlease delete it manually to ensure a fresh start (Visual Studio might have cached previous settings)."
    }
} 

# CHECK CMAKE CACHE BEFORE CONTINUING

if(-not (file_exists "$($slnDir)\CMakeCache.txt")){
    log $tags.error "CMakeCache not found, please configure and generate the solution with CMake first"
    end
}
else {
    log $tags.info "Found CMakeCache. Regenerating solution..."
    cmake $slnDir
    if(-not $?){
        log $tags.error "Exited with $($lastexitcode)"
        end
    }
}

#---- Debug ----#

$debuggerAttach = $null
if( get $ini.debug['attach'] ([ref]$debuggerAttach) "Debugger attach"){
    $debuggerAttach = parse_boolean $debuggerAttach
}

$debuggerFlavor = $null
get $ini.debug['flavor'] ([ref]$debuggerFlavor) "Debugger flavor" | Out-Null

$debugCommand = $null;
get $ini.debug['command'] ([ref]$debugCommand) "Debug command" | Out-Null

#---- User Macros ----#

# automatically set the macro ProjectRootDir
$userMacros = [ordered]@{
    ProjectRootDir = "$( if($projectRootDir -eq "."){ $PWD } else { $projectRootDir } )"
}

$ini.macros.Remove('comments')

foreach ($macro in ($ini.macros.Keys)){
    $value = $ini.macros[$macro]
    $userMacros[$macro] = $value
}

log $tags.info "User Macros:"
$userMacros

#---- General ----#

$outDir = $null
if( get $ini.general['outDir'] ([ref]$outDir) "General->OutDir" ){}
$intDir = $null
if( get $ini.general['intDir'] ([ref]$intDir) "General->IntDir" ){}

#---- Build Events ----#

$pre_link_command = $null
if( get $ini['pre-link'] ([ref]$pre_link_command) "Pre-Link Command" ){}
$post_build_command = $null
if( get $ini['post-build'] ([ref]$post_build_command) "Post-Build Command"){}

#---- Custom Build Tool ----#

$customBuildToolCommand = $null
if( get $ini['custom-build'] ([ref]$customBuildToolCommand) "Custom Build Tool Command" ){}

#########################################################

# set helper variables

$solutionFile = "$($slnDir)\$($projectName).sln"

# check if solution exists

if(-not (file_exists $solutionFile))
{
    log $tags.error "Solution $($solutionFile) file not found"
    end
}

$projectXmlPath = "$($slnDir)\$($projectName).vcxproj"

$userXmlPath = "$($projectXmlPath).user"

$projectPropsPath = "$($slnDir)\$($projectName).props"

$xml_start_string = "<?xml version=`"1.0`" encoding=`"utf-8`"?>
                    <Project ToolsVersion=`"Current`" xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">
                    "

$xml_end_string = "</Project>"

$xml_configuration_label_debug = "'`$(Configuration)|`$(Platform)'=='Debug|x64'"
$xml_configuration_label_release = "'`$(Configuration)|`$(Platform)'=='Release|x64'"

# helper methods

# Searches between $nodes the node with the specified $conf_label and returns ([ref]$found) 
function getConfigurationNode($nodes, $conf_label, [ref]$found){
    $found.Value = $nodes | Where-Object {$_.Condition -eq $conf_label}
}

# Get each configuration node from $src_nodes and applies $lambda = { param($node) ... } to it
function applyToAllConfs($src_nodes, $lambda){
    $node_debug = $null
    $node_release = $null
    getConfigurationNode $src_nodes $xml_configuration_label_debug ([ref]$node_debug)
    getConfigurationNode $src_nodes $xml_configuration_label_release ([ref]$node_release)
    foreach($node in ($node_debug, $node_release) ){
        $lambda.Invoke($node)
    }
}

#########################################################

#               APPLY FOUND SETTINGS

#########################################################


# Set Debug properties

if(file_exists $userXmlPath){
    Remove-Item $userXmlPath
    log $tags.info "User configuration $($userXmlPath) found. Overwriting..."
}

New-Item $userXmlPath | Out-Null

$debug_xml_string = $xml_start_string 

$debug_xml_string += "<PropertyGroup Condition=`"$($xml_configuration_label_debug)`">"

if($debuggerAttach){
    $debug_xml_string += "<LocalDebuggerAttach>true</LocalDebuggerAttach>"
}

switch($debuggerFlavor){
    'local'{ 
        $debug_xml_string += "<DebuggerFlavor>WindowsLocalDebugger</DebuggerFlavor>" 
        Break 
    }
}

if($debugCommand){
    $debug_xml_string += "<LocalDebuggerCommand>$($debugCommand)</LocalDebuggerCommand>"
}

$debug_xml_string += "</PropertyGroup>"

$debug_xml_string += $xml_end_string

Set-Content $userXmlPath $debug_xml_string

log $tags.saved "User configuration $($userXmlPath) saved."


#########################################################

# set macros

if(file_exists $projectPropsPath){
    Remove-Item $projectPropsPath
    log $tags.info "Props file $($projectPropsPath) found. Overwriting..."
}

New-Item $projectPropsPath | Out-Null

$macros_nodes = ""
$build_macros = ""

function addMacro($name, $value){
    $script:macros_nodes += "
        <$($name)>$($value)</$($name)>
    "
    $script:build_macros += "
        <BuildMacro Include=`"$($name)`">
            <Value>`$($($name))</Value>
        </BuildMacro>
    "
}

foreach ($macro in $userMacros.GetEnumerator()) {
    addMacro $macro.Name $macro.Value
}

$props_xml_string = $xml_start_string

$props_xml_string += "<ImportGroup Label=`"PropertySheets`" />"

$props_xml_string += "<PropertyGroup Label=`"UserMacros`">"

$props_xml_string += $macros_nodes

$props_xml_string += "</PropertyGroup>"

$props_xml_string += "<ItemGroup>"

$props_xml_string += $build_macros

$props_xml_string += "</ItemGroup>"

$props_xml_string += $xml_end_string


Set-Content $projectPropsPath $props_xml_string | Out-Null

log $tags.saved "Project props $($projectPropsPath) saved."

#########################################################

#                   open project xml                    #

#########################################################

$projectXml = $null
$projectXmlNsm = $null
loadXml $projectXmlPath ([ref]$projectXml) ([ref]$projectXmlNsm)
$ns = $projectXml.Project.NamespaceURI

#########################################################

# bind props file to project

$nodeBefore = $projectXml.Project.ImportGroup | Where-Object {$_.Label -eq "PropertySheets"} 

$importGroup = $projectXml.CreateElement("ImportGroup", $ns)
$importGroup.SetAttribute("Label", "PropertySheets")
$importProject = $projectXml.CreateElement("Import", $ns)
$importProject.SetAttribute("Project", "$($projectName).props")
$importGroup.AppendChild($importProject)
$importGroup.SetAttribute("Condition", $xml_configuration_label_debug)

$projectXml.Project.InsertAfter($importGroup, $nodeBefore)

$importGroup2 = $importGroup.Clone()
$importGroup2.SetAttribute("Condition", $xml_configuration_label_release)

$projectXml.Project.InsertAfter($importGroup2, $nodeBefore)

#########################################################

# set output directory

if($outDir)
{
    applyToAllConfs $projectXml.Project.PropertyGroup.OutDir { param($outDirNode) $outDirNode.InnerText = $outDir }
}

# set intermediate directory

if($intDir){
    applyToAllConfs $projectXml.Project.PropertyGroup.IntDir { param($intDirNode) $intDirNode.InnerText = $intDir }
}

#########################################################

# set custom build events

applyToAllConfs $projectXml.Project.ItemDefinitionGroup { param($itemDefGroup) 
    if($pre_link_command){
        $itemDefGroup.PreLinkEvent.Command = $pre_link_command
    }
    if($post_build_command){
        $itemDefGroup.PostBuildEvent.Command = $post_build_command
    }
}

#########################################################

# set custom build tool

applyToAllConfs $projectXml.Project.ItemGroup.CustomBuild.Command { param($command)
    if($customBuildToolCommand){
        $command.'#text' = $customBuildToolCommand
    }
}

#########################################################

#                   close project xml                   #

#########################################################

$projectXml.Save($projectXmlPath)

log $tags.saved "Project configuration $($projectXmlPath) saved."

#########################################################

end