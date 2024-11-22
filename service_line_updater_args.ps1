# Path to your CSV file
param (
    [string]$email,
    [string]$password,
    [string]$csvFile
)

# Import the CSV data
$data = Import-Csv -Path $csvFile

# Base URLs
$baseLoginUrl = "https://app.servicetrade.com/api/auth"
$baseLogoutUrl = "https://app.servicetrade.com/api/auth"
$baseEditUrl = "https://app.servicetrade.com/user/edit/id/"
$baseSaveUrl = "https://app.servicetrade.com/user/save"

# Login and set the $sessId
Write-Host "Logging in..."
$response = Invoke-RestMethod -Uri $baseLoginUrl -Method POST -Body (@{
        username = $email
        password = $password
    } | ConvertTo-Json) -ContentType "application/json" -SessionVariable session

# Extract PHPSESSID cookie
$sessId = ($session.Cookies.GetCookies($baseLoginUrl) | Where-Object { $_.Name -eq "PHPSESSID" }).Value
if (-not $sessId) {
    Write-Host "Failed to log in. Check credentials."
    exit 1
}
$sessId = "PHPSESSID=$sessId"
Write-Host "Logged in with session ID: $sessId"


# Loop through each record in the CSV
foreach ($record in $data) {
    # Extract values from the CSV for dynamic fields
    $id = $record.id
    $firstName = $record.first_name
    $lastName = $record.last_name
    $email = $record.email
    $locationId = $record.office

    # Convert boolean-like CSV values to 0 or 1
    $isSales = ($record.is_sales -eq 'true') ? 1 : 0
    $isTech = ($record.is_tech -eq 'true') ? 1 : 0
    $isHelper = ($record.is_helper -eq 'true') ? 1 : 0

    # Hardcoded service_lines_provided
    $serviceLines = @(
        9, 10, 405, 28, 221, 25, 23, 26, 321, 86, 18, 19, 182, 1, 301, 6, 108, 109, 
        173, 2, 190, 14, 16, 13, 15, 4, 112, 310, 110, 107, 553, 251, 3, 561, 113, 
        20, 5, 83
    )
    $serviceLinesQuery = ($serviceLines | ForEach-Object {
            [System.Web.HttpUtility]::UrlEncode("service_lines_provided[]") + "=" + $_
        }) -join "&"

    # Fetch the xvalidate-form-key
    $editUrl = "$baseEditUrl$id"
    $response = curl `
        $editUrl `
        -H "accept: text/html" `
        -H "cookie: $sessId" `
        -H "referer: https://app.servicetrade.com/user/view/id/$id" `
    | Out-String

    # Extract xvalidate-form-key using regex
    $keyPattern = 'window\.xvalidate_form_key\s*=\s*"(.*?)"'
    $xvalidateFormKey = if ($response -match $keyPattern) { $matches[1] } else { $null }

    if ($xvalidateFormKey) {
        Write-Host "Fetched xvalidate-form-key: $xvalidateFormKey"

        # Manually construct the query string to match the layout
        $queryString = @"
id=$id&
first_name=$firstName&
last_name=$lastName&
email=$([System.Web.HttpUtility]::UrlEncode($email))&
phone=&
timezone=America%2FChicago&
company_id=2695031&
company_id_search=Vendor%20-%20Marmic%20Fire%20and%20Safety&
location_id=$locationId&
warehouse_id=&
manager_id=&
details=&
default_en_route_item_id=&
default_job_prep_item_id=&
default_on_site_item_id=&
is_sales=$isSales&
is_tech=$isTech&
is_helper=$isHelper&
$serviceLinesQuery&
Save=Save&
xvalidate-form-key=$xvalidateFormKey
"@

        $queryString = $queryString.Replace("`n", "").Replace("`r", "")


        # Log data to the console for verification
        Write-Host "Prepared Request for ID: $id"
        Write-Host "Constructed Query String:"
        Write-Host $queryString
        Write-Host "----------------------------------------"

        # Wait for confirmation before sending the curl command
        #Read-Host "Press Enter to send the request, or Ctrl+C to abort"

        # Send the POST request with dynamic data
        curl `
            $baseSaveUrl `
            -H "content-type: application/x-www-form-urlencoded" `
            -H "cookie: $sessId" `
            --data-raw $queryString `
            > "ps_combined_out_$id.txt"

        Write-Host "Request sent for ID: $id"
    }
    else {
        Write-Host "Failed to fetch xvalidate-form-key for ID: $id. Check response content."
    }
}


# Logout
Write-Host "Logging out..."
$response = Invoke-RestMethod -Uri $baseLogoutUrl -Method DELETE -Headers @{ "Cookie" = $sessId }
Write-Host "Logged out. Session ended."
