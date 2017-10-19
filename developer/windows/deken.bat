@set REF=%~dp0\windows\portable-python\App
@set PYTHONPATH=%REF%\Lib;%REF%\DLLs;%REF%\libs;%REF%\site-packages-alt
@%REF%\python.exe %~dp0\deken.py %*
