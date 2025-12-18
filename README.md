# Kubespray Bootstrap Template

Публичный репозиторий-шаблон для быстрого развёртывания Kubernetes кластера через Kubespray в облаке.

## Описание

Этот репозиторий предназначен для:
- Отладки установки Kubernetes кластера в облаке (4 VM) с запуском Kubespray из Docker-контейнера на bastion-хосте
- Использования как шаблона для быстрого старта на проде

## Топология стенда

- **ОС нод**: AlmaLinux 9.0
- **Ноды**: 3 мастера + 1 воркер
- **Ресурсы каждой ноды**: 1 vCPU, 2 GB RAM, 30 GB SSD
- **Bastion-хост**: в той же приватной сети, SSH-ключи уже настроены
- **Сеть**: общий L2 сегмент (одна приватная подсеть) для работы gratuitous ARP для VIP
- **VIP**: зарезервированные IP под kube-vip

## Конфигурация кластера

- **CNI**: Calico (VXLAN режим)
- **kube-proxy**: iptables (НЕ ipvs)
- **API HA**: kube-vip (VIP в приватной сети, ARP режим)
- **Минимальные аддоны**: только необходимое для базового кластера (dashboard, ingress и т.п. выключены)

## Требования

- Bastion-хост с установленным Docker
- SSH доступ с bastion ко всем нодам кластера
- SSH ключ для доступа к нодам
- Python 3 (для Makefile, опционально)

## Быстрый старт

### 1. Подготовка репозитория и Docker-образа

```bash
# Клонировать репозиторий
git clone <repository-url>
cd kubespray-bootstrap

# Подготовить Docker-образ Kubespray (скачать/обновить)
make bootstrap
```

### 2. Конфигурация

#### 2.1. Создать файл `.env`

```bash
cp env.template .env
```

Отредактируйте `.env` и укажите:
- `SSH_USER` - пользователь для SSH (обычно `root`)
- `SSH_KEY_PATH` - путь к SSH приватному ключу
- `INVENTORY_PATH` - путь к рабочему инвентарю (по умолчанию `inventory/cluster`)
- `KUBE_VIP_VIP` - VIP адрес для kube-vip (например, `10.0.0.100`)
- `KUBE_VIP_INTERFACE` - сетевой интерфейс для kube-vip (например, `eth0`)
- `KUBERNETES_VERSION` - версия Kubernetes (по умолчанию `1.32.0`)
- `KUBESPRAY_TAG` - тег/ветка Kubespray (по умолчанию `release-2.29`)

#### 2.2. Создать inventory

```bash
# Скопировать пример инвентаря
cp -r inventory.example inventory/cluster
```

Отредактируйте `inventory/cluster/hosts.yaml` и укажите реальные IP адреса ваших нод:

```yaml
all:
  hosts:
    master1:
      ansible_host: 10.0.0.11  # Замените на реальный IP
      ip: 10.0.0.11
      access_ip: 10.0.0.11
    master2:
      ansible_host: 10.0.0.12  # Замените на реальный IP
      ip: 10.0.0.12
      access_ip: 10.0.0.12
    master3:
      ansible_host: 10.0.0.13  # Замените на реальный IP
      ip: 10.0.0.13
      access_ip: 10.0.0.13
    worker1:
      ansible_host: 10.0.0.21  # Замените на реальный IP
      ip: 10.0.0.21
      access_ip: 10.0.0.21
  children:
    kube_control_plane:
      hosts:
        master1:
        master2:
        master3:
    kube_node:
      hosts:
        worker1:
    etcd:
      hosts:
        master1:
        master2:
        master3:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
```

**Важно о структуре inventory:**

Группа `k8s_cluster` объединяет все ноды кластера (masters + workers) в одну логическую группу. 
Это необходимо для Kubespray, так как:

- Многие роли применяются ко всем узлам (container runtime, sysctl, kubelet, CNI-плагины, сертификаты)
- Kubespray использует `k8s_cluster` как таргет для задач, которые должны выполняться на всех нодах
- Без этой группы некоторые плейбуки могут работать некорректно или требовать явного `--limit`

**Структура групп:**
- `kube_control_plane` - только master ноды
- `kube_node` - только worker ноды  
- `etcd` - ноды с etcd (обычно те же, что и masters)
- `k8s_cluster` - все ноды кластера (объединяет control plane + nodes)

#### 2.3. Настроить group_vars

Файлы в `inventory.example/group_vars/` уже содержат базовые настройки. Вы можете использовать их как есть или скопировать дополнительные настройки из `config/group_vars/` (это шаблоны с дефолтными значениями).

Отредактируйте `inventory/cluster/group_vars/all/all.yml`:

```yaml
ansible_user: root  # Должен совпадать с SSH_USER из .env
kube_interface: "eth0"  # Сетевой интерфейс на нодах
kube_vip_vip: "10.0.0.100"  # Должен совпадать с KUBE_VIP_VIP из .env
kube_vip_interface: "eth0"  # Должен совпадать с KUBE_VIP_INTERFACE из .env
```

Отредактируйте `inventory/cluster/group_vars/k8s_cluster/k8s-cluster.yml` при необходимости (версия Kubernetes и т.п.).

### 3. Проверка подключения

Перед установкой проверьте доступность всех нод:

```bash
make ping
```

Эта команда выполнит `ansible ping` для всех хостов в инвентаре.

### 4. Установка кластера

```bash
make install
```

Эта команда запустит `cluster.yml` playbook из Kubespray внутри Docker контейнера. Процесс займёт 15-30 минут в зависимости от скорости сети и нод.

### 5. Получение kubeconfig

После успешной установки скопируйте kubeconfig:

```bash
make kubeconfig
```

Kubeconfig будет сохранён в `artifacts/kubeconfig`.

Использование:

```bash
export KUBECONFIG=$(pwd)/artifacts/kubeconfig
kubectl get nodes
kubectl get pods --all-namespaces
```

### 6. Проверка kube-vip

#### Проверка VIP на нодах

```bash
# На любой ноде кластера
ip addr show eth0 | grep 10.0.0.100
```

VIP должен быть назначен на одном из мастер-нод.

#### Проверка ARP таблицы

```bash
# На bastion или другой ноде в той же сети
ip neigh show | grep 10.0.0.100
```

#### Проверка доступности API

```bash
# С bastion или любой ноды в приватной сети
curl -k https://10.0.0.100:6443/healthz
```

Должен вернуться `ok`.

#### Проверка через kubectl

```bash
export KUBECONFIG=$(pwd)/artifacts/kubeconfig
kubectl cluster-info
```

В выводе должен быть указан VIP адрес.

## Масштабирование (добавление воркера)

### 1. Добавить воркер в inventory

Отредактируйте `inventory/cluster/hosts.yaml`:

```yaml
all:
  hosts:
    # ... существующие ноды ...
    worker2:  # Новый воркер
      ansible_host: 10.0.0.22
      ip: 10.0.0.22
      access_ip: 10.0.0.22
  children:
    # ...
    kube_node:
      hosts:
        worker1:
        worker2:  # Добавить нового воркера
    # k8s_cluster автоматически включает всех воркеров через kube_node
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:  # Новый воркер автоматически попадает сюда
```

**Примечание:** Группа `k8s_cluster` автоматически включает всех воркеров через `kube_node`, поэтому при добавлении нового воркера в `kube_node` он автоматически становится частью `k8s_cluster`.

### 2. Запустить scale playbook

```bash
make scale
```

Эта команда запустит `scale.yml` playbook, который добавит новую ноду в кластер.

### 3. Проверить

```bash
export KUBECONFIG=$(pwd)/artifacts/kubeconfig
kubectl get nodes
```

Новая нода должна появиться в статусе `Ready`.

## Сброс/удаление кластера

⚠️ **Внимание**: Эта операция полностью удалит кластер!

```bash
make reset
```

Команда запросит подтверждение перед выполнением `reset.yml` playbook.

## Доступные команды

| Команда | Описание |
|---------|----------|
| `make bootstrap` | Скачать/обновить Docker-образ Kubespray |
| `make ping` | Проверить доступность всех нод |
| `make install` | Установить кластер (cluster.yml) |
| `make scale` | Добавить воркер (scale.yml) |
| `make reset` | Удалить кластер (reset.yml) |
| `make kubeconfig` | Скопировать kubeconfig с мастера |
| `make shell` | Открыть shell в kubespray контейнере |
| `make clean` | Очистить временные файлы и артефакты |
| `make help` | Показать справку |

## Структура проекта

```
kubespray-bootstrap/
├── inventory.example/      # Пример инвентаря (в репозитории)
│   ├── hosts.yaml
│   └── group_vars/
├── inventory/cluster/      # Рабочий инвентарь (в .gitignore)
├── config/                 # Шаблоны конфигурации
│   └── group_vars/
├── scripts/                # Утилиты для запуска
│   ├── run-playbook.sh
│   └── ping-hosts.sh
├── artifacts/              # Артефакты (kubeconfig, логи) (в .gitignore)
├── .env                    # Переменные окружения (в .gitignore)
├── env.template            # Шаблон .env
├── docker-compose.yml      # Docker Compose конфигурация
├── Makefile                # Команды для управления
├── .gitignore
└── README.md
```

## Типичные проблемы на AlmaLinux 9

### Firewalld

Kubespray автоматически настраивает firewalld, но если возникают проблемы:

```bash
# На нодах проверить статус
systemctl status firewalld

# Если нужно временно отключить для отладки
systemctl stop firewalld
systemctl disable firewalld
```

**Важно**: В продакшене firewalld должен быть включён и настроен правильно.

### SELinux

Kubespray настраивает SELinux в режиме `permissive` для контейнеров. Проверить:

```bash
# На нодах
getenforce
sestatus
```

Если нужно принудительно установить permissive (не рекомендуется для прода):

```bash
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
```

### Недостаточно памяти

При 2GB RAM на ноду могут возникать проблемы с OOM. Проверьте:

```bash
# На нодах
free -h
dmesg | grep -i oom
```

Если нужно, уменьшите `kubelet_max_pods` в `inventory/cluster/group_vars/k8s_cluster/k8s-cluster.yml`.

### Проблемы с kube-vip

Если VIP не работает:

1. Проверьте, что все ноды в одной L2 сети:
   ```bash
   # На нодах
   ip addr show eth0
   ```

2. Проверьте ARP таблицу:
   ```bash
   ip neigh show
   ```

3. Проверьте логи kube-vip:
   ```bash
   kubectl logs -n kube-system -l app=kube-vip
   ```

4. Убедитесь, что интерфейс указан правильно в `kube_vip_interface`.

### Проблемы с Calico

Если поды Calico не запускаются:

```bash
# Проверить статус
kubectl get pods -n kube-system | grep calico

# Проверить логи
kubectl logs -n kube-system -l k8s-app=calico-node
```

Убедитесь, что:
- Интерфейс `kube_interface` указан правильно
- Нет конфликтов с firewalld
- VXLAN порты (4789/UDP) открыты

## Безопасность

⚠️ **Важно**: Этот репозиторий публичный. НИКОГДА не коммитьте:

- Файлы из `inventory/cluster/`
- Файл `.env`
- SSH ключи (`*.key`, `id_rsa*`, `id_ed25519*`)
- Kubeconfig файлы
- Любые файлы с реальными IP адресами или доменами продакшн среды

Все приватные данные должны быть в `.gitignore`.

## Внутренние Docker/образные репозитории (air-gapped)

Для лабораторного стенда по умолчанию используются **публичные реестры**:

- Kubernetes образы — `registry.k8s.io`
- Docker Hub — `registry-1.docker.io` (через стандартную конфигурацию runtime)

В файле `config/group_vars/all/all.yml` заранее заложены переменные для удобного перехода на внутренний реестр:

- `use_internal_registry` — переключатель (по умолчанию `false`)
- `upstream_kube_image_repo` — текущий публичный репозиторий для k8s‑образов (`registry.k8s.io`)
- `internal_kube_image_repo` — плейсхолдер для внутреннего репозитория
- `kube_image_repo` — эффективный репозиторий, который реально использует Kubespray
- `upstream_docker_registry_mirror` / `internal_docker_registry_mirror` / `docker_registry_mirrors` — зеркала для Docker‑runtime

Поведение:

- В тестовом стенде (`use_internal_registry: false`) всё тянется из публичных реестров.
- Для air‑gapped/прод окружения вы:
  1. Настраиваете и наполняете внутренний registry.
  2. В `inventory/cluster/group_vars/all/all.yml` задаёте:
     ```yaml
     use_internal_registry: true
     internal_kube_image_repo: "registry.example.com/k8s"            # пример
     internal_docker_registry_mirror: "https://registry.example.com" # пример
     ```
  3. При необходимости дополнительно настраиваете специфичные для containerd переменные (`containerd_registry_mirrors`) согласно документации Kubespray.

## Версионирование

Версии по умолчанию (можно изменить в `.env`):

- **Kubernetes**: 1.32.0
- **Kubespray**: release-2.29 (v2.29.1)
- **Calico**: v3.26.0

Для использования других версий отредактируйте `.env` и соответствующие файлы в `inventory/cluster/group_vars/`.

## Поддержка

При возникновении проблем:

1. Проверьте логи установки
2. Проверьте доступность нод (`make ping`)
3. Проверьте настройки в `.env` и `inventory/cluster/`
4. Изучите раздел "Типичные проблемы" выше

## Лицензия

Этот репозиторий является шаблоном и может быть использован свободно.
