echo '--- start kubernetes cluster install ---'

echo '--- [1] Rocky Linux 기본 설정 ---'
echo '--- [1-1] package update ---'
yum -y update

echo '--- [1-2] timezone setting ---'
timedatectl set-timezone Asia/Seoul

echo '--- [1-3] [WARNING FileExisting-tc]: tc not found in system path 로그 관련 업데이트 ---'
yum install -y yum-utils iproute-tc

echo '--- [1-4] Hosts 등록 ---'
cat << EOF >> /etc/hosts
20.96.0.4 vm-k8s-master
20.96.0.5 vm-k8s-node-1
20.96.0.6 vm-k8s-node-2
EOF

echo '--- [2] kubeadm 설치 전 사전작업 ---'
echo '--- [2-1] 방화벽 해제 ---'
systemctl stop firewalld && systemctl disable firewalld

echo '--- [2-2] Swap 비활성화 ---'
swapoff -a && sed -i '/ swap / s/^/#/' /etc/fstab


echo '--- [3] 컨테이너 런타임 설치 전 사전작업 ---'
echo '--- [3-1] iptable 세팅 ---'
cat <<EOF |tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

cat <<EOF |tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

echo '--- [4] 컨테이너 런타임 (containerd 설치) ---'
echo '--- [4-1] containerd 패키지 설치 (option2) ---'
echo '--- [4-2] docker engine 설치 ---'
echo '--- [4-3] repo 설정 ---'
yum install -y yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

echo '--- [4-4] containerd 설치 ---'
yum install -y containerd.io-1.6.21-3.1.el8
systemctl daemon-reload
systemctl enable --now containerd

echo '--- [4-5] 컨테이너 런타임 : cri 활성화 ---'
sed -i 's/^disabled_plugins/#disabled_plugins/' /etc/containerd/config.toml
systemctl restart containerd


echo '--- [5] kubeadm 설치 ---'
echo '--- [5-1] repo 설정 ---'
cat <<EOF |tee /etc/yum.repos.d/kubernetes.repoddd
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

echo '--- [6] SELinux 설정 ---'
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

echo '--- [6-1] kubelet, kubeadm, kubectl 패키지 설치 ---'
yum install -y kubelet-1.27.2-0.x86_64 kubeadm-1.27.2-0.x86_64 kubectl-1.27.2-0.x86_64 --disableexcludes=kubernetes
systemctl enable --now kubelet


echo '--- [7] kubeadm으로 클러스터 생성 for master-node ---'

echo '--- [7-1] kubeadm으로 클러스터 생성  ---'
echo '--- [7-2] 클러스터 초기화 (Pod Network 세팅) ---'
kubeadm init --pod-network-cidr=20.96.0.0/12 --apiserver-advertise-address 20.96.0.4
kubeadm token create --print-join-command > ~/join.sh

echo '--- [7-3] kubectl 사용 설정 ---'
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

echo '--- [7-4] Pod Network 설치 (calico) ---'
kubectl create -f https://raw.githubusercontent.com/k8s-1pro/install/main/ground/k8s-1.27/calico-3.25.1/calico.yaml
kubectl create -f https://raw.githubusercontent.com/k8s-1pro/install/main/ground/k8s-1.27/calico-3.25.1/calico-custom.yaml


echo '--- [8] 쿠버네티스 편의기능 설치 ---'
echo '--- [8-1] kubectl 자동완성 기능 ---'
echo "source <(kubectl completion bash)" >> ~/.bashrc
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -o default -F __start_kubectl k' >>~/.bashrc

echo '--- [8-2] Dashboard 설치 ---'
kubectl create -f https://raw.githubusercontent.com/k8s-1pro/install/main/ground/k8s-1.27/dashboard-2.7.0/dashboard.yaml