# Важно: Этот файл должен быть сохранен в кодировке UTF-16 BE (Big Endian) с BOM
# В Windows PowerShell это обеспечивает корректное отображение кириллицы
# При сохранении в других кодировках (UTF-8, UTF-16 LE, CP1251) могут возникнуть проблемы с отображением
# Рекомендуется использовать Notepad++ для конвертации в UTF-16 BE с BOM

<#
.SYNOPSIS
    Скрипт для получения списка установленного программного обеспечения на Windows Server 2022.

.DESCRIPTION
    Скрипт собирает информацию об установленных приложениях из реестра Windows,
    включая название, версию, издателя и дату установки. Результаты сохраняются в CSV-файл.

.AUTHOR
    Александр Николаев
    E-mail: nick@lmhosts.ru

.PARAMETER OutputPath
    Путь для сохранения CSV-файла с результатами.
    По умолчанию: "$env:USERPROFILE\Desktop\installed_apps.csv"

.PARAMETER MinFreeSpaceMB
    Минимальное требуемое свободное место на диске в МБ.
    По умолчанию: 100

.EXAMPLE
    .\Get_Install_Soft_in_W2022_v1.ps1
    Запуск скрипта с параметрами по умолчанию.

.EXAMPLE
    .\Get_Install_Soft_in_W2022_v1.ps1 -OutputPath "C:\Reports\apps.csv" -MinFreeSpaceMB 200
    Запуск скрипта с указанием пути сохранения и требуемого свободного места.

.NOTES
    Требования:
    - Windows PowerShell 5.1 или выше
    - Доступ к реестру Windows
    - Достаточно свободного места на диске

    Кодировка файла:
    - Файл должен быть сохранен в кодировке UTF-16 BE (Big Endian) с BOM
    - Рекомендуется использовать Notepad++ для конвертации в UTF-16 BE с BOM
.LINK
    https://github.com/Nichls/win-server-2022-installed-software
#>

# Определение параметров скрипта
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "$env:USERPROFILE\Desktop\installed_apps.csv",  # Путь для сохранения результатов
    
    [Parameter(Mandatory=$false)]
    [int]$MinFreeSpaceMB = 100  # Минимальное требуемое свободное место в МБ
)

# Настройка кодировки для корректной работы с кириллицей
[Console]::OutputEncoding = [System.Text.Encoding]::Unicode  # Установка кодировки консоли
$OutputEncoding = [System.Text.Encoding]::Unicode  # Установка кодировки вывода

# Настройка логирования
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path)  # Получение имени скрипта без расширения
$logFile = Join-Path $PSScriptRoot "$scriptName.log"  # Формирование пути к лог-файлу

<#
.SYNOPSIS
    Функция для логирования сообщений в консоль и файл.

.DESCRIPTION
    Записывает сообщение с временной меткой и уровнем важности в консоль и лог-файл.

.PARAMETER Message
    Текст сообщения для логирования.

.PARAMETER Level
    Уровень важности сообщения (INFO, WARNING, ERROR).
    По умолчанию: "INFO"
#>
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"  # Формирование временной метки
    $logMessage = "[$timestamp] [$Level] $Message"  # Формирование строки лога
    
    # Вывод в консоль
    Write-Host $logMessage
    
    # Запись в файл с кодировкой Unicode
    $logMessage | Out-File -FilePath $logFile -Append -Encoding Unicode
}

<#
.SYNOPSIS
    Функция проверки свободного места на диске.

.DESCRIPTION
    Проверяет наличие достаточного свободного места на диске для сохранения файла.

.PARAMETER Path
    Путь к директории для проверки.

.PARAMETER RequiredSpaceMB
    Требуемое количество свободного места в МБ.

.RETURNS
    bool: True если места достаточно, False если нет.
#>
function Test-FreeSpace {
    param(
        [string]$Path,
        [int]$RequiredSpaceMB
    )
    
    try {
        $drive = (Get-Item $Path).PSDrive  # Получение информации о диске
        $freeSpaceMB = [math]::Round($drive.Free / 1MB, 2)  # Расчет свободного места в МБ
        
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

try {
    # Проверка и создание директории для выходного файла
    $outputDir = Split-Path -Path $OutputPath -Parent  # Получение пути к директории
    if (-not (Test-Path $outputDir)) {
        Write-Log "Создание директории: $outputDir"
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null  # Создание директории если её нет
    }

    # Проверка свободного места
    if (-not (Test-FreeSpace -Path $outputDir -RequiredSpaceMB $MinFreeSpaceMB)) {
        throw "Недостаточно места на диске для сохранения файла"
    }

    Write-Log "Получение путей реестра для поиска установленных приложений"
    $paths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',  # Путь для 64-битных приложений
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'  # Путь для 32-битных приложений
    )

    Write-Log "Получение информации об установленных приложениях"
    # Get-ItemProperty: Получает свойства элементов реестра
    # Where-Object: Фильтрует объекты по условию (только с DisplayName)
    # Select-Object: Выбирает нужные свойства из объектов
    $apps = Get-ItemProperty -Path $paths |
    Where-Object { $_.DisplayName } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate

    if ($null -eq $apps -or $apps.Count -eq 0) {
        Write-Log "Не найдено установленных приложений" -Level "WARNING"
        exit
    }

    Write-Log "Найдено приложений: $($apps.Count)"

    Write-Log "Экспорт данных в файл: $OutputPath"
    # Export-Csv: Экспортирует данные в CSV-файл
    $apps | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding Unicode

    Write-Log "Скрипт успешно завершен"
}
catch {
    Write-Log "Ошибка при выполнении скрипта: $_" -Level "ERROR"
    Write-Log $_.ScriptStackTrace -Level "ERROR"  # Логирование стека вызовов при ошибке
    throw
}
