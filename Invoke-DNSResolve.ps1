function Get-SubnetAddresses {
    Param (
        [IPAddress]$IP,
        [ValidateRange(0, 32)][int]$MaskBits
    )

    $mask = ([Math]::Pow(2, $MaskBits) - 1) * [Math]::Pow(2, (32 - $MaskBits))
    $maskbytes = [BitConverter]::GetBytes([UInt32] $mask)
    $DottedMask = [IPAddress]((3..0 | ForEach-Object { [String] $maskbytes[$_] }) -join '.')

    $lower = [IPAddress] ( $ip.Address -band $DottedMask.Address )

    $LowerBytes = [BitConverter]::GetBytes([UInt32] $lower.Address)
    [IPAddress]$upper = (0..3 | % { $LowerBytes[$_] + ($maskbytes[(3 - $_)] -bxor 255) }) -join '.'

    $ips = @($lower, $upper)
    return $ips
}

function Get-IPRange {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Net.IPAddress]$Lower,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Net.IPAddress]$Upper
    )

    $IPList = [Collections.ArrayList]::new()
    $null = $IPList.Add($Lower)
    $i = $Lower
    while ( $i -ne $Upper ) { 
        $iBytes = [BitConverter]::GetBytes([UInt32] $i.Address)
        [Array]::Reverse($iBytes)
        $nextBytes = [BitConverter]::GetBytes([UInt32]([bitconverter]::ToUInt32($iBytes, 0) + 1))
        [Array]::Reverse($nextBytes)
        $i = [IPAddress]$nextBytes
        $null = $IPList.Add($i)
    }
    return $IPList
}

function Invoke-DNSResolve {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(

        [Parameter(Mandatory = $true)]
        [string]$IP,
		
		[Parameter (Mandatory = $False)]
		[String] $OutputFile
    )

    if ($IP.Contains("/")) {
        $mb = $IP.Split("/")[1]
        $IP = $IP.Split("/")[0]
        $ips = Get-SubnetAddresses -MaskBits $mb -IP $IP
        $ipAddresses = Get-IPRange -Lower $ips[0] -Upper $ips[1]
    } else {
        $ipAddresses = @($IP)
    }
	
	$runspacePool = [runspacefactory]::CreateRunspacePool(1, 10)
	$runspacePool.Open()

	$scriptBlock = {
		param ($computer)

		try {
			$ResolvedResult = (Resolve-DnsName $computer -QuickTimeout).NameHost
			return $ResolvedResult
		}
		catch {return $null}
	}

	$runspaces = New-Object 'System.Collections.Generic.List[System.Object]'

	foreach ($computer in $ipAddresses) {
		$powerShellInstance = [powershell]::Create().AddScript($scriptBlock).AddArgument($computer)
		$powerShellInstance.RunspacePool = $runspacePool
		$runspaces.Add([PSCustomObject]@{
			Instance = $powerShellInstance
			Status   = $powerShellInstance.BeginInvoke()
		})
	}

	$FinalResults = @()
	foreach ($runspace in $runspaces) {
		$result = $runspace.Instance.EndInvoke($runspace.Status)
		if ($result) {
			$FinalResults += $result
		}
	}

	$runspacePool.Close()
	$runspacePool.Dispose()
	
	if ($FinalResults) {
	
		$FinalResults

		if (-not $OutputFile) { $OutputFile = "$pwd\Resolved.txt" }

		$utf8NoBom = New-Object System.Text.UTF8Encoding $false
		[System.IO.File]::WriteAllLines($OutputFile, $FinalResults, $utf8NoBom)

		Write-Output ""
		if ($OutputFile) {
			Write-Output " Output saved to: $OutputFile"
		}
		else {
			Write-Output " Output saved to: $pwd\Resolved.txt"
		}
		Write-Output ""
	}
	else {
		Write-Output " No hosts could be resolved."
		Write-Output ""
	}
	
	$FinalResults = $null
}
