
# setup kube repo
echo "Setting up kube stuff"
sudo apt -y install apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
# install kubelet, kubectl
sudo apt update
sudo apt -y install vim git curl wget kubelet=1.22.12-00 kubectl
sudo apt-mark hold kubelet kubectl

#disable swap
echo "disabling swap"
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo swapoff -a

# setup container runtime
echo "setup container runtime"

# using containerd
# persistent loading of modules
tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

# Set load modules
sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params
tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# restart sysctl
sysctl --system

# required packages
apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

# add docker repo
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu 
$(lsb_release -cs) stable" -y

# install and config containerd
apt update
apt install -y containerd.io
mkdir -p /etc/containerd
sudo containerd config default  /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd


# Install aws client
echo "install aws cli"
sudo apt install -y unzip curl jq
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Create EKS files
sudo mkdir /var/lib/kubelet
sudo mkdir /etc/kubernetes/kubelet
sudo mkdir /etc/eks

sudo tee /etc/kubernetes/kubelet/kube-config.json << EOF
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "address": "0.0.0.0",
  "authentication": {
    "anonymous": {
      "enabled": false
    },
    "webhook": {
      "cacheTTL": "2m0s",
      "enabled": true
    },
    "x509": {
      "clientCAFile": "/etc/kubernetes/pki/ca.crt"
    }
  },
  "authorization": {
    "mode": "Webhook",
    "webhook": {
      "cacheAuthorizedTTL": "5m0s",
      "cacheUnauthorizedTTL": "30s"
    }
  },
  "clusterDomain": "cluster.local",
  "hairpinMode": "hairpin-veth",
  "cgroupDriver": "cgroupfs",
  "cgroupRoot": "/",
  "featureGates": {
    "RotateKubeletServerCertificate": true
  },
  "serializeImagePulls": false,
  "serverTLSBootstrap": true
}
EOF

# sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/kubelet-containerd.service > /etc/eks/containerd/kubelet-containerd.service
# Instead of using the above, we are creating this file so we can add the --protect-kernel-defaults=false flag
sudo tee /etc/eks/containerd/kubelet-containerd.service << EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service sandbox-image.service
Requires=containerd.service sandbox-image.service

[Service]
ExecStartPre=/sbin/iptables -P FORWARD ACCEPT -w 5
ExecStart=/usr/bin/kubelet --cloud-provider aws \
    --config /etc/kubernetes/kubelet/kubelet-config.json \
    --kubeconfig /var/lib/kubelet/kubeconfig \
    --container-runtime remote \
    --container-runtime-endpoint unix:///run/containerd/containerd.sock \
    --protect-kernel-defaults=false \
    --network-plugin cni $KUBELET_ARGS $KUBELET_EXTRA_ARGS

Restart=on-failure
RestartForceExitStatus=SIGPIPE
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF


# EKS bootstrap files
sudo mkdir /etc/eks/containerd
sudo mkdir /etc/systemd/system/kubelet.service.d/
sudo mkdir /etc/sysconfig

sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/max-pods-calculator.sh > /etc/eks/max-pods-calculator.sh
sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/kubelet-config.json > /etc/kubernetes/kubelet/kube-config.json
sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/kubelet-kubeconfig > /var/lib/kubelet/kubeconfig
sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/eni-max-pods.txt > /etc/eks/eni-max-pods.txt
sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/bootstrap.sh > /etc/eks/bootstrap.sh
sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/sandbox-image.service > /etc/eks/containerd/sandbox-image.service
sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/containerd-config.toml > /etc/eks/containerd/containerd-config.toml
sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/pull-sandbox-image.sh > /etc/eks/containerd/pull-sandbox-image.sh
sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/kubelet-config.json > /etc/kubernetes/kubelet/kubelet-config.json
sudo curl https://raw.githubusercontent.com/awslabs/amazon-eks-ami/master/files/iptables-restore.service > /etc/eks/iptables-restore.service

# make scripts executable
sudo chmod +x /etc/eks/containerd/pull-sandbox-image.sh
sudo chmod +x /etc/eks/bootstrap.sh

# AWS IAM authenticator install
sudo curl -o aws-iam-authenticator https://s3.us-west-2.amazonaws.com/amazon-eks/1.21.2/2021-07-05/bin/linux/amd64/aws-iam-authenticator
sudo chmod +x ./aws-iam-authenticator
sudo cp ./aws-iam-authenticator /usr/bin/aws-iam-authenticator