#!/bin/bash
kubeconfig_path=''
function unkown_option() {
echo -e "\nUnknown K8S node type: $1 \n"; 
}

# Check if the machine Linux and Distor is Ubuntu or RHEL(RedHat)
UNAME=$(uname | tr "[:upper:]" "[:lower:]")
# If Linux, try to determine specific distribution
if [ "$UNAME" == "linux" ]; then
    # If available, use LSB to identify distribution
    if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
        kubeconfig_path='/home/ubuntu' 
    elif [[ -f /etc/redhat-release ]]; then
        kubeconfig_path='/home/ec2-user'
    else 
        echo -e "   Linux is not either Ubuntu nor RHEL.... \n"; 
        unkown_option
        exit 1; 
    fi  
else 
    echo -e "    Not a Linux platform ... \n"; 
    unkown_option
    exit 1; 
fi

[[ "$1" == "--help" || "$1" == "help" || "$1" == "-h" ]] && { unkown_option; exit 0;}

if [[ "$1" == 'master' ]]; then 
echo -e "\n--------- K8S Master node setup ------------"
elif [[ "$1" == 'worker' ]]; then 
echo -e "\n--------- K8S Worker node setup ------------"
else 
unkown_option $1
exit 1
fi

sudo apt update
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
echo -e "\n---------- APT transport for downloading pkgs via HTTPS -------\n"
sudo apt-get update
sudo apt-get install -y gnupg2 gpg software-properties-common apt-transport-https ca-certificates curl 

echo -e "\n---------- Enable the Docker repository ----------\n"
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"


sudo su - <<EOF
echo -e "\n---------------- Install container.io ---------\n"
apt update
apt install -y containerd.io
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
systemctl stop containerd
systemctl start containerd
systemctl enable containerd
EOF

sudo su - <<EOF
echo -e "\n------------  Add K8S packgaes to APT list ---------\n"
[[ -d "/etc/apt/keyrings" ]] || mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
EOF


echo -e "\n---------- Install kubeadm, kubelet, kubectl and kubernetes-cni -------------\n"
sudo apt update -y
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo -e "\n--------------- Install extended tool for k8s - stern, kubetcx ---------------\n"
curl -s -Lo /tmp/stern.tar.gz https://github.com/stern/stern/releases/download/v1.24.0/stern_1.24.0_linux_amd64.tar.gz
tar -xvzf /tmp/stern.tar.gz -C /tmp
sudo mv /tmp/stern /usr/local/bin/
sudo apt install -y kubectx


if [[ "$1" == 'master' ]]; then 
echo -e "\n--------- Initiating kubeadm control-plane (master node) ----------\n"
sudo su - <<EOF
kubeadm init
EOF

echo -e "\n-------------- Set-up Kubectl config  -----------\n"
sleep 4
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config 
sudo chown $(id -u):$(id -g) $HOME/.kube/config
[[ -f "$HOME/.kube/config" ]] || echo "     Kubeconfig copied $HOME/.kube/config"

echo -e "\n --------- Install networking and network policy plugin ----------\n"
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml 

echo -e "\n--------------- Check mater node status -----------------\n"
kubectl get nodes
echo -e "\n Waiting for control-plane (master node) to get Ready \n"
sleep 15
kubectl get nodes
echo -e "\n\n  Wait to for 5-10 minutes, if node is still not in Ready state then try to install below calico network cni "
echo "    1. kubectl apply -f https://docs.projectcalico.org/manifests/calico-typha.yaml"
echo "    2. kubectl get nodes"
echo -e "\n-----------------------------------------------------------------------------------"

fi  

echo -e "\n------ Copy the join <token> command ----------\n" 
echo "    The join command must be executed in the worker node that we intend to add to the control-plane."
echo "    we can generate it using bellow command:"  
echo "    kubeadm token create --print-join-command"
echo -e "\n-----------------------------------------\n"
