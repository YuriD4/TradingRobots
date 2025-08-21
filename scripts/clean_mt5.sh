#!/bin/bash

# Complete MT5 Data Cleanup Script
# Полный скрипт очистки с закрытием и перезапуском MT5

echo "🧹 ПОЛНАЯ ОЧИСТКА ДАННЫХ MT5"
echo "============================"

# Основные пути
MT5_BASE_PATH="C:\\Users\\pablonachos\\AppData\\Roaming\\MetaQuotes\\Terminal\\010E047102812FC0C18890992854220E"
MT5_TESTER_PATH="C:\\Users\\pablonachos\\AppData\\Roaming\\MetaQuotes\\Tester"
MT5_PROGRAM_PATH="C:\\Program Files\\MetaTrader 5 IC Markets Global"

# Функция для получения размера папки
get_folder_size() {
    local path="$1"
    size=$(prlctl exec "Windows 11" powershell -Command "
        if (Test-Path '$path') {
            \$size = (Get-ChildItem '$path' -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if (\$size) { [math]::Round(\$size/1GB,2) } else { 0 }
        } else { 0 }
    " 2>/dev/null | tr -d '\r')
    echo "$size"
}

# Получаем размеры до очистки
bases_size=$(get_folder_size "$MT5_BASE_PATH\\bases")
tester_size=$(get_folder_size "$MT5_BASE_PATH\\tester")
main_tester_size=$(get_folder_size "$MT5_TESTER_PATH")
total_size=$(echo "$bases_size + $tester_size + $main_tester_size" | bc -l 2>/dev/null || echo "н/д")

echo "📊 Найдено данных для очистки:"
printf "• bases: %s ГБ\n" "$bases_size"
printf "• tester: %s ГБ\n" "$tester_size"  
printf "• Tester: %s ГБ\n" "$main_tester_size"
printf "• ИТОГО: %s ГБ\n" "$total_size"

if [ "$total_size" = "0" ] || [ "$total_size" = "н/д" ]; then
    echo "❌ Нет данных для очистки"
    exit 1
fi

echo ""
echo "🔄 ШАГ 1: Закрытие всех MT5 программ..."

# Закрываем все MT5 процессы
prlctl exec "Windows 11" powershell -Command "
    Write-Host 'Закрытие MT5 процессов...'
    
    # Список процессов для закрытия
    \$processes = @('terminal64', 'terminal', 'metatrader', 'metaeditor', 'mt5', 'MetaEditor')
    
    foreach (\$proc in \$processes) {
        Get-Process -Name \$proc -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host 'Закрываю:' \$_.ProcessName
            \$_.Kill()
        }
    }
    
    # Дополнительно ищем по пути
    Get-Process | Where-Object {
        \$_.Path -like '*MetaTrader*' -or 
        \$_.Path -like '*MetaQuotes*' -or
        \$_.Path -like '*terminal*'
    } | ForEach-Object {
        Write-Host 'Закрываю по пути:' \$_.ProcessName
        \$_.Kill()
    }
    
    Write-Host 'Ожидание завершения процессов...'
    Start-Sleep -Seconds 3
" 2>/dev/null

echo "✅ Все MT5 программы закрыты"

echo ""
echo "🧹 ШАГ 2: Очистка данных..."

# Очищаем все папки
prlctl exec "Windows 11" powershell -Command "
    Write-Host 'Принудительная очистка данных...'
    
    # Функция для принудительного удаления
    function Force-RemoveFiles {
        param(\$path, \$name)
        
        if (Test-Path \$path) {
            Write-Host \"Очистка \$name...\"
            try {
                # Удаляем все файлы принудительно
                Get-ChildItem \$path -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        Remove-Item \$_.FullName -Force -ErrorAction Stop
                    } catch {
                        # Если файл заблокирован, пробуем через cmd
                        cmd /c \"del /F /Q \\\"\$(\$_.FullName)\\\" 2>nul\"
                    }
                }
                
                # Удаляем папки
                Get-ChildItem \$path -Recurse -Directory -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object {
                    try {
                        Remove-Item \$_.FullName -Recurse -Force -ErrorAction Stop
                    } catch {
                        cmd /c \"rmdir /S /Q \\\"\$(\$_.FullName)\\\" 2>nul\"
                    }
                }
                
                Write-Host \"✅ \$name очищена\"
            } catch {
                Write-Host \"⚠️ Частичная очистка \$name\"
            }
        }
    }
    
    # Очищаем все папки
    Force-RemoveFiles '$MT5_BASE_PATH\\bases' 'bases'
    Force-RemoveFiles '$MT5_BASE_PATH\\tester' 'tester'
    Force-RemoveFiles '$MT5_TESTER_PATH' 'Tester'
    Force-RemoveFiles '$MT5_BASE_PATH\\logs' 'logs'
    
    Write-Host 'Очистка завершена!'
" 2>/dev/null

echo "✅ Данные очищены"

echo ""
echo "🔄 ШАГ 3: Перезапуск MT5..."

# Запускаем MT5 обратно
prlctl exec "Windows 11" powershell -Command "
    Write-Host 'Запуск MetaTrader 5...'
    
    # Ищем исполняемый файл MT5
    \$mt5Paths = @(
        '$MT5_PROGRAM_PATH\\terminal64.exe',
        'C:\\Program Files (x86)\\MetaTrader 5\\terminal64.exe',
        'C:\\Program Files\\MetaTrader 5\\terminal64.exe'
    )
    
    foreach (\$path in \$mt5Paths) {
        if (Test-Path \$path) {
            Write-Host 'Найден MT5:' \$path
            Start-Process \$path -WindowStyle Minimized
            Write-Host '✅ MT5 запущен'
            break
        }
    }
    
    Write-Host 'Запуск MetaEditor...'
    
    # Ищем MetaEditor
    \$editorPaths = @(
        '$MT5_PROGRAM_PATH\\metaeditor64.exe',
        'C:\\Program Files (x86)\\MetaTrader 5\\metaeditor64.exe',
        'C:\\Program Files\\MetaTrader 5\\metaeditor64.exe'
    )
    
    foreach (\$path in \$editorPaths) {
        if (Test-Path \$path) {
            Write-Host 'Найден MetaEditor:' \$path
            Start-Process \$path -WindowStyle Minimized
            Write-Host '✅ MetaEditor запущен'
            break
        }
    }
" 2>/dev/null

# Проверяем результат
echo ""
echo "📊 РЕЗУЛЬТАТ ОЧИСТКИ:"
echo "===================="

new_bases_size=$(get_folder_size "$MT5_BASE_PATH\\bases")
new_tester_size=$(get_folder_size "$MT5_BASE_PATH\\tester")
new_main_tester_size=$(get_folder_size "$MT5_TESTER_PATH")

printf "• bases: %s ГБ → %s ГБ\n" "$bases_size" "$new_bases_size"
printf "• tester: %s ГБ → %s ГБ\n" "$tester_size" "$new_tester_size"
printf "• Tester: %s ГБ → %s ГБ\n" "$main_tester_size" "$new_main_tester_size"

if command -v bc >/dev/null 2>&1; then
    freed_space=$(echo "$total_size - $new_bases_size - $new_tester_size - $new_main_tester_size" | bc -l 2>/dev/null)
    echo ""
    echo "✅ Освобождено: ~$freed_space ГБ"
else
    echo ""
    echo "✅ Очистка завершена!"
fi

echo ""
echo "💡 MT5 и MetaEditor перезапущены и готовы к работе!"