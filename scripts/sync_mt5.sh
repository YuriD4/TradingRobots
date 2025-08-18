#!/bin/bash

# MT5 Synchronization Script
# Синхронизирует MQL5 роботов из Git репозитория с MT5 через Parallels Desktop
# 
# Использование: 
# 1. Перетащите этот файл в терминал
# 2. Или выполните: ./scripts/sync_mt5.sh
# 3. Или выполните: bash scripts/sync_mt5.sh

echo "🚀 Начинаем синхронизацию MQL5 роботов с MT5..."
echo ""

# Определяем пути
REPO_PATH="/Users/pablonachos/Documents/Git Projects/TradingRobots"
MT5_SYNC_PATH="/Users/pablonachos/MT5Sync/Experts"
MT5_WINDOWS_PATH="C:\\Users\\pablonachos\\AppData\\Roaming\\MetaQuotes\\Terminal\\010E047102812FC0C18890992854220E\\MQL5\\Experts"

# Проверяем, существуют ли необходимые папки
if [ ! -d "$REPO_PATH" ]; then
    echo "❌ Ошибка: Папка репозитория не найдена: $REPO_PATH"
    exit 1
fi

if [ ! -d "$MT5_SYNC_PATH" ]; then
    echo "❌ Ошибка: Папка MT5Sync не найдена: $MT5_SYNC_PATH"
    echo "💡 Убедитесь, что общая папка Parallels настроена правильно"
    exit 1
fi

# Показываем что будем синхронизировать
echo "📁 Исходная папка: $REPO_PATH"
echo "🔄 Промежуточная:  $MT5_SYNC_PATH"
echo "🎯 Целевая папка:   $MT5_WINDOWS_PATH"
echo ""

# Шаг 1: Синхронизируем в общую папку Parallels
echo "⏳ Шаг 1: Синхронизируем в общую папку..."
rsync -av --delete --exclude='.git' --exclude='.kilocode' --exclude='docs' --exclude='scripts' --exclude='README.md' "$REPO_PATH/" "$MT5_SYNC_PATH/"

if [ $? -ne 0 ]; then
    echo "❌ Ошибка при синхронизации в общую папку!"
    exit 1
fi

# Шаг 2: Копируем файлы в MT5 через Windows
echo "⏳ Шаг 2: Копируем файлы в MT5..."
prlctl exec "Windows 11" cmd /c "xcopy \"\\\\psf\\MT5Sync\\Experts\\*\" \"$MT5_WINDOWS_PATH\\\" /E /Y /I" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Синхронизация завершена успешно!"
    echo ""
    echo "📊 Синхронизированные роботы:"
    ls -la "$MT5_SYNC_PATH" | grep "^d" | awk '{print "   📁 " $9}' | grep -v "^\s*📁\s*\.$" | grep -v "^\s*📁\s*\.\.$"
    echo ""
    echo "🎮 Файлы скопированы в MT5 Navigator → Expert Advisors"
    echo "💡 Перезапустите MetaEditor или обновите Navigator для отображения изменений"
else
    echo ""
    echo "❌ Ошибка при копировании в MT5!"
    echo "💡 Проверьте, что Windows VM запущена и MT5 установлен"
    exit 1
fi

echo ""
echo "🏁 Готово!"