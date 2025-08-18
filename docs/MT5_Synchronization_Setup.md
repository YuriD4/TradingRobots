# Настройка синхронизации MQL5 роботов с MT5 через Parallels Desktop

## Обзор решения

Эта инструкция описывает, как настроить синхронизацию MQL5 файлов между Git репозиторием на Mac и MT5 терминалом в Parallels Desktop Windows VM с использованием rsync и общих папок Parallels.

## Архитектура решения

```
Mac (Git репозиторий)
├── TradingRobots/
│   ├── WiktarTgScreener/
│   ├── Robot2/
│   ├── Robot3/
│   └── scripts/
│       └── sync_mt5.sh       # Скрипт синхронизации
│
├── MT5Sync/Experts/          # Общая папка Parallels (промежуточная)
│   ├── WiktarTgScreener/     # Копия из репозитория
│   ├── Robot2/               # Копия из репозитория
│   └── Robot3/               # Копия из репозитория
│
Windows VM (MT5)
├── \\psf\MT5Sync\Experts\    # Доступ к общей папке
└── C:\Users\...\MetaQuotes\Terminal\...\MQL5\Experts\  # Реальная папка MT5
    ├── WiktarTgScreener/     # Финальное расположение
    ├── Robot2/
    └── Robot3/
```

## Первоначальная настройка (уже выполнена)

### 1. Создание общей папки MT5Sync
```bash
mkdir -p ~/MT5Sync
```

### 2. Добавление общей папки в Parallels
```bash
prlctl set "Windows 11" --shf-host-add MT5Sync --path ~/MT5Sync
```

### 3. Создание структуры папок
```bash
mkdir -p ~/MT5Sync/Experts
```

### 4. Первоначальная синхронизация
```bash
# Выполнить скрипт синхронизации
./scripts/sync_mt5.sh
```

## Ежедневная работа

### Простой способ - использование скрипта (рекомендуемый)
1. **Перетащите файл** `scripts/sync_mt5.sh` в терминал
2. **Нажмите Enter** - синхронизация выполнена!

### Альтернативный способ - команда rsync
```bash
rsync -av --delete --exclude='.git' --exclude='.kilocode' --exclude='docs' --exclude='scripts' --exclude='README.md' "/Users/pablonachos/Documents/Git Projects/TradingRobots/" ~/MT5Sync/Experts/
```

## Добавление нового робота

### Шаг 1: Создание папки робота в репозитории
```bash
cd "/Users/pablonachos/Documents/Git Projects/TradingRobots"
mkdir NewRobotName
```

### Шаг 2: Добавление файлов .mq5 и .mqh в папку робота

### Шаг 3: Синхронизация
```bash
# Перетащите scripts/sync_mt5.sh в терминал или выполните:
./scripts/sync_mt5.sh
```

### Шаг 4: Проверка результата
Новый робот появится в MT5 Navigator → Expert Advisors

## Настройка MT5 в Windows

### 1. Доступ к общим папкам
В Windows VM общие папки Parallels доступны по пути:
```
\\psf\MT5Sync\Experts\
```

### 2. Настройка MT5
1. Откройте MT5 в Windows VM
2. Перейдите в **File → Open Data Folder**
3. Откройте папку **MQL5 → Experts**
4. Создайте символические ссылки или скопируйте содержимое из `\\psf\MT5Sync\Experts\`

### Альтернативный способ (рекомендуемый):
1. В MT5 перейдите в **Tools → Options → Expert Advisors**
2. Добавьте путь `\\psf\MT5Sync\Experts` в список дополнительных папок

## Проверка работы

### 1. Проверка символических ссылок на Mac
```bash
ls -la ~/MT5Sync/Experts/
# Должны видеть ссылки вида: WiktarTgScreener -> /Users/pablonachos/Documents/Git Projects/TradingRobots/WiktarTgScreener
```

### 2. Проверка доступности файлов
```bash
ls -la ~/MT5Sync/Experts/WiktarTgScreener/
# Должны видеть файлы: TelegramHelper.mqh, WiktarIndicator.mq5
```

### 3. Проверка в MT5
- Откройте Navigator в MT5
- В разделе Expert Advisors должны появиться папки с вашими роботами
- Каждый робот должен быть в своей отдельной папке

## Рабочий процесс

### Ежедневная работа:
1. **Редактирование кода**: Работайте с файлами в Git репозитории на Mac
2. **Синхронизация**: Перетащите `scripts/sync_mt5.sh` в терминал после изменений
3. **Обновление Navigator**: Перезапустите MetaEditor или обновите Navigator
4. **Компиляция**: Компилируйте код прямо в MT5
5. **Git операции**: Коммитьте изменения из репозитория на Mac

### Добавление нового робота:
1. Создайте папку в репозитории
2. Добавьте файлы .mq5 и .mqh
3. Выполните синхронизацию скриптом
4. Робот появится в MT5 Navigator

## Преимущества этого решения

✅ **Простая синхронизация** - один скрипт для всех роботов
✅ **Организация по папкам** - каждый робот в своей папке в MT5 Navigator
✅ **Git интеграция** - полная поддержка версионирования
✅ **Надежность** - rsync копирует только измененные файлы
✅ **Безопасность** - исключает служебные папки (.git, .kilocode)
✅ **Простота использования** - перетащить скрипт в терминал

## Устранение неполадок

### Проблема: Синхронизация не работает
```bash
# Проверьте, существует ли папка робота
ls -la "/Users/pablonachos/Documents/Git Projects/TradingRobots/RobotName"

# Выполните синхронизацию вручную
./scripts/sync_mt5.sh
```

### Проблема: MT5 не видит файлы
1. Убедитесь, что Parallels Tools установлены в Windows VM
2. Перезапустите MT5
3. Проверьте настройки общих папок в Parallels

### Проблема: Общая папка не доступна в Windows
```bash
# Проверьте статус общих папок
prlctl list -i "Windows 11" | grep -A 5 "Host Shared Folders"

# Пересоздайте общую папку
prlctl set "Windows 11" --shf-host-del MT5Sync
prlctl set "Windows 11" --shf-host-add MT5Sync --path ~/MT5Sync
```

## Команды для быстрого копирования

### Синхронизация всех роботов:
```bash
# Способ 1: Перетащить скрипт в терминал
# Перетащите файл scripts/sync_mt5.sh в терминал и нажмите Enter

# Способ 2: Выполнить скрипт командой
./scripts/sync_mt5.sh

# Способ 3: Прямая команда rsync
rsync -av --delete --exclude='.git' --exclude='.kilocode' --exclude='docs' --exclude='scripts' --exclude='README.md' "/Users/pablonachos/Documents/Git Projects/TradingRobots/" ~/MT5Sync/Experts/
```

### Добавление нового робота:
```bash
# 1. Создать папку в репозитории
mkdir "/Users/pablonachos/Documents/Git Projects/TradingRobots/NewRobotName"

# 2. Добавить файлы .mq5 и .mqh в папку

# 3. Синхронизировать
./scripts/sync_mt5.sh
```

---

**Дата создания:** 18 августа 2025  
**Статус:** Настроено и протестировано  
**Текущие роботы:** WiktarTgScreener