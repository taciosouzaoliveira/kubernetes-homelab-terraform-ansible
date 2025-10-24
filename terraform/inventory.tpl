[controlplane]
${controlplane_ip}

[workers]
%{ for ip in worker_ips ~}
${ip}
%{ endfor ~}

[k8s_cluster:children]
controlplane
workers

[all:vars]
ansible_user=ubuntu
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
