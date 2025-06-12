$paths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$apps = Get-ItemProperty -Path $paths |
Where-Object { $_.DisplayName } |
Select-Object DisplayName, DisplayVersion, Publisher, InstallDate

$apps | Export-Csv "$env:USERPROFILE\Desktop\installed_apps.csv" -NoTypeInformation -Encoding UTF8
