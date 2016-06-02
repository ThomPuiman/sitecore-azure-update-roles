# Deploying Sitecore to Azure Cloud Service

This script can deploy you Sitecore solution to web roles on Azure. Different from the Sitecore Azure module, this script doesn't add the complete Sitecore installation to the cspkg but adds it during startup. This way your package is much smaller and easier to scale.

Note: If you're going to use this, make sure you know what you're doing. I've got it running in production for a few sites, but if you don't know what's happening you're going to have a bad time.

## Instructions

Copy the contents of the Bootstrapper folder to your Visual Studio project. This needs to be deployed along with your project.

**_AZURE** - Contains the Bootstrapper.exe. I've slightly modified the original code, which can be viewed here: https://bootstrap.codeplex.com
You might want to recompile the code in order to make it work with another Azure SDK version.
Azure Bootstrapper can download and unzip files from the Azure Blob storage. In order to separate the Sitecore installation from the package, i've zipped all Sitecore files and uploaded this to the storage. With the startup scripts BootstrapperCD.cmd and BootstrapperCE.cmd (found in the bin-folder and referenced from in the ServiceDefinition) it downloads the zip and unpacks it in the approot-folder on the web role during startup. It detects whether the files are already existing or not, so it won't overwrite anything if you're just upgrading an existing deployment.
I've also slightly modified the Sitecore installation to copy the Data-folder as App_Data folder within the Website-folder in order to make it work on a web role. Also the zip containing the Sitecore installation for the Content Delivery environment have the folders /sitecore/admin /sitecore/shell and file /sitecore/default.aspx excluded.

**SitecoreAzureConfig** - Replace Azure.publishsettings with your own publishsettings-file, which you can download here: https://windows.azure.com/download/publishprofile.aspx
The ServiceDefinitions are already pre-configured for this to work, you can add your own configurations, certificates and schema version (with the correct SDK version you're using). 
The ServiceConfigurations need to be updated with the correct Azure SQL Server name and Storage connection string.

## Parameters

**$csNameCD** - The name of the cloud service for the Content Delivery (which already needs to be created before executing this script)

**$csNameCE** - The name of the cloud service for the Content Management

**$configDir** - The full path of the folder containing the ServiceDefinitions and ServiceConfigurations

**$applicationDir** - The full path of the folder containing your published Visual Studio solution

**$subscription** - The name of your Azure subscription (which needs to be in the Azure.publishsettings file)

**$storageAccount** - The name of the Azure Blob Storage account (hardcoded name of the container is 'sitecore', you can also change it in the script to point it at a different container)

**$storageKey** - The access key of the given storage account

**$slot (optional)** - Either "Production" or "Staging"

**$deploymentLabel (optional)** - Display name of your deployment in the Azure portal