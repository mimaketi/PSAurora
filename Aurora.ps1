$GLOBAL:token = "fViBRRIxTFlJ70O9q9GNJddvMzsVLDX0"
$tokenFinder = "%" + "%"
$GLOBAL:authorized = $false
$Global:WebClient = new-object System.Net.WebClient

Function Discover-Auroras($Port){
    #Use unused port or it will fail
    $LocalEndPoint = New-Object System.Net.IPEndPoint([ipaddress]::Any,$Port)

    $MulticastEndPoint = New-Object System.Net.IPEndPoint([ipaddress]::Parse("239.255.255.250"),1900)

    $UDPSocket = New-Object System.Net.Sockets.Socket([System.Net.Sockets.AddressFamily]::InterNetwork,[System.Net.Sockets.SocketType]::Dgram,[System.Net.Sockets.ProtocolType]::Udp)

    $UDPSocket.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress,$true)

    $UDPSocket.Bind($LocalEndPoint)

    $UDPSocket.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP,[System.Net.Sockets.SocketOptionName]::AddMembership, (New-Object System.Net.Sockets.MulticastOption($MulticastEndPoint.Address, [ipaddress]::Any)))

    $UDPSocket.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP, [System.Net.Sockets.SocketOptionName]::MulticastTimeToLive, 2)

    $UDPSocket.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::IP, [System.Net.Sockets.SocketOptionName]::MulticastLoopback, $true)

    #Write-Host "UDP-Socket setup done...`r`n"
    #All SSDP Search
    $SearchString = "M-SEARCH * HTTP/1.1`r`nHOST:239.255.255.250:1900`r`nMAN:`"ssdp:discover`"`r`nST:ssdp:all`r`nMX:3`r`n`r`n"

    $UDPSocket.SendTo([System.Text.Encoding]::UTF8.GetBytes($SearchString), [System.Net.Sockets.SocketFlags]::None, $MulticastEndPoint) | Out-Null

    #Write-Host "M-Search sent...`r`n"

    [byte[]]$RecieveBuffer = New-Object byte[] 64000

    [int]$RecieveBytes = 0

    $Response_RAW = ""
    $Timer = [System.Diagnostics.Stopwatch]::StartNew()
    $Delay = $True
    while($Delay){
        #15 Second delay so it does not run forever
        if($Timer.Elapsed.TotalSeconds -ge 5){Remove-Variable Timer; $Delay = $false}
        if($UDPSocket.Available -gt 0){
            $RecieveBytes = $UDPSocket.Receive($RecieveBuffer, [System.Net.Sockets.SocketFlags]::None)

            if($RecieveBytes -gt 0){
                $Text = "$([System.Text.Encoding]::ASCII.GetString($RecieveBuffer, 0, $RecieveBytes))"
                $Response_RAW += $Text
            }
        }
    }
    return $Response_RAW -split "`n`r" | where {$_ -match "nanoleaf_aurora:light"}
}

function test-auroratarget{
    if ($global:target -eq $null){
        throw "You must first have connected to an aurora. Try re-running Discover-Auroras"
    }elseif (-not $GLOBAL:authorized) {
        return test-authorization
    }else{
        return $true;
    }
}
function invoke-aurora($path,$method = "get",$body = $null){
    if (-not (test-auroratarget)){return}
    try{
        $auroraResponse = invoke-webrequest -method $method -Uri($global:target + $path) -body $body
        return $auroraResponse | convertfrom-json 
    }catch{
        $responseCode = $_.exception.response.statuscode.value__
        $error = ""
        switch ($responseCode){
            400 {$error = "Bad Request, please submit a bug report"}
            401 {$error = "Unauthorized, please try running register-aurora"}
            403 {$error = "Forbidden, Please try running register-aurora"}
            404 {$error = "Not found, please submit a bug report"} 
            422 {$error = "Unprocessable Entity, Please submit a bug report"}
            500 {$error = "Internal Sever Error, please reset your aurora and try again"}
            default {$error = "$_.exception.response"}
        }
        throw $error
    }
}



function test-authorization{
    if ($token -eq $tokenFinder){
        Write-host "No token defined"
        register-aurora
    }else{
        try{
            #powershell throws errors on anything other than 200-399 status's.  If this succedes, we're probably fine, otherwise there is an issue.
            Invoke-WebRequest -Method GET $target/api/v1/$token | out-null
            $GLOBAL:authorized = $true;
            Write-Host "Authorized for this aurora"
            return $true
        }catch{
            if ((401,403,422) -contains $_.exception.response.statuscode.value__){
                Write-host "Aurora not authorized, running register-aurora"
                return register-aurora
            }else{
                write-error $_.exception
                return $false
            }
        }
    }

}

function register-aurora{
    read-host "Press and hold the power button on the aurora until the light begins to flash (5-7 sec). Then press enter"
    try{
    $global:token = (Invoke-WebRequest -Method post "$($global:target)/api/v1/new" -ErrorAction SilentlyContinue).content | convertfrom-json | select -exp auth_token
    }catch{
        return $false
    }
    (gc $PSCommandPath) -replace $tokenFinder,$token | Out-File -path $PSCommandPath -Force
    return $true
}

function get-aurorastate(){
    $command = "/api/v1/$($global:token)/state"
    return invoke-aurora -method "GET" -path $command
}

function get-aurorainfo(){
    $command = "/api/v1/$($global:token)/state"
    return invoke-aurora -path $command
}

function set-aurora(){
    [Parameter(Mandatory=$False, ParameterSetName = "power")]
    [Parameter(ParameterSetNAme = "brightness")]
    [Parameter(ParameterSetNAme = "hue")]
    [Parameter(ParameterSetName = "saturation")]
    [Parameter(ParameterSetName = "ColorTemp")]
    [Parameter(ParameterSetName = "ColorMode")]
    [switch]$on,

    [Parameter(Mandatory=$False, ParameterSetName = "power")]
    [switch]$off,

    [Parameter(Mandatory=$False, ParameterSetName = "brightness")]
    [Parameter(ParameterSetNAme = "power")]
    [int]$brightnessByValue,

    [Parameter(Mandatory=$False, ParameterSetName = "brightness")]
    [Parameter(ParameterSetNAme = "power")]
    [int]$brightnessByIncrement,

    [Parameter(Mandatory=$False, ParameterSetName = "hue")]
    [Parameter(ParameterSetNAme = "power")]
    [int]$hueByValue,

    [Parameter(Mandatory=$False, ParameterSetName = "hue")]
    [Parameter(ParameterSetNAme = "power")]
    [int]$hueByIncrement,

    [Parameter(Mandatory=$False, ParameterSetName = "saturation")]
    [Parameter(ParameterSetNAme = "power")]
    [int]$saturationByIncrement,

    [Parameter(Mandatory=$False, ParameterSetName = "saturation")]
    [Parameter(ParameterSetNAme = "power")]
    [int]$saturationByIncrement,

    [Parameter(Mandatory=$False, ParameterSetName = "ct")]
    [Parameter(ParameterSetNAme = "power")]
    [int]$ctByIncrement,

    [Parameter(Mandatory=$False, ParameterSetName = "ct")]
    [Parameter(ParameterSetNAme = "power")]
    [int]$ctByIncrement

    $PSCmdlet.ParameterSetName




      
}







#####End function Definitions#####
Write-host "Searching for devices..."
$auroras = Discover-Auroras($null)
Write-host "$($auroras.count) device$(({s },{ })[$auroras.count -eq 1])found"
#if multiple found, loop through and give choice, else, set the only one found as primary.
if ($auroras -ne $null){
    if ($auroras.count -gt 1){
        Write-host "Multiple devices found.`n"
        foreach ($aurora in $auroras){
            $name = $aurora -split "`n" | where {$_ -match "devicename"}
            write-host "$($auroras.IndexOf($aurora) + 1): $name"
        }
        $auroraIndex = Read-Host "Please enter device to target"
        $global:target = $auroras[$auroraIndex -1]
    }else{
        $global:target = $auroras
    }
    $global:target = (($global:target -split "`n" | where {$_ -match "location"}) -split "Location: http://")[1].trim()
}else{
    Write-host "No devices found.  This happens sometimes.  Please make sure your aurora and this device are connected to WIFI and powered on, and try again"
}
test-authorization | out-null
