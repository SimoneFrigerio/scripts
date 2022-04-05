###########
#REFERENCE#
###########
# https://docs.microsoft.com/en-us/azure/defender-for-cloud/integration-defender-for-endpoint?tabs=linux
# https://docs.microsoft.com/en-us/powershell/module/az.compute/set-azvmextension?view=azps-7.3.2
#
# Require Powershell 7
# 
# Powered by Simone Frigerio - sifriger@microsoft.com
# Version 1.2 
# - added ARC VM
# - added optimization functions
#
# ARC MODULE
# Install-Module -Name Az.ConnectedMachine
#
###############################################################################
#                                                                             #
# USE AT YOUR OWN RESPONSABILITY AND RISK - this procedures are not supported #
#                                                                             #
###############################################################################

########################################################################
#### FUNCTIONS
########################################################################
function OnboardingMDELinux ($ResourceGroup, $VMName,$vmLocation, $subscriptionid, $LinuxBase64onboarding) {
    #Get VM extension - Jump Already Deployed MDE
    $VMExtension = Get-AzVMExtension -ResourceGroupName $ResourceGroup -VMName $VMName | Where-Object -Property Name -eq "MDE.Linux" | select VMNAme, Name, Location, Publisher, ProvisioningState
    $ProvisioningState = $VMExtension.ProvisioningState
    if ($ProvisioningState -eq "Succeeded") {
        Write-Host $VMName " - " $ResourceGroup " - Extension MDE.Linux already Deployed" 
    }else{
        #Onboarding Extension MDE.Linux
        $Settings = @{"azureResourceId"= $ResourceID; "defenderForServersWorkspaceId"=$subscriptionid; "forceReOnboarding"="true"; "provisionedBy"="Manual" };
        $LinuxProtectedSettings = @{"defenderForEndpointOnboardingScript"= $LinuxBase64onboarding};
        $OnboardingVM = Set-AzVMExtension -ResourceGroupName $ResourceGroup -VMName $VMName -Location $vmLocation -Name "MDE.Linux" -Publisher "Microsoft.Azure.AzureDefenderForServers" -ExtensionType "MDE.Linux" -TypeHandlerVersion "1.0" -Settings $Settings -ProtectedSettings $LinuxProtectedSettings;
        $IsSuccessStatusCode = $OnboardingVM.IsSuccessStatusCode
        $StatusCode = $OnboardingVM.StatusCode
        Write-Host $VMname " - SuccessStatusCode:" $IsSuccessStatusCode " - StatusCode:" $StatusCode
        #SETTING Exclusion
    }
}

function OnboardingMDEWindows ($ResourceGroup, $VMName,$vmLocation, $subscriptionid, $WinBase64EncodingPackage) {
    #Get VM extension - Jump Already Deployed MDE
    $VMExtension = Get-AzVMExtension -ResourceGroupName $ResourceGroup -VMName $VMName | Where-Object -Property Name -eq "MDE.Windows" | select VMNAme, Name, Location, Publisher, ProvisioningState 
    $ProvisioningState = $VMExtension.ProvisioningState
    if ($ProvisioningState -eq "Succeeded") {
        Write-Host $VMName " - " $ResourceGroup " - Extension MDE.WIndows already Deployed" 
    }else{
        #Windows ONLY 2019 2022 - W2012r2 - W2016
        $WinProtectedSettings = @{"defenderForEndpointOnboardingScript"= $WinBase64EncodingPackage};
        $OnboardingVM = Set-AzVMExtension -ResourceGroupName $ResourceGroup -VMName $VMName -Location $vmLocation -Name "MDE.Windows" -Publisher "Microsoft.Azure.AzureDefenderForServers" -ExtensionType "MDE.Windows" -TypeHandlerVersion "1.0" -Settings $Settings -ProtectedSettings $WinProtectedSettings;
        $IsSuccessStatusCode = $OnboardingVM.IsSuccessStatusCode
        $StatusCode = $OnboardingVM.StatusCode
        Write-Host $VMname " - SuccessStatusCode:" $IsSuccessStatusCode " - StatusCode:" $StatusCode
    }
}

########################################################################
##########################
# CONFIGURATION SECTION
##########################

$subscriptions = "xxxxxxxx-yyyy-aaaa-bbbb-cccccccccccc,xxxxxxxx-yyyy-aaaa-bbbb-cccccccccccc"
$RG_Excluded = "YOUR-RG"

# Convert Base64 Onboarding Script taken from Defender 365 Portal
# https://www.base64encode.org/
# Linux
# Windows 2022
$LinuxBase64onboarding ="BASE64ONBOARDING SCRIPT STRING" 
$WinBase64onboarding = "BASE64ONBOARDING SCRIPT STRING"

#ONBOARDING Azure-VM - 0 Exclude - 1 Onboard
$OnboardingAzVM = 0 

#ONBOARDING ARC-VM - 0 Exclude - 1 Onboard
$OnboardingARCVM = 0 

########################################################################
Connect-AzAccount

#$allResources = @()
#$subscriptions= Get-AzSubscription
$array_subscriptions = $subscriptions.split(",")
$RG_Excluded = $RG_Excluded.ToLower()
$array_RG_Excluded = $RG_Excluded.split(",")

ForEach ($vsub in $array_subscriptions){
    #$subscriptionid = $vsub.SubscriptionID
    $subscriptionid = $vsub
    Set-AzContext -SubscriptionId $subscriptionid
    
    #Azure VM
    if ($OnboardingAzVM -eq 1){
        #Azure List of Running VM
        $AzureVMs = Get-AzVM | `
        Select-Object Name, ResourceGroupName, @{Name="Status";
            Expression={(Get-AzVM -Name $_.Name -ResourceGroupName $_.ResourceGroupName -status).Statuses[1].displayStatus}} | `
            Where-Object {$_.Status -eq "VM running"}
            #Write-Host $AzureVMs
        ForEach ($Azurevm in $AzureVMs){
            #Get vm parameters
            $ResourceGroup= $Azurevm.ResourceGroupName.ToLower()
            $VMName = $Azurevm.Name
            $vm = Get-AzVM -ResourceGroupName $Azurevm.ResourceGroupName -Name $Azurevm.Name
            $OSType = $vm.StorageProfile.OsDisk.OsType        
            $ResourceID = $vm.id
            $vmLocation = $vm.Location
        
            #Check Resorcegroup Exclusion
            $CheckResourceGroup = $array_RG_Excluded.Contains("$ResourceGroup")
            if ($CheckResourceGroup -eq $true ){
                Write-Host "RG Escluded - " $ResourceGroup
            }else{
                if ($OSType -eq "Linux"){
                    OnboardingMDELinux $ResourceGroup, $VMName,$vmLocation, $subscriptionid, $LinuxBase64onboarding
                }
                if ($OSType -eq "Windows"){
                    OnboardingMDEWindows $ResourceGroup, $VMName,$vmLocation, $subscriptionid, $WinBase64EncodingPackage
                }
            }
        #Write-Host "Next VM"
        }
    }
    if ($OnboardingARCVM -eq 1){
        #Foreach Resource group in a subscription
        $Resourcegroups = Get-AzResourceGroup | Select ResourcegroupName
        ForEach ($Resourcegroup in $Resourcegroups){
            $CheckResourceGroup = $array_RG_Excluded.Contains("$ResourceGroup")
            if ($CheckResourceGroup -eq $true ){
                Write-Host "RG Escluded - " $ResourceGroup
            }else{
                $AzureARCVMs = Get-AzConnectedMachine -ResourceGroupName $Resourcegroup
                ForEach ($AzureARCvm in $AzureARCVMs){
                    #Get vm parameters
                    $VMName = $AzureARCvm.Name
                    $OSType = $AzureARCvm.OSNAme
                    $ResourceID = $vm.id
                    $vmLocation = $AzureARCvm.Location
                    if ($OSType -eq "Linux"){
                        OnboardingMDELinux $ResourceGroup, $VMName,$vmLocation, $subscriptionid, $LinuxBase64onboarding
                    }
                    if ($OSType -eq "Windows"){
                        OnboardingMDEWindows $ResourceGroup, $VMName,$vmLocation, $subscriptionid, $WinBase64EncodingPackage
                    }
                }
            }
        }
    }
}
