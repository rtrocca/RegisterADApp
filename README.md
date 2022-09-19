# Register-App.ps1
A PowerShell script that helps register and approve an AD Enterprise Application. The Script needs a JSON file that contains the app definition. One way to get such file is to retrieve the JSON definition of an existing app and edit it.

The scripts also allows to specify if an app secret shoudl be created and it can also start the admin consent flow for the all.

Parameters:
- **Path** path of the JSON file with the app definition
- **AppName** App name that will overwrite the one defined in the JSON file
- **CreateSecret** Create an app secret and *print it on the console* Note that this might be unsafe, close the console after this has been printed and you noted it down.
- **AdminConsentFlow** if specified the script will start the admin consent flow in a browser
- **ApprovePath** the path to which the approve flow will be redirected. This path must be present in the web section of the app definition file
- **ApprovePort** localhost port used for the HTTP server
- **ApproveState** a state that will be propagated. Used to check that the redirection comes from the right source.
- **ApproveScope** OAUTH scope for the consent flow

**ApprovePath** and **ApprovePort** must match an entry in the *web* section of the app definition file. For example if ApprovaPath is /myapp/permissions and ApprovePort 5000, then the path http://localhost:5000/myapp/permissions must be in the app definition file. See the sample TeamsAdminApp.json
```json
"web": {
        "redirectUris": ["http://localhost:5000/myapp/permissions"]
}
```

# TeamsAdminApp.json
This is an app definition that can be used for managing Microsoft Teams using Access Tokens. See the Connect-MicrosoftTeams documentation at [Example 4: Connect to MicrosoftTeams using Access Tokens](https://learn.microsoft.com/en-us/powershell/module/teams/connect-microsoftteams?view=teams-ps#example-4-connect-to-microsoftteams-using-access-tokens). 
In order to do that (without changing any parameters):
- Edit the TeamsAdminApp.json with your custom information, but do not change the scopes.
- Run ```Connect-AzAccount``` [Connect-AzAccount](https://learn.microsoft.com/en-us/powershell/module/az.accounts/Connect-AzAccount?view=azps-8.3.0) part of Az PowerShell
- Run ```Register-App -Path .\TeamsAdminApp.json -CreateSecret -AdminConsentFlow```
- Note down the AppId and ClientSecret
- Follow the instructions on screen to open a browser window and start the Admin Consent Flow for your newly registered app (it might take some time for the app to be registered, in that case the flow will fail saying that the app cannot be found. In that case you will have to manually give Admin approval to the AD app.
- Follow the instructions at [Example 4: Connect to MicrosoftTeams using Access Tokens](https://learn.microsoft.com/en-us/powershell/module/teams/connect-microsoftteams?view=teams-ps#example-4-connect-to-microsoftteams-using-access-tokens) to Connect to Microsoft Teams.
- **note** if the Admin Consent Flow would not pass, the PowerShell HTTP server will not exit by itself. In that case you need to access the "exit" endpoint from the browser, for example navigate to http://localhost:5000/exit

Example Output:
```
.\Register-App.ps1 -Path '.\TeamsAdminApp.json' -CreateSecret  -AdminConsentFlow
Template read
{
  "displayName": "Teams Module App",
  "signInAudience": "AzureADMyOrg",
  "requiredResourceAccess": [
  ...
 }
 
Tenant ID <your tenant id>
App Created with App-ID <newly created app ID>
Creating Secret
Client Secret <Client Secret>
Waiting one minute so that the app is properly registered. Note: this might not be enough in some cases.
HTTP Server Ready!  
now try going to http://localhost:5000/

# Microsoft code:
ClientSecret = "<Client Secret>"
$ClientSecret = [Net.WebUtility]::URLEncode($ClientSecret)
$TenantID = "<your tenant id>"
$Username = "<username>"
$Password = "<pwd>"
$Password = [Net.WebUtility]::URLEncode($Password)

$URI = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"
$Body = "client_id=$ClientID&client_secret=$ClientSecret&grant_type=password&username=$Username&password=$Password"
$RequestParameters = @{
   URI = $URI
   Method = "POST"
   ContentType = "application/x-www-form-urlencoded"
}
$GraphToken = (Invoke-RestMethod @RequestParameters -Body "$Body&scope=https://graph.microsoft.com/.default").access_token
$TeamsToken = (Invoke-RestMethod @RequestParameters -Body "$Body&scope=48ac35b8-9aa8-4d74-927d-1f4a14a0b239/.default").access_token
Connect-MicrosoftTeams -AccessTokens @($GraphToken, $TeamsToken)
```
