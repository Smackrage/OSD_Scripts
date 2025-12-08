$dhcpserver = 'DHCPSERVER01.contoso.corp'  
$optionids = 3,6,15,66,67  
$dhcpserver |  
    ForEach-Object{  
        $servername = $_  
        Get-DHCPServerv4Scope -ComputerName $servername |   
            ForEach-Object{  
                $scopeid = $_.ScopeId  
                Get-DHCPServerv4OptionValue -ComputerName $servername -ScopeID $scopeid -OptionId $optionids |  
                    ForEach-Object{  
                        [PSCustomObject]@{  
                            DHCPServer = $servername  
                            ScopeID = $scopeid  
                            OptionId = $_.OptionId  
                            Name =  $_.Name
                            Value = $_.Value -join ';'  
                        }  
                    }  
            }  
         } | Export-Csv c:\temp\scopids091225.csv -NoTypeInformation
