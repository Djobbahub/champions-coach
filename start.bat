@echo off
cd /d "%~dp0"
title Champions Coach
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
