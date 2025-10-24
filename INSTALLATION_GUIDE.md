# Guia Completo de Instalação Manual do Cluster Kubernetes

Este documento detalha todos os passos executados para criar o cluster Kubernetes, permitindo que você replique o processo manualmente.

## Índice

1. [Visão Geral da Arquitetura](#visão-geral-da-arquitetura)
2. [Pré-requisitos](#pré-requisitos)
3. [Preparação da Infraestrutura](#preparação-da-infraestrutura)
4. [Configuração de Todas as Máquinas](#configuração-de-todas-as-máquinas)
5. [Configuração do Control Plane](#configuração-do-control-plane)
6. [Adição dos Worker Nodes](#adição-dos-worker-nodes)
7. [Verificação do Cluster](#verificação-do-cluster)
8. [Troubleshooting](#troubleshooting)

---

## Visão Geral da Arquitetura

### Componentes do Cluster

**Control Plane (Master Node):**
- **Hostname**: controlplane
- **IP**: 10.17.3.142
- **Recursos**: 4GB RAM, 2 vCPUs, 20GB disco
- **Componentes principais**:
  - kube-apiserver: API do Kubernetes
  - etcd: Banco de dados key-value distribuído
  - kube-scheduler: Agendador de pods
  - kube-controller-manager: Controladores do cluster
  - kubelet: Agente do node
  - kube-proxy: Gerenciamento de rede

**Worker Nodes:**
- **Worker 1**:
  - Hostname: worker-1
  - IP: 10.17.3.51
  - Recursos: 2GB RAM, 2 vCPUs, 20GB disco
- **Worker 2**:
  - Hostname: worker-2
  - IP: 10.17.3.124
  - Recursos: 2GB RAM, 2 vCPUs, 20GB disco
- **Componentes**:
  - kubelet: Agente do node
  - kube-proxy: Gerenciamento de rede
  - containerd: Container runtime

**Rede:**
- **Rede de Management**: 10.17.3.0/24 (NAT)
- **Pod Network CIDR**: 10.244.0.0/16 (Flannel)
- **CNI Plugin**: Flannel

**Versões:**
- Kubernetes: v1.28.15
- Containerd: 1.7.28
- Ubuntu: 22.04.5 LTS (Jammy)
- Kernel: 5.15.0-160-generic

---

## Pré-requisitos

### Hardware Mínimo
- Control Plane: 2 CPUs, 4GB RAM, 20GB disco
- Workers: 2 CPUs, 2GB RAM, 20GB disco
- Conexão de rede entre todos os nodes

### Sistema Operacional
- Ubuntu 22.04 LTS (Server Edition)
- Acesso root ou sudo
- Conexão com internet

---

## Preparação da Infraestrutura

### 1. Configuração Inicial do Sistema

Em **TODAS as máquinas** (control plane + workers):

#### 1.1. Atualizar hostname

```bash
# No control plane
sudo hostnamectl set-hostname controlplane

# No worker 1
sudo hostnamectl set-hostname worker-1

# No worker 2
sudo hostnamectl set-hostname worker-2
```

#### 1.2. Configurar /etc/hosts

Adicione as entradas em `/etc/hosts` de todas as máquinas:

```bash
sudo tee -a /etc/hosts <<EOF
10.17.3.142 controlplane controlplane.k8s.local
10.17.3.51 worker-1 worker-1.k8s.local
10.17.3.124 worker-2 worker-2.k8s.local
EOF
```

#### 1.3. Desabilitar swap

O Kubernetes requer que swap esteja desabilitado:

```bash
# Desabilitar swap imediatamente
sudo swapoff -a

# Remover entradas de swap do fstab para persistir após reboot
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Verificar que não há swap ativo
free -h
```

---

## Configuração de Todas as Máquinas

Execute os seguintes passos em **TODAS as máquinas** (control plane + workers):

### 2. Configurar Módulos do Kernel

#### 2.1. Carregar módulos necessários

```bash
# Criar arquivo de configuração para carregar módulos no boot
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

# Carregar módulos imediatamente
sudo modprobe overlay
sudo modprobe br_netfilter

# Verificar que os módulos foram carregados
lsmod | grep overlay
lsmod | grep br_netfilter
```

**Explicação:**
- `overlay`: Necessário para o overlay filesystem usado por containerd
- `br_netfilter`: Permite que iptables enxergue tráfego bridged

### 3. Configurar Parâmetros de Rede (sysctl)

#### 3.1. Configurar parâmetros do kernel

```bash
# Criar arquivo de configuração sysctl
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Aplicar configurações sem reiniciar
sudo sysctl --system

# Verificar configurações
sudo sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward
```

**Explicação:**
- `net.bridge.bridge-nf-call-iptables = 1`: Permite que pacotes IPv4 bridged sejam processados pelo iptables
- `net.bridge.bridge-nf-call-ip6tables = 1`: Permite que pacotes IPv6 bridged sejam processados pelo ip6tables
- `net.ipv4.ip_forward = 1`: Habilita encaminhamento de pacotes IPv4 (necessário para roteamento de pods)

### 4. Instalar Dependências Base

```bash
# Atualizar lista de pacotes
sudo apt-get update

# Instalar pacotes necessários
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
```

**Explicação:**
- `apt-transport-https`: Permite ao APT usar repositórios HTTPS
- `ca-certificates`: Certificados SSL/TLS confiáveis
- `curl`: Ferramenta para transferir dados com URLs
- `gnupg`: Gerenciamento de chaves GPG
- `lsb-release`: Informações sobre a versão do Linux

### 5. Instalar Container Runtime (containerd)

#### 5.1. Adicionar repositório Docker

```bash
# Adicionar chave GPG do Docker
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Adicionar repositório
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

#### 5.2. Instalar containerd

```bash
# Atualizar lista de pacotes
sudo apt-get update

# Instalar containerd
sudo apt-get install -y containerd.io
```

#### 5.3. Configurar containerd

```bash
# Criar diretório de configuração
sudo mkdir -p /etc/containerd

# Gerar configuração padrão
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Configurar systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Reiniciar containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verificar status
sudo systemctl status containerd
```

**Explicação:**
- `SystemdCgroup = true`: Usa systemd como cgroup driver, recomendado para sistemas com systemd
- O cgroup driver deve ser o mesmo entre containerd e kubelet

### 6. Instalar Kubernetes (kubeadm, kubelet, kubectl)

#### 6.1. Adicionar repositório Kubernetes

```bash
# Criar diretório para keyrings
sudo mkdir -p /etc/apt/keyrings

# Adicionar chave GPG do Kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | \
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Adicionar repositório
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | \
    sudo tee /etc/apt/sources.list.d/kubernetes.list
```

#### 6.2. Instalar pacotes Kubernetes

```bash
# Atualizar lista de pacotes
sudo apt-get update

# Instalar kubelet, kubeadm e kubectl
sudo apt-get install -y kubelet kubeadm kubectl

# Impedir atualizações automáticas
sudo apt-mark hold kubelet kubeadm kubectl

# Verificar versões instaladas
kubelet --version
kubeadm version
kubectl version --client
```

**Explicação dos componentes:**
- **kubeadm**: Ferramenta para inicializar e gerenciar o cluster
- **kubelet**: Agente que roda em cada node e gerencia containers
- **kubectl**: CLI para interagir com o cluster Kubernetes

---

## Configuração do Control Plane

Execute os seguintes passos **APENAS no control plane**:

### 7. Inicializar o Cluster Kubernetes

#### 7.1. Executar kubeadm init

```bash
# Inicializar o cluster
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=10.17.3.142

# Salvar o output completo, especialmente o comando 'kubeadm join'
```

**Parâmetros explicados:**
- `--pod-network-cidr=10.244.0.0/16`: Range de IPs para pods (requerido pelo Flannel)
- `--apiserver-advertise-address`: IP que o API server anuncia (IP do control plane)

**Output esperado:**
```
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 10.17.3.142:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

#### 7.2. Configurar kubectl para usuário não-root

```bash
# Criar diretório .kube
mkdir -p $HOME/.kube

# Copiar arquivo de configuração
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# Ajustar permissões
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Testar acesso
kubectl get nodes
```

**Explicação:**
- O arquivo `admin.conf` contém certificados e configurações para acessar o cluster
- Copiando para `~/.kube/config`, o kubectl sabe como se autenticar

### 8. Instalar Plugin CNI (Flannel)

#### 8.1. Aplicar manifesto do Flannel

```bash
# Baixar e aplicar Flannel
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Verificar instalação
kubectl get pods -n kube-flannel
kubectl get nodes
```

**Explicação:**
- **CNI (Container Network Interface)**: Plugin de rede que permite comunicação entre pods
- **Flannel**: Solução de rede overlay simples que usa VXLAN
- Sem CNI, os nodes ficam em estado "NotReady"

#### 8.2. Verificar componentes do control plane

```bash
# Ver todos os pods do sistema
kubectl get pods -n kube-system

# Verificar componentes
kubectl get componentstatuses

# Ver detalhes dos nodes
kubectl get nodes -o wide
```

**Componentes esperados:**
- `coredns-*`: DNS interno do cluster
- `etcd-controlplane`: Banco de dados distribuído
- `kube-apiserver-controlplane`: API do Kubernetes
- `kube-controller-manager-controlplane`: Gerenciador de controladores
- `kube-proxy-*`: Gerenciamento de rede
- `kube-scheduler-controlplane`: Agendador de pods

---

## Adição dos Worker Nodes

Execute os seguintes passos em **CADA worker node**:

### 9. Obter Comando de Join

#### 9.1. No control plane, gerar comando de join

```bash
# Se perdeu o comando original, gere um novo token
sudo kubeadm token create --print-join-command
```

**Output exemplo:**
```
kubeadm join 10.17.3.142:6443 --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

### 10. Juntar Worker ao Cluster

#### 10.1. Executar comando de join no worker

```bash
# No worker node, executar como root
sudo kubeadm join 10.17.3.142:6443 \
    --token abcdef.0123456789abcdef \
    --discovery-token-ca-cert-hash sha256:1234567890abcdef...
```

**Explicação dos parâmetros:**
- `--token`: Token de autenticação (válido por 24h por padrão)
- `--discovery-token-ca-cert-hash`: Hash do certificado CA para validar identidade do control plane

**Output esperado:**
```
This node has joined the cluster:
* Certificate signing request was sent to apiserver and a response was received.
* The Kubelet was informed of the new secure connection details.
```

#### 10.2. Verificar no control plane

```bash
# De volta ao control plane
kubectl get nodes

# Ver mais detalhes
kubectl get nodes -o wide
```

**Status esperado:**
- Inicialmente: `NotReady` (CNI sendo configurado)
- Após ~30 segundos: `Ready`

### 11. Repetir para Todos os Workers

Repita o passo 10 para cada worker adicional (worker-2, etc.)

---

## Verificação do Cluster

### 12. Testes de Funcionalidade

#### 12.1. Verificar status dos nodes

```bash
# Ver todos os nodes
kubectl get nodes

# Ver detalhes incluindo IPs e versões
kubectl get nodes -o wide

# Ver labels dos nodes
kubectl get nodes --show-labels
```

#### 12.2. Verificar todos os pods do sistema

```bash
# Ver pods em todos os namespaces
kubectl get pods -A

# Ver pods em namespace específico
kubectl get pods -n kube-system
kubectl get pods -n kube-flannel
```

#### 12.3. Testar agendamento de pods

```bash
# Criar um pod de teste
kubectl run nginx --image=nginx

# Verificar se foi criado
kubectl get pods

# Ver em qual node foi agendado
kubectl get pods -o wide

# Acessar logs
kubectl logs nginx

# Deletar pod de teste
kubectl delete pod nginx
```

#### 12.4. Testar deployment com múltiplas réplicas

```bash
# Criar deployment com 3 réplicas
kubectl create deployment nginx --image=nginx --replicas=3

# Verificar distribuição entre nodes
kubectl get pods -o wide

# Ver detalhes do deployment
kubectl get deployment nginx

# Escalar deployment
kubectl scale deployment nginx --replicas=5

# Verificar nova distribuição
kubectl get pods -o wide

# Limpar
kubectl delete deployment nginx
```

#### 12.5. Testar conectividade de rede

```bash
# Criar dois pods para teste
kubectl run test1 --image=busybox --command -- sleep 3600
kubectl run test2 --image=busybox --command -- sleep 3600

# Obter IPs dos pods
kubectl get pods -o wide

# Testar ping entre pods (do test1 para test2)
kubectl exec test1 -- ping -c 3 <IP_DO_TEST2>

# Testar resolução DNS
kubectl exec test1 -- nslookup kubernetes.default

# Limpar
kubectl delete pod test1 test2
```

#### 12.6. Verificar logs do kubelet

```bash
# Em qualquer node
sudo journalctl -u kubelet -f

# Ver últimas 100 linhas
sudo journalctl -u kubelet -n 100
```

---

## Arquitetura Detalhada dos Componentes

### Control Plane Components

#### kube-apiserver
- **Função**: Expõe a API REST do Kubernetes
- **Porta**: 6443 (HTTPS)
- **Localização**: `/etc/kubernetes/manifests/kube-apiserver.yaml`
- **Verificação**: `kubectl cluster-info`

#### etcd
- **Função**: Armazena todo estado do cluster
- **Porta**: 2379 (client), 2380 (peer)
- **Localização**: `/etc/kubernetes/manifests/etcd.yaml`
- **Backup**: 
```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup.db
```

#### kube-scheduler
- **Função**: Decide em qual node cada pod será executado
- **Localização**: `/etc/kubernetes/manifests/kube-scheduler.yaml`
- **Critérios**: Recursos disponíveis, afinidade, taints/tolerations

#### kube-controller-manager
- **Função**: Executa controladores (Node Controller, Replication Controller, etc.)
- **Localização**: `/etc/kubernetes/manifests/kube-controller-manager.yaml`

### Node Components

#### kubelet
- **Função**: Agente que gerencia pods no node
- **Configuração**: `/var/lib/kubelet/config.yaml`
- **Service**: `systemctl status kubelet`

#### kube-proxy
- **Função**: Mantém regras de rede para Services
- **Modo**: iptables (padrão)
- **Verificação**: `kubectl get pods -n kube-system | grep kube-proxy`

#### containerd
- **Função**: Container runtime que executa os containers
- **Socket**: `/run/containerd/containerd.sock`
- **Configuração**: `/etc/containerd/config.toml`
- **Comandos úteis**:
```bash
# Listar containers
sudo crictl ps

# Ver imagens
sudo crictl images

# Ver logs de container
sudo crictl logs <container-id>
```

### Rede (Flannel)

#### Como funciona
1. Flannel cria interface `flannel.1` em cada node
2. Atribui subnet do range 10.244.0.0/16 para cada node
3. Usa VXLAN para encapsular tráfego entre nodes
4. Cada pod recebe IP da subnet do seu node

#### Verificação
```bash
# Ver interfaces de rede
ip addr show flannel.1

# Ver rotas
ip route | grep flannel

# Ver configuração do Flannel
kubectl get configmap -n kube-flannel kube-flannel-cfg -o yaml
```

### Certificados

#### Localização dos certificados
```
/etc/kubernetes/pki/
├── apiserver.crt
├── apiserver.key
├── apiserver-kubelet-client.crt
├── apiserver-kubelet-client.key
├── ca.crt
├── ca.key
├── front-proxy-ca.crt
├── front-proxy-ca.key
├── front-proxy-client.crt
├── front-proxy-client.key
├── sa.key
├── sa.pub
└── etcd/
    ├── ca.crt
    ├── ca.key
    ├── server.crt
    └── server.key
```

#### Verificar expiração
```bash
sudo kubeadm certs check-expiration
```

#### Renovar certificados
```bash
sudo kubeadm certs renew all
```

---

## Troubleshooting

### Problema: Node em estado NotReady

**Verificar:**
```bash
# Ver eventos do node
kubectl describe node <node-name>

# Verificar kubelet
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 50

# Verificar containerd
sudo systemctl status containerd
```

**Soluções comuns:**
- CNI não instalado: Instalar Flannel
- Swap ativado: `sudo swapoff -a`
- Containerd não rodando: `sudo systemctl restart containerd`

### Problema: Pods em estado Pending

**Verificar:**
```bash
# Ver eventos do pod
kubectl describe pod <pod-name>

# Ver logs do scheduler
kubectl logs -n kube-system kube-scheduler-controlplane
```

**Causas comuns:**
- Recursos insuficientes
- Taints no node
- PersistentVolume não disponível

### Problema: Pods não conseguem se comunicar

**Verificar:**
```bash
# Ver status do Flannel
kubectl get pods -n kube-flannel

# Verificar interfaces de rede
ip addr show flannel.1

# Testar ping entre pods
kubectl exec <pod1> -- ping <ip-pod2>
```

**Soluções:**
- Reiniciar pods do Flannel
- Verificar firewall
- Verificar módulos do kernel (br_netfilter)

### Problema: kubectl não conecta ao cluster

**Verificar:**
```bash
# Ver configuração
kubectl config view

# Testar conectividade
curl -k https://10.17.3.142:6443/version

# Ver status do API server
sudo systemctl status kubelet
kubectl get pods -n kube-system | grep apiserver
```

**Soluções:**
- Copiar novamente admin.conf
- Verificar certificados
- Reiniciar kubelet

### Problema: Worker não consegue join ao cluster

**Verificar:**
```bash
# No worker, ver logs do kubelet
sudo journalctl -u kubelet -f

# No control plane, gerar novo token
sudo kubeadm token create --print-join-command

# Verificar conectividade
ping 10.17.3.142
telnet 10.17.3.142 6443
```

**Soluções comuns:**
- Token expirado: Gerar novo token
- Firewall bloqueando porta 6443
- Horário dessincronizado entre nodes

### Comandos de Diagnóstico Úteis

```bash
# Ver todos os recursos
kubectl get all -A

# Ver eventos do cluster
kubectl get events -A --sort-by='.lastTimestamp'

# Ver recursos de um node
kubectl top node
kubectl describe node <node-name>

# Ver logs de componentes
kubectl logs -n kube-system <pod-name>

# Executar comando em pod
kubectl exec -it <pod-name> -- /bin/bash

# Ver configuração do kubelet
sudo cat /var/lib/kubelet/config.yaml

# Ver status do containerd
sudo systemctl status containerd
sudo crictl ps
```

---

## Referências e Documentação

### Documentação Oficial
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [containerd Documentation](https://containerd.io/docs/)
- [Flannel Documentation](https://github.com/flannel-io/flannel)

### CKA Exam Preparation
- [CNCF CKA Curriculum](https://github.com/cncf/curriculum)
- [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [Practice Exercises](https://github.com/dgkanatsios/CKAD-exercises)

### Comandos Essenciais para CKA

```bash
# Atalhos úteis
alias k=kubectl
export do="--dry-run=client -o yaml"

# Gerar manifests
kubectl run nginx --image=nginx $do > pod.yaml
kubectl create deployment nginx --image=nginx $do > deploy.yaml
kubectl expose deployment nginx --port=80 $do > service.yaml

# Edição rápida
kubectl edit deployment nginx
kubectl set image deployment/nginx nginx=nginx:1.19

# Backup e restore
kubectl get all -A -o yaml > cluster-backup.yaml
kubectl apply -f cluster-backup.yaml

# Debug
kubectl run debug --image=busybox -it --rm -- /bin/sh
kubectl debug node/worker-1 -it --image=ubuntu
```

---

## Resumo do Processo

### Ordem de Instalação

1. **Preparação** (todos os nodes):
   - Configurar hostname e /etc/hosts
   - Desabilitar swap
   - Carregar módulos do kernel
   - Configurar sysctl

2. **Instalação** (todos os nodes):
   - Instalar containerd
   - Instalar kubeadm, kubelet, kubectl

3. **Control Plane**:
   - `kubeadm init`
   - Configurar kubectl
   - Instalar CNI (Flannel)

4. **Workers**:
   - `kubeadm join` com token do control plane

5. **Verificação**:
   - `kubectl get nodes`
   - `kubectl get pods -A`
   - Testar deployments

### Portas Importantes

**Control Plane:**
- 6443: Kubernetes API server
- 2379-2380: etcd server client API
- 10250: Kubelet API
- 10259: kube-scheduler
- 10257: kube-controller-manager

**Workers:**
- 10250: Kubelet API
- 30000-32767: NodePort Services

### Arquivos Importantes

```
/etc/kubernetes/
├── manifests/              # Manifests estáticos dos componentes
├── pki/                    # Certificados
├── admin.conf              # Kubeconfig do admin
├── kubelet.conf            # Kubeconfig do kubelet
└── controller-manager.conf # Kubeconfig do controller-manager

/var/lib/kubelet/
├── config.yaml             # Configuração do kubelet
└── pods/                   # Dados dos pods

/etc/containerd/
└── config.toml             # Configuração do containerd

/var/lib/etcd/              # Dados do etcd
```

---

## Conclusão

Este cluster Kubernetes foi construído seguindo as melhores práticas do CKA. Cada componente foi instalado e configurado para trabalhar em conjunto, criando um ambiente robusto para estudos e prática.

**Próximos Passos para Estudos:**
1. Praticar deployments, services e ingress
2. Entender storage (PV, PVC, StorageClass)
3. Estudar RBAC e segurança
4. Praticar backup e restore
5. Entender troubleshooting de componentes
6. Praticar upgrades de cluster

Boa sorte nos seus estudos para o CKA! 🚀
