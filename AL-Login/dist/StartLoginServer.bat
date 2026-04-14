@ECHO off
TITLE Aion German - Login Server Console
REM SET PATH="C:\Program Files\Java\jdk-11\bin"
REM SET PATH="Type here your path to java jdk/jre (including bin folder)."
REM NOTE: Remove tag REM from previous line.

:start
CLS
echo.

echo Starting Aion German Login Server.
echo.
REM -------------------------------------
REM Default parameters for a basic server.
java -Xms8m -Xmx32m -server --add-opens java.base/sun.misc=ALL-UNNAMED -cp ./libs/*;AL-Login.jar com.aionemu.loginserver.LoginServer
REM
REM -------------------------------------

SET CLASSPATH=%OLDCLASSPATH%


if ERRORLEVEL 1 goto error
goto end
:error
echo.
echo Login Server Terminated Abnormaly, Please Verify Your Files.
echo.
:end
echo.
echo Login Server Terminated.
echo.
pause
