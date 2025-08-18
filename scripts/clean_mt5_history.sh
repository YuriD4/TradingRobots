#!/bin/bash

# MT5 Historical Data Cleanup Script
# Скрипт для очистки исторических данных MT5

MT5_BASES_PATH="C:\\Users\\pablonachos\\AppData\\Roaming\\MetaQuotes\\Terminal\\010E047102812FC0C18890992854220E\\bases"

# Получаем текущий размер данных
CURRENT_SIZE_GB=$(prlctl exec "Windows 11" powershell -Command "\$size = (Get-ChildItem '$MT5_BASES_PATH' -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if (\$size) { [math]::Round(\$size/1GB,2) } else { 0 }" 2>/dev/null | tr -d '\r')

if [ ! -z "$CURRENT_SIZE_GB" ] && [ "$CURRENT_SIZE_GB" != "" ] && [ "$CURRENT_SIZE_GB" != "0" ]; then
    echo "🧹 Очистка исторических данных MT5 (${CURRENT_SIZE_GB} ГБ)..."
else
    echo "❌ Не удалось получить размер данных или папка пуста"
    exit 1
fi

# Удаляем содержимое папки bases
prlctl exec "Windows 11" cmd /c "del /S /Q \"$MT5_BASES_PATH\\*.*\"" > /dev/null 2>&1
prlctl exec "Windows 11" cmd /c "for /d %i in (\"$MT5_BASES_PATH\\*\") do rmdir /S /Q \"%i\"" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Очищено ${CURRENT_SIZE_GB} ГБ исторических данных"
    echo "💡 Перезапустите MT5 для применения изменений"
else
    echo "❌ Ошибка при удалении данных"
    exit 1
fi