#!/bin/bash

# MT5 Compact Synchronization Script
# Компактная версия скрипта синхронизации с отображением размера исторических данных

# Определяем пути
REPO_PATH="/Users/pablonachos/Documents/Git Projects/TradingRobots"
MT5_SYNC_PATH="/Users/pablonachos/MT5Sync/Experts"
MT5_WINDOWS_PATH="C:\\Users\\pablonachos\\AppData\\Roaming\\MetaQuotes\\Terminal\\010E047102812FC0C18890992854220E\\MQL5\\Experts"
MT5_BASES_PATH="C:\\Users\\pablonachos\\AppData\\Roaming\\MetaQuotes\\Terminal\\010E047102812FC0C18890992854220E\\bases"

# Проверяем папки
if [ ! -d "$REPO_PATH" ] || [ ! -d "$MT5_SYNC_PATH" ]; then
    echo "❌ Ошибка: Необходимые папки не найдены"
    exit 1
fi

# Получаем размер исторических данных
BASES_SIZE_GB=$(prlctl exec "Windows 11" powershell -Command "\$size = (Get-ChildItem '$MT5_BASES_PATH' -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if (\$size) { [math]::Round(\$size/1GB,2) } else { 0 }" 2>/dev/null | tr -d '\r')

if [ ! -z "$BASES_SIZE_GB" ] && [ "$BASES_SIZE_GB" != "" ] && [ "$BASES_SIZE_GB" != "0" ]; then
    echo "📊 Исторические данные: ${BASES_SIZE_GB} ГБ"
else
    echo "📊 Исторические данные: н/д"
fi

# Синхронизация
echo -n "🔄 Синхронизация... "

# Шаг 1: rsync в общую папку
rsync -av --delete --exclude='.git' --exclude='.kilocode' --exclude='docs' --exclude='scripts' --exclude='README.md' "$REPO_PATH/" "$MT5_SYNC_PATH/" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Ошибка rsync"
    exit 1
fi

# Шаг 2: копирование в MT5
prlctl exec "Windows 11" cmd /c "xcopy \"\\\\psf\\MT5Sync\\Experts\\*\" \"$MT5_WINDOWS_PATH\\\" /E /Y /I" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    # Подсчитываем роботов
    ROBOT_COUNT=$(ls -la "$MT5_SYNC_PATH" | grep "^d" | grep -v "^\s*d.*\s\.$" | grep -v "^\s*d.*\s\.\.$" | wc -l | tr -d ' ')
    echo "✅ Готово! Синхронизировано роботов: $ROBOT_COUNT"
else
    echo "❌ Ошибка копирования в MT5"
    exit 1
fi

echo "💡 Перезапустите MetaEditor для отображения изменений"