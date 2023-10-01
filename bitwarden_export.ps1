$ErrorActionPreference = "Stop"

try{
    # load JSON config file, containing values for 'bw_user' and 'bw_export_key_name'
    try{
        $config = Get-Content "$PSScriptRoot/bitwarden_export.config" | ConvertFrom-Json
    }catch{
        throw $_.Exception.Message +"`nCould not load configuration file."
    }

    # create file path with current time for export
    $time = Get-Date -UFormat '%F_%H%M'
    $output_path = "$PSScriptRoot/bitwarden_vault_$time.json"

    try{
        # Check if Bitwarden CLI is already logged in.
        Write-Host "Verifying Bitwarden login..."
        Write-Host (bw login --check)

    }catch [System.Management.Automation.CommandNotFoundException]{
        throw $_.Exception.Message +"`nPlease install Bitwarden CLI! https://bitwarden.com/help/cli/#download-and-install "
    }

    try {
        try{
            if($LASTEXITCODE){
                # prompt Bitwarden master password and store it in environment variable
                Write-Host "Please log in to Bitwarden CLI!"
                $bw_cred = Get-Credential -UserName $config.bw_user -Message "Enter your master password!"
                $env:BW_PASS = $bw_cred.GetNetworkCredential().Password

                # log in to Bitwarden, it will prompt TOTP code if needed.
                Write-Host (bw login --passwordenv BW_PASS $config.bw_user --quiet)
                if($LASTEXITCODE){
                    throw "Login failed."
                }
            }else{
                # Already logged in. Empty BW_PASS causes Bitwarden CLI to prompt password
                $env:BW_PASS = ""
            }

        }catch{
            throw $_.Exception.Message +"`nCannot log in to Bitwarden CLI."
        }

        # sync vault
        Write-Host "Syncing vault..."
        Write-Host (bw sync)

        try{
            # unlock vault. BW_SESSION will be used by 'bw get' and 'bw export'
            Write-Host "Unlocking vault..."
            if($env:BW_PASS){
                $env:BW_SESSION = (bw unlock --passwordenv BW_PASS --raw)
            }else{
                $env:BW_SESSION = (bw unlock --raw)
            }

            if(!$env:BW_SESSION){
                throw "Could not unlock vault."
            }

            # read export encryption key from item in vault. For recovery, make sure this key is kept safe outside the vault too!
            Write-Host "Retrieving encryption key from vault..."
            $export_key = (bw get password $config.bw_export_key_name --raw)

            if(!$export_key){
                throw "Could not retrieve encryption key."
            }
            # export the vault into encrypted JSON file
            Write-Host "Exporting vault..."
            Write-Host (bw export --format encrypted_json --password $export_key --output $output_path)
            if($LASTEXITCODE){
                throw "Vault export failed."
            }

            Write-Host "For recovery, make sure the encryption key is stored safely outside the vault too!"

        }finally{
            # lock vault
            Write-Host "Locking vault..."
            Write-Host (bw lock)
        }

    }finally{
        # clear sensitive variables    
        Remove-Item env:\BW_SESSION -ErrorAction SilentlyContinue
        Remove-Item env:\BW_PASS -ErrorAction SilentlyContinue
        Remove-Variable export_key -ErrorAction SilentlyContinue
        Remove-Variable bw_cred -ErrorAction SilentlyContinue
        Write-Host "Secrets cleared."
    }

    Write-Host "Vault exported successfully."

}catch{
    Write-Error $_.Exception.Message
}
