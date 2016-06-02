IF "%ComputeEmulatorRunning%" == "true" (
:: do not remove the echo string or else you will get an exception
ECHO  ComputeEmulatorRunning environment 
    
) ELSE (

ECHO  Azure environment
	
	CACLS ../../approot/temp /t /e /p "Network Service":c
	CACLS ../../approot/layouts /t /e /p "Network Service":c
	CACLS ../../approot/App_Config/ConnectionStrings.config /t /e /p "Network Service":c
	CACLS ../../approot/App_Config/Include/publishTargets.config /t /e /p "Network Service":c
   %windir%\system32\inetsrv\appcmd set config -section:applicationPools -applicationPoolDefaults.processModel.idleTimeout:00:00:00
)

EXIT /b 0