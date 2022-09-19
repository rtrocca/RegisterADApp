#Requires -Version 7.0
# Need to call Connect-AzAccount before running this script
# Code inspired by the article at:
# https://reginbald.medium.com/creating-app-registration-with-arm-bicep-b1d48a287abb

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage='Path of the JSON file with the App definition template')]
    [string]$Path,
    
    [Parameter(Mandatory = $false, HelpMessage='Name of the app. It will be substituted in the JSON template')]
    [string]$AppName = "",

    [Parameter(Mandatory = $false, HelpMessage='Create a secret for the application')]
    [switch]$CreateSecret = $false,

    [Parameter(Mandatory = $false, HelpMessage='Trigger the admin consent flow to grant permissions to the app')]
    [switch]$AdminConsentFlow = $false,

    [Parameter(Mandatory = $false, HelpMessage='Redirect URL on localhost for the App Consent Flow')]
    [string]$ApprovePath = '/myapp/permissions',
    
    [Parameter(Mandatory = $false, HelpMessage='Port on localhost for the App Consent Flow')]
    [string]$ApprovePort = '5000',
    
    [Parameter(Mandatory = $false, HelpMessage='State for the App Consent Flow')]
    [string]$ApproveState = '1234',

    [Parameter(Mandatory = $false, HelpMessage='Scope for the App Consent Flow')]
    [string]$ApproveScope = 'https://graph.microsoft.com/.default'
    
    
)

function Send-HtmlContent($context, $content) {
    [string]$html = "
    <!DOCTYPE html>
    <html>
        <body>
        $content
        </body>
    </html>
    "
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($html) # convert htmtl to bytes
    $context.Response.ContentLength64 = $buffer.Length
    $context.Response.OutputStream.Write($buffer, 0, $buffer.Length) #stream to broswer
    $context.Response.OutputStream.Close()
}

function Start-ApproveServer($port, $tenantId, $clientId, $scope, $redirectPath, $state) {
    # Http Server
    $http = [System.Net.HttpListener]::new() 

    # Hostname and port to listen on
    $http.Prefixes.Add("http://localhost:$port/")

    # Start the Http Server 
    $http.Start()


    # Log ready message to terminal 
    if ($http.IsListening) {
        write-host 'HTTP Server Ready!  ' -f 'black' -b 'gre'
        write-host "now try going to $($http.Prefixes)" -f 'y'
    }

    $exit = $false
    # INFINTE LOOP
    # Used to listen for requests
    while ($http.IsListening -and !$exit) {
        # Get Request Url
        # When a request is made in a web browser the GetContext() method will return a request object
        # Our route examples below will use the request object properties to decide how to respond
        $context = $http.GetContext()

        $request = $context.Request
        if ($request.HttpMethod -eq 'GET') {
            $url = $request.Url;
            $path = $url.LocalPath;
            Write-Host "path $path"
            Write-Host $url
            $search = $context.Request.QueryString;
            Write-Host "Raw URL $url"
            switch ($path) {
                '/' { 
                    $redirectUrl = "http://localhost:$port$redirectPath"
                    $approveEndpoint = "https://login.microsoftonline.com/$tenantId/v2.0/adminconsent?client_id=$clientId&state=$state&redirect_uri=$redirectUrl&scope=$scope"
                    Send-HtmlContent $context "
                        <div>
                        Please click <a href=$approveEndpoint>here</a> to start the approval process.
                        </div>
                    "
    
                }
                $redirectPath {
                    $err = $search['error']
                    if (![string]::IsNullOrWhiteSpace($err)) {
                        $errorDescription = $search['error_description']
                        Send-HtmlContent $context "<h1>There was an error $err</h1>
                            <p>$errorDescription</p>
                        "
                    } else {
                        $readState = $search['state']
                        #$adminConsent = $search['admin_consent']
                        if ($readState -eq $state) {
                            Send-HtmlContent $context '<h1>Success!</h1>'
                                
                        } else {
                            Send-HtmlContent $context "<h1>Somebody tampered with state</h1>
                            <p>Received $readState instead of $state"

                        }
                        $exit = $true
                    }
                }
                '/exit' {
                    $exit = $true
                    [string]$html = '<h1>Bye</h1>'
    
                    Send-HtmlContent $context $html
                    }
                Default {}
            }
        } 
    
    }
}

    
$template = Get-Content -Path $Path | ConvertFrom-Json
Write-Host 'Template read'
Write-Host "AppName $AppName"

if (![string]::IsNullOrEmpty($AppName)) {
    $template.displayName = $AppName
}

$token = (Get-AzAccessToken -ResourceUrl https://graph.microsoft.com)
$tenantId = $token.tenantId
$tok = $token.token
$headers = @{'Content-Type' = 'application/json'; 'Authorization' = 'Bearer ' + $tok}

Write-Host ($template | ConvertTo-Json -Depth 10)
try {
    $app = (Invoke-RestMethod -Method POST -Headers $headers -Uri 'https://graph.microsoft.com/v1.0/applications' -Body ($template | ConvertTo-Json -Depth 10) )
}
catch{
    Write-Host "Error $Error"
    return $null
}

#$principal = Invoke-RestMethod -Method POST -Headers $headers -Uri  'https://graph.microsoft.com/v1.0/servicePrincipals' -Body (@{ "appId" = $app.appId } | ConvertTo-Json)

Write-Host "Tenant ID $tenantId"
Write-Host "App Created with App-ID $($app.appId)"

if ($CreateSecret -eq $true) {
    Write-Host 'Creating Secret'
    $body = @{
        "passwordCredential" = @{
            "displayName"= "Client Secret"
        }
    }
    $secret = (Invoke-RestMethod -Method POST -Headers $headers -Uri  "https://graph.microsoft.com/beta/applications/$($app.id)/addPassword" -Body ($body | ConvertTo-Json))

    Write-Host "Secret Key $($secret.keyId)"
    Write-Host "Client Secret $($secret.secretText)"

} 

if ($AdminConsentFlow -eq $true) {
    Write-Host 'Waiting one minute so that the app is properly registered. Note: this might not be enough in some cases.'
    Start-Sleep -Seconds 60
    Start-ApproveServer $ApprovePort $tenantId $app.appId $ApproveScope $ApprovePath $ApproveState
}
