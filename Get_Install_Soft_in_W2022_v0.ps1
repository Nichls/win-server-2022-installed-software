# Важно: Этот файл должен быть сохранен в кодировке UTF-16 BE (Big Endian) с BOM
# В Windows PowerShell это обеспечивает корректное отображение кириллицы
# При сохранении в других кодировках (UTF-8, UTF-16 LE, CP1251) могут возникнуть проблемы с отображением
# Рекомендуется использовать Notepad++ для конвертации в UTF-16 BE с BOM
# Задаем пути в реестре, где Windows хранит сведения об установленных приложениях:
# 1) Для 64-битных программ
# 2) Для 32-битных программ, установленных на 64-битной системе
$paths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

# Получаем значения ключей из указанных путей.
# Используем фильтр, чтобы исключить записи без DisplayName (то есть неотображаемые приложения).
# Далее выбираем только нужные поля: имя, версию, издателя и дату установки.
$apps = Get-ItemProperty -Path $paths |
  Where-Object { $_.DisplayName } |
  Select-Object DisplayName, DisplayVersion, Publisher, InstallDate

# Экспортируем полученные данные в файл CSV.
# Файл сохраняется на рабочий стол текущего пользователя.
# Параметры:
# -NoTypeInformation — исключает служебную информацию о типе объекта
# -Encoding UTF8 — кодировка UTF-8 для совместимости
$apps | Export-Csv "$env:USERPROFILE\Desktop\installed_apps.csv" -NoTypeInformation -Encoding UTF8
