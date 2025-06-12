# Важно: Этот файл должен быть сохранен в кодировке UTF-16 BE (Big Endian) с BOM
# В Windows PowerShell это обеспечивает корректное отображение кириллицы
# При сохранении в других кодировках (UTF-8, UTF-16 LE, CP1251) могут возникнуть проблемы с отображением
# Рекомендуется использовать Notepad++ для конвертации в UTF-16 BE с BOM

<#
.SYNOPSIS
    Скрипт для получения списка установленного программного обеспечения на удаленном Windows Server 2022.

.DESCRIPTION
    Скрипт подключается к удаленному серверу и собирает информацию об установленных приложениях из реестра Windows,
    включая название, версию, издателя и дату установки. Результаты сохраняются в CSV-файл.

.AUTHOR
    Александр Николаев
    E-mail: nick@lmhosts.ru

.PARAMETER ComputerName
    Имя или IP-адрес удаленного сервера.
    Обязательный параметр.

.PARAMETER Credential
    Учетные данные для подключения к серверу.
    Может быть в формате "username" или "DOMAIN\username".
    Обязательный параметр.

.PARAMETER OutputPath
    Путь для сохранения CSV-файла с результатами.
    По умолчанию: "$env:USERPROFILE\Desktop\installed_apps.csv"

.PARAMETER MinFreeSpaceMB
    Минимальное требуемое свободное место на диске в МБ.
    По умолчанию: 100

.EXAMPLE
    .\Get_Install_Soft_in_W2022_v2.ps1 -ComputerName "server01" -Credential "admin"
    Запуск скрипта с указанием имени сервера и локального пользователя.

.EXAMPLE
    .\Get_Install_Soft_in_W2022_v2.ps1 -ComputerName "192.168.1.100" -Credential "DOMAIN\admin" -OutputPath "C:\Reports\apps.csv"
    Запуск скрипта с указанием IP-адреса, доменного пользователя и пути сохранения.

.NOTES
    Требования:
    - Windows PowerShell 5.1 или выше
    - Доступ к удаленному серверу по WinRM
    - Достаточно свободного места на диске

.LINK
    https://github.com/Nichls/win-server-2022-installed-software
#>

# Определение параметров скрипта
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,  # Имя или IP-адрес сервера
    
    [Parameter(Mandatory=$true)]
    [System.Management.Automation.PSCredential]$Credential,  # Учетные данные
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "$env:USERPROFILE\Desktop\installed_apps.csv",  # Путь для сохранения результатов
    
    [Parameter(Mandatory=$false)]
    [int]$MinFreeSpaceMB = 100  # Минимальное требуемое свободное место в МБ
)

# Настройка кодировки для корректной работы с кириллицей
[Console]::OutputEncoding = [System.Text.Encoding]::Unicode
$OutputEncoding = [System.Text.Encoding]::Unicode

# Настройка логирования
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path)
$logFile = Join-Path $PSScriptRoot "$scriptName.log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Write-Host $logMessage
    $logMessage | Out-File -FilePath $logFile -Append -Encoding Unicode
}

function Test-FreeSpace {
    param(
        [string]$Path,
        [int]$RequiredSpaceMB
    )
    
    try {
        $drive = (Get-Item $Path).PSDrive
        $freeSpaceMB = [math]::Round($drive.Free / 1MB, 2)
        
        if ($freeSpaceMB -lt $RequiredSpaceMB) {
            Write-Log "Недостаточно места на диске. Требуется: ${RequiredSpaceMB}MB, Доступно: ${freeSpaceMB}MB" -Level "ERROR"
            return $false
        }
        return $true
    }
    catch {
        Write-Log "Ошибка при проверке свободного места: $_" -Level "ERROR"
        return $false
    }
}

# Начало работы скрипта
Write-Log "Начало выполнения скрипта"
Write-Log "Подключение к серверу: $ComputerName"

try {
    # Проверка доступности сервера
    if (-not (Test-WSMan -ComputerName $ComputerName -ErrorAction SilentlyContinue)) {
        throw "Не удалось подключиться к серверу $ComputerName. Проверьте доступность и настройки WinRM."
    }

    # Проверка и создание директории для выходного файла
    $outputDir = Split-Path -Path $OutputPath -Parent
    if (-not (Test-Path $outputDir)) {
        Write-Log "Создание директории: $outputDir"
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Проверка свободного места
    if (-not (Test-FreeSpace -Path $outputDir -RequiredSpaceMB $MinFreeSpaceMB)) {
        throw "Недостаточно места на диске для сохранения файла"
    }

    Write-Log "Получение информации об установленных приложениях с сервера $ComputerName"
    
    # Создание сессии для удаленного выполнения
    $session = New-PSSession -ComputerName $ComputerName -Credential $Credential

    # Пути реестра для поиска
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    # Получение информации об установленных приложениях через удаленную сессию
    $apps = Invoke-Command -Session $session -ScriptBlock {
        param($paths)
        Get-ItemProperty -Path $paths |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    } -ArgumentList $paths

    # Закрытие сессии
    Remove-PSSession $session

    if ($null -eq $apps -or $apps.Count -eq 0) {
        Write-Log "Не найдено установленных приложений на сервере $ComputerName" -Level "WARNING"
        exit
    }

    Write-Log "Найдено приложений: $($apps.Count)"

    Write-Log "Экспорт данных в файл: $OutputPath"
    $apps | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding Unicode

    Write-Log "Скрипт успешно завершен"
}
catch {
    Write-Log "Ошибка при выполнении скрипта: $_" -Level "ERROR"
    Write-Log $_.ScriptStackTrace -Level "ERROR"
    throw
} 