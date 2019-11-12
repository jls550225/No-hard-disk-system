@echo off
title 建立快照檔
set VHDOS=
set /p VHDOS=請輸入iSCSI磁碟機代號:
if not exist %VHDOS%:\vhdos\win7x64.vhdx echo 找不到 %VHDOS%:\vhdos\win7x64.vhdx 主檔，無法執行。 & pause & goto theend
echo create vdisk file=%VHDOS%:\vhdos\win7x64_st.vhdx parent=%VHDOS%:\vhdos\win7x64.vhdx > %TEMP%\createparent.txt
echo create vdisk file=%VHDOS%:\vhdos\win7x64_rcst.vhdx parent=%VHDOS%:\vhdos\win7x64.vhdx >> %TEMP%\createparent.txt
diskpart /s %TEMP%\createparent.txt
:theend