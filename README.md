# Cluster Kubernetes para Estudo CKA

Cluster Kubernetes com 1 control plane e 2 workers provisionado com Terraform e configurado com Ansible.

<p>
  <img src="Terraform cluster.png" alt="Terraform Cluster" width="500"/>
</p>

## Informações do Cluster

- **Control Plane**: 10.17.3.142 (hostname: controlplane)
- **Worker 1**: 10.17.3.51 (hostname: worker-1)
- **Worker 2**: 10.17.3.124 (hostname: worker-2)
- **Versão Kubernetes**: v1.28.15
- **CNI**: Flannel
- **Container Runtime**: containerd

## Estrutura do Projeto

```
.
├── terraform/
│   ├── main.tf           # Configuração principal do Terraform
│   ├── outputs.tf        # Outputs do Terraform
│   ├── cloud-init.yaml   # Configuração cloud-init para VMs
│   └── inventory.tpl     # Template do inventário Ansible
└── ansible/
    ├── playbook.yml      # Playbook de configuração do K8s
    ├── ansible.cfg       # Configuração do Ansible
    └── inventory.ini     # Inventário gerado automaticamente
```

## Como Usar

### Provisionar a Infraestrutura

```bash
cd terraform
terraform init
terraform apply -auto-approve
```

### Configurar o Cluster Kubernetes

Aguarde ~2 minutos após o `terraform apply` para o cloud-init concluir, então:

```bash
cd ../ansible
ansible-playbook playbook.yml
```

### Acessar o Control Plane

```bash
ssh ubuntu@10.17.3.142
```

### Verificar o Cluster

```bash
ssh ubuntu@10.17.3.142 'kubectl get nodes -o wide'
ssh ubuntu@10.17.3.142 'kubectl get pods -A'
```

### Destruir o Cluster

```bash
cd terraform
terraform destroy -auto-approve
```

## Comandos Úteis para Estudo CKA

### Verificar componentes do cluster
```bash
kubectl get nodes
kubectl get pods -A
kubectl get componentstatuses
```

### Verificar certificados
```bash
sudo kubeadm certs check-expiration
```

### Fazer backup do etcd
```bash
sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup.db
```

### Criar recursos
```bash
kubectl run nginx --image=nginx
kubectl create deployment nginx --image=nginx --replicas=3
kubectl expose deployment nginx --port=80 --type=NodePort
```

### Escalar deployments
```bash
kubectl scale deployment nginx --replicas=5
```

### Ver logs
```bash
kubectl logs -f <pod-name>
kubectl logs <pod-name> -c <container-name>
```

### Debug
```bash
kubectl describe pod <pod-name>
kubectl exec -it <pod-name> -- /bin/bash
```

## Recursos

- [Documentação Oficial Kubernetes](https://kubernetes.io/docs/)
- [CKA Exam Curriculum](https://github.com/cncf/curriculum)
- [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)

## Credenciais

- **Usuário SSH**: ubuntu
- **Senha SSH**: ubuntu
- **Chave SSH**: Configurada no cloud-init.yaml
