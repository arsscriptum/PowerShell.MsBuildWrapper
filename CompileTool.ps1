<#
#̷𝓍   𝓐𝓡𝓢 𝓢𝓒𝓡𝓘𝓟𝓣𝓤𝓜 
#̷𝓍   
#̷𝓍   Write-LogEntry
#̷𝓍   
#>


[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [Alias('p')]
    [string]$Project,
    [Parameter(Mandatory = $false)]
    [ValidateSet('Debug','Release','All')]
    [Alias('c')]
    [string]$Configuration="Release",
    [ValidateSet('x86','x64')]
    [string]$Platform="x64",
    [Parameter(Mandatory=$false)]
    [Alias('r')]
    [switch]$Rebuild,
    [Parameter(Mandatory=$false)]
    [switch]$Clean,
    [Parameter(Mandatory=$false)]
    [Alias('q')]
    [switch]$Quiet,
    [Parameter(Mandatory=$false)]
    [Alias('h')]
    [switch]$Help,
    [Parameter(Mandatory = $false)]
    [string]$WarningsVariable,
    [Parameter(Mandatory = $false)]
    [string]$ErrorsVariable,
    [Parameter(Mandatory = $false)]
    [string]$OutputVariable
)

[System.Diagnostics.Stopwatch]$Script:progressSw = [System.Diagnostics.Stopwatch]::new()

$CurrentPath = (Get-Location).Path
$CmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = '$pid'" | select CommandLine ).CommandLine   
[string[]]$UserCommandArray = $CmdLine.Split(' ')
$ProgramFullPath = $UserCommandArray[0].Replace('"','')
$ProgramDirectory = (gi $ProgramFullPath).DirectoryName
$ProgramName = (gi $ProgramFullPath).Name
$ProgramBasename = (gi $ProgramFullPath).BaseName

$Global:LogFilePath = Join-Path ((Get-Location).Path) 'downloadtool.log'
Remove-Item $Global:LogFilePath -Force -ErrorAction Ignore | Out-Null
New-Item $Global:LogFilePath -Force -ItemType file -ErrorAction Ignore | Out-Null

if(($ProgramName -eq 'pwsh.exe') -Or ($ProgramName -eq 'powershell.exe')){
    $MODE_NATIVE = $False
    $MODE_SCRIPT = $True
    $ProgramName = $MyInvocation.MyCommand.Name
}else{
    $MODE_NATIVE = $True
    $MODE_SCRIPT = $False
}


function Get-PossibleDirectoryName([string]$Path) {
    if([string]::IsNullOrEmpty($Path)){
        Show-MyPopup "ERROR" "PossibleDirectoryName Path error" 'Error' 
        return ""
    }
        if(Test-Path -Path $Path -PathType Container){
            $directory = $Path.Replace('/','\').Trim('\').Trim()
            return $directory
        }
        $resolvedPath = Resolve-Path -Path $Path -ErrorVariable resolvePathError -ErrorAction SilentlyContinue

        if ($null -eq $resolvedPath)
        {
            $fullpath = $resolvePathError[0].TargetObject
            [uri]$u = $fullpath
            $segcount = $u.Segments.Count
            $directory = ''
            for($x = 1 ; $x -lt $segcount-1 ; $x++){
                $directory += $u.Segments[$x].Replace('/','\')
                $directory = $directory.Trim()
            }
        
            return $directory
        }
        else
        {
            $fullpath = $resolvedPath.ProviderPath
            $directory = (Get-Item -Path $fullpath).DirectoryName
            $directory = $directory.Trim()
            return $directory
        }
    
}


function Resolve-MsBuildExe{

    [CmdletBinding(SupportsShouldProcess)]
    param()

    $expectedLocations=@("${ENV:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin", "$ENV:ProgramFiles\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin")

    if(Test-Path "$ENV:VS140COMNTOOLS" -ErrorAction Ignore -PathType Container){
        $resolvedMsBuildPath = Resolve-Path "$ENV:VS140COMNTOOLS\..\..\MSBuild\Current\Bin" -ErrorAction Ignore | select -ExpandProperty Path
        Write-Verbose "ENV:VS140COMNTOOLS valid. Resolving $resolvedMsBuildPath"
    }
    $expectedLocations+=$resolvedMsBuildPath
    $ffFiles=$expectedLocations|%{Join-Path $_ 'msbuild.exe'}
    [String[]]$validFiles=@($ffFiles|?{test-path $_})
    $validFilesCount = $validFiles.Count
    if($validFilesCount){
        return $validFiles[0]
    }
    else{
        return $Null
    }
}


function UpdateConsoleCursor{
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Message to be printed
        [Parameter(Mandatory = $True, Position = 0)] 
        [string] $Message,

        # Cursor position where message is to be printed
        [int] $Leftpos = -1,
        [int] $Toppos = -1,

        # Foreground and Background colors for the message
        [System.ConsoleColor] $ForegroundColor = [System.Console]::ForegroundColor,
        [System.ConsoleColor] $BackgroundColor = [System.Console]::BackgroundColor,
        
        # Clear whatever is typed on this line currently
        [switch] $ClearLine,

        # After printing the message, return the cursor back to its initial position.
        [switch] $StayOnSameLine
    ) 

       # Save the current positions. If StayOnSameLine switch is supplied, we should go back to these.
    $CurrCursorLeft = [System.Console]::get_CursorLeft()
    $CurrCursorTop = [System.Console]::get_CursorTop()
    $CurrForegroundColor = [System.Console]::ForegroundColor
    $CurrBackgroundColor = [System.Console]::BackgroundColor

    
    # Get the passed values of foreground and backgroun colors, and left and top cursor positions
    $NewForegroundColor = $ForegroundColor
    $NewBackgroundColor = $BackgroundColor

    if ($Leftpos -ge 0) {
        $NewCursorLeft = $Leftpos
    } else {
        $NewCursorLeft = $CurrCursorLeft
    }

    if ($Toppos -ge 0) {
        $NewCursorTop = $Toppos
    } else {
        $NewCursorTop = $CurrCursorTop
    }

    # if clearline switch is present, clear the current line on the console by writing " "
    if ( $ClearLine ) {                        
        $clearmsg = " " * ([System.Console]::WindowWidth - 1)  
        [System.Console]::SetCursorPosition(0, $NewCursorTop)
        [System.Console]::Write($clearmsg)            
    }

    # Update the console with the message.
    [System.Console]::ForegroundColor = $NewForegroundColor
    [System.Console]::BackgroundColor = $NewBackgroundColor    
    [System.Console]::SetCursorPosition($NewCursorLeft, $NewCursorTop)
    if ( $StayOnSameLine ) { 
        # Dont print newline at the end, set cursor back to original position
        [System.Console]::Write($Message)
        [System.Console]::SetCursorPosition($CurrCursorLeft, $CurrCursorTop)
    } else {
        [System.Console]::WriteLine($Message)
    }    

    # Set foreground and backgroun colors back to original values.
    [System.Console]::ForegroundColor = $CurrForegroundColor
    [System.Console]::BackgroundColor = $CurrBackgroundColor

}


[string]$Script:FullChar = "O"
[string]$Script:EmptyChar = "-"
[int]$Script:CallCount = 0
function StartAsciiProgressBar{
    $Script:progressSw.Start()
}

function StopAsciiProgressBar{
   
    $Script:progressSw.Stop()
}



function NewAsciiProgressBar{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)][int]$NumWarning=0,
        [Parameter(Mandatory = $false)][int]$NumErrors=0,
        [Parameter(Mandatory = $false)][int]$UpdateDelay=100,
        [Parameter(Mandatory = $false)][int]$ProgressDelay=10
    )
 
    $ms = $Script:progressSw.Elapsed.TotalMilliseconds
    if($ms -lt $UpdateDelay){
        return
    }
    
    $Script:progressSw.Restart()
    $Script:Index++
    $Half = $Max/ 2
    if($Index -ge $Max){ 
        $Script:Pos=0
        $Script:Index=0
    }elseif($Index -ge $Half){ 
        $Script:Pos = $Max-$Index
    }else{
        $Script:Pos++
    }

    $str = ''
    For($a = 0 ; $a -lt $Script:Pos ; $a++){
        $str += "$Script:EmptyChar"
    }
    $str += "$Script:FullChar"
    For($a = $Half ; $a -gt $Script:Pos ; $a--){
        $str += "$Script:EmptyChar"
    }
    $ElapsedTimeStr = ''
    $ts =  [timespan]::fromseconds($Script:ElapsedSeconds)
    if($ts.Ticks -gt 0){
        $ElapsedTimeStr = "{0:mm:ss}" -f ([datetime]$ts.Ticks)
    }
    $color = 'Gray'
    if($NumWarning -gt 0){ $color = 'Yellow' }
    if($NumErrors -gt 0){ $color = 'Red' }
    $ProgressMessage = "Progress: [{0}] {1} {2:d3} Errors {3:d3} Warnings" -f $str, $ElapsedTimeStr, $NumErrors , $NumWarning
    UpdateConsoleCursor "$ProgressMessage" -ForegroundColor $color  -ClearLine -StayOnSameLine
    Start-Sleep -Milliseconds $ProgressDelay
}


function Out-Banner {  # NOEXPORT
    Write-Host "`n$ProgramName - compilation tool" -f Blue
    Write-Host "Copyright 2020 - Guillaume Plante`n" -f Gray
}




Out-Banner

if($Help){
    Out-Usage
    return
}

$CurrentPath = (Get-Location).Path
$RootPath = (Resolve-Path "$CurrentPath\.." -ErrorAction Ignore).Path



#Remove-Item -Path $DeployPath -Force -Recurse -ErrorAction Ignore | Out-Null
#if(-not(Test-Path $DeployPath)){
     #Write-Host " MakeDir      $DeployPath"
    #New-Item -Path $DeployPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
#}

$ProjectPath = Join-Path $RootPath $Project


$Target = 'Build'
if($Rebuild){
    $Target = 'Rebuild'
}




$MsBuildScript = {
      param([string]$msbuild,[string]$project,[string]$target,[string]$cfg,[string]$platform)   
  
    try{
        # Start-MsBuild -a @($Project ,'-t:Rebuild' ,'-p:Configuration=Debug')
       &"$msbuild" "$project" "/t:$target" "/p:Configuration=$cfg" "/p:platform=$platform"
        
    }catch{
        Write-Error $_ 
    }finally{
        Write-verbose "Downloaded $Url"
}}.GetNewClosure()

[scriptblock]$MsBuildScriptBlock = [scriptblock]::create($MsBuildScript) 


    try{
        StartAsciiProgressBar
        $NumErrors = 0
        $NumWarnings = 0
        $Script:Max = 30
        $Script:Half = 15
        $Script:Index = 0
        $Script:stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $Script:EstimatedSeconds = 3
        [regex]$perror = [regex]::new('(?<Path>[^\x28]*)(?<Where>[0-9\(\)\,]*)(?<dots>\:\ )(?<w>[\\error]{0,})([\s]{1})(?<Code>[A-Z0-9]*)(\:)(?<Message>[^\x00]*)')
        [regex]$pwarn = [regex]::new('(?<Path>[^\x28]*)(?<Where>[0-9\(\)\,]*)(?<dots>\:\ )(?<w>[\\warning]{0,})([\s]{1})(?<Code>[A-Z0-9]*)(\:)(?<Message>[^\x00]*)')
        [collections.arraylist]$WarningsObjects =  [collections.arraylist]::new()
        [collections.arraylist]$ErrorsObjects =  [collections.arraylist]::new()
        $e = "$([char]27)"
        #hide the cursor
        Write-Host "$e[?25l"  -NoNewline  
        $e = "$([char]27)"

        $AllOutput = ''
        $JobName = "GetHandleInfo"
        $MsBuildExe=Resolve-MsBuildExe
        $Working = $True
        $jobby = Start-Job -Name $JobName -ScriptBlock $MsBuildScriptBlock -ArgumentList ($MsBuildExe,$Project,$Target,$Configuration,$Platform)
        while($Working){
            try{
                $Script:ElapsedSeconds = $Script:EstimatedSeconds-$stopwatch.Elapsed.TotalSeconds
                NewAsciiProgressBar -NumWarning $NumWarnings -NumErrors $NumErrors
                $JobState = (Get-Job -Name $JobName).State

                Write-verbose "JobState: $JobState"
                if($JobState -eq 'Completed'){
                    $Working = $False
                }

                $out = (Receive-Job -Name $JobName | out-string -stream) 
              
                $out | % { 
                    $AllOutput += "$_`n"
                }
                $NumErrors += ($out| Select-String -Pattern $perror).Length
                $NumWarnings += ($out| Select-String -Pattern $pwarn).Length
                $out | % { 
                    $w = $_ -match $pwarn;
                    if($w) { 
                        $path = $Matches.Path 
                        $code = $Matches.Code 
                        $line = $Matches.Where 
                        $msg = $Matches.Message 
                        $obj = [pscustomobject]@{
                                path = $path.Trim()
                                code = $code.Trim()
                                line = $line.Trim()
                                msg = $msg.Trim()
                        }
                        [void]$WarningsObjects.Add($obj)
                    }
                }

                $out | % { 
                    $w = $_ -match $perror;
                    if($w) { 
                        $path = $Matches.Path 
                        $code = $Matches.Code 
                        $line = $Matches.Where 
                        $msg = $Matches.Message 
                        $obj = [pscustomobject]@{
                                path = $path.Trim()
                                code = $code.Trim()
                                line = $line.Trim()
                                msg = $msg.Trim()
                        }
                        [void]$ErrorsObjects.Add($obj)
                    }
                }
                
            }catch{
                Write-Error $_
            }
        }
        #restore scrolling region
        Write-Host "$e[s$($e)[r$($e)[u" -NoNewline
        #show the cursor
        Write-Host "$e[?25h"   
    
        Get-Job $JobName | Remove-Job
        if($PSBoundParameters.ContainsKey('WarningsVariable')){
            Set-Variable -Name $WarningsVariable -Scope Global -Visibility Public -Option allscope -Value $WarningsObjects
        }
        if($PSBoundParameters.ContainsKey('ErrorsVariable')){
            Set-Variable -Name $ErrorsVariable -Scope Global -Visibility Public -Option allscope -Value $ErrorsObjects
        }
        if($PSBoundParameters.ContainsKey('OutputVariable')){
            Set-Variable -Name $OutputVariable -Scope Global -Visibility Public -Option allscope -Value $AllOutput
        }
        
     }catch{
        Write-Error $_ 
    }

