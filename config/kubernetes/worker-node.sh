echo '======== [4] Rocky Linux 기본 설정 ========'
echo '======== [4-1] 패키지 업데이트 ========'
yum -y update

echo '======== [4-2] 타임존 설정 ========'
timedatectl set-timezone Asia/Seoul

echo '======== [4-3] Disk 확장 / Bug: soft lockup 설정 추가========'
# https://cafe.naver.com/kubeops/25
yum install -y cloud-utils-growpart
growpart /dev/sda 4
xfs_growfs /dev/sda4
echo 0 > /proc/sys/kernel/hung_task_timeout_secs
echo "kernel.watchdog_thresh = 20" >> /etc/sysctl.conf

echo '======== [4-4] [WARNING FileExisting-tc]: tc not found in system path 로그 관련 업데이트 ========'
yum install -y yum-utils iproute-tc

echo '======== [4-5] Hosts 등록 ========'
cat << EOF >> /etc/hosts
192.168.4.4 vm-k8s-master
192.168.4.5 vm-k8s-node-1
192.168.4.6 vm-k8s-node-2
EOF

echo '======== [5] kubeadm 설치 전 사전작업 ========'
echo '======== [5] 방화벽 해제 ========'
systemctl stop firewalld && systemctl disable firewalld

echo '======== [5] Swap 비활성화 ========'
swapoff -a && sed -i '/ swap / s/^/#/' /etc/fstab


echo '======== [6] 컨테이너 런타임 설치 ========'
echo '======== [6-1] 컨테이너 런타임 설치 전 사전작업 ========'
echo '======== [6-1] iptable 세팅 ========'
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

echo '======== [6-2] 컨테이너 런타임 (containerd 설치) ========'
echo '======== [6-2-1] containerd 패키지 설치 (option2) ========'
echo '======== [6-2-1-1] docker engine 설치 ========'
echo '======== [6-2-1-1] repo 설정 ========'
yum install -y yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

echo '======== [6-2-1-1] containerd 설치 ========'
yum install -y containerd.io-1.6.21-3.1.el8
systemctl daemon-reload
systemctl enable --now containerd

echo '======== [6-3] 컨테이너 런타임 : cri 활성화 ========'
sed -i 's/^disabled_plugins/#disabled_plugins/' /etc/containerd/config.toml
systemctl restart containerd


echo '======== [7] kubeadm 설치 ========'
echo '======== [7] repo 설정 ========'
cat <<EOF |tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

echo '======== [7] SELinux 설정 ========'
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

echo '======== [7] kubelet, kubeadm, kubectl 패키지 설치 ========'
yum install -y kubelet-1.27.2-0.x86_64 kubeadm-1.27.2-0.x86_64 kubectl-1.27.2-0.x86_64 --disableexcludes=kubernetes
systemctl enable --now kubelet

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/kubelet.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config