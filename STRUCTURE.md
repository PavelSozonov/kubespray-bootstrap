# Структура проекта

Краткое описание структуры репозитория.

## Основные директории

- **`inventory.example/`** - Пример inventory с шаблонами (в репозитории)
- **`inventory/cluster/`** - Рабочий inventory (в .gitignore, создаётся пользователем)
- **`config/`** - Шаблоны конфигурации Kubespray (group_vars)
- **`scripts/`** - Утилиты для запуска playbook из Docker
- **`artifacts/`** - Артефакты (kubeconfig, логи) - в .gitignore

## Основные файлы

- **`README.md`** - Подробная документация и инструкции
- **`Makefile`** - Команды для управления кластером
- **`env.template`** - Шаблон переменных окружения
- **`.env`** - Переменные окружения (в .gitignore, создаётся пользователем)
- **`docker-compose.yml`** - Docker Compose конфигурация (опционально)
- **`.gitignore`** - Исключения для Git

## Команды Makefile

- `make bootstrap` - Скачать/обновить Docker-образ Kubespray
- `make ping` - Проверить доступность нод
- `make install` - Установить кластер
- `make scale` - Добавить воркер
- `make reset` - Удалить кластер
- `make kubeconfig` - Получить kubeconfig
- `make shell` - Открыть shell в контейнере
- `make clean` - Очистить временные файлы

## Workflow

1. Клонировать репозиторий
2. `make bootstrap` - скачать Kubespray Docker-образ
3. `cp env.template .env` - создать .env
4. Отредактировать `.env` с вашими значениями
5. `cp -r inventory.example inventory/cluster` - создать inventory
6. Отредактировать `inventory/cluster/` с вашими IP
7. `make ping` - проверить доступность
8. `make install` - установить кластер
9. `make kubeconfig` - получить kubeconfig
