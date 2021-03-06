#!/bin/bash
set -o xtrace

# cleanup
docker rm $(docker ps -a -q)
docker rmi $(docker images -q)
docker volume rm $(docker volume ls -qf dangling=true)

# location of kubeconfig.json
cat ./kubeconfig.json
export KUBECONFIG=$(pwd)/kubeconfig.json

# check the validity of kubeconfig.json
kubectl cluster-info
kubectl get nodes || exit

# set up govc environment variables
export GOVC_INSECURE=1
export GOVC_URL='https://Administrator@vsphere.local:Admin!23@'$VSPHERE_VCENTER'/sdk'
export USERNAME='administrator@vsphere.local'
export PASSWORD='Admin!23'

# set up local vsphere.conf for the e2e test environment
touch /tmp/vsphere.conf
echo "[Global]" > /tmp/vsphere.conf
echo '      user = "administrator@vsphere.local"' >> /tmp/vsphere.conf
echo '      password = "Admin!23"' >> /tmp/vsphere.conf
echo '      port = "443"' >> /tmp/vsphere.conf
echo '      insecure-flag = "1"' >> /tmp/vsphere.conf
echo "      datacenters = \"${VSPHERE_DATACENTER},datacenter-2\"" >> /tmp/vsphere.conf
echo "[VirtualCenter \"${VSPHERE_VCENTER}\"]" >> /tmp/vsphere.conf
echo "[Workspace]" >> /tmp/vsphere.conf
echo "      server = \"${VSPHERE_VCENTER}\"" >> /tmp/vsphere.conf
echo "      datacenter = \"${VSPHERE_DATACENTER}\"" >> /tmp/vsphere.conf
echo "      folder = \"${VSPHERE_WORKING_DIR}\"" >> /tmp/vsphere.conf
echo "      default-datastore = \"${VSPHERE_DATASTORE}\"" >> /tmp/vsphere.conf
echo "[Disk]" >> /tmp/vsphere.conf
echo "      scsicontrollertype = pvscsi" >> /tmp/vsphere.conf
echo "[Network]" >> /tmp/vsphere.conf
echo '      public-network = "VM Network"' >> /tmp/vsphere.conf
cat /tmp/vsphere.conf
export VSPHERE_CONF_FILE=/tmp/vsphere.conf  

# figure out all the cluster and host names
CLUSTER1_HOSTSET=$(govc find . -type h -datastore $(govc find -i datastore -name vsanDatastore) | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
CLUSTER2_HOSTSET=$(govc find . -type h -datastore $(govc find -i datastore -name "vsanDatastore (1)") | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")

CLUSTER1_NAME=$(govc find . -type c -datastore $(govc find -i datastore -name vsanDatastore) | sed 's/.*host\///')
CLUSTER2_NAME=$(govc find . -type c -datastore $(govc find -i datastore -name "vsanDatastore (1)") | sed 's/.*host\///')
CLUSTER3_NAME="cluster-3"

# construct array
CLUSTER1_HOSTSET=(${CLUSTER1_HOSTSET[@]})
CLUSTER2_HOSTSET=(${CLUSTER2_HOSTSET[@]})

HOST1="${CLUSTER1_HOSTSET[0]}"
HOST2="${CLUSTER1_HOSTSET[1]}"
HOST3="${CLUSTER1_HOSTSET[2]}"
HOST4="${CLUSTER2_HOSTSET[0]}"
HOST5="${CLUSTER2_HOSTSET[1]}"
HOST6="${CLUSTER2_HOSTSET[2]}"
HOST7=$(govc find /vcqaDC/host/cluster-3 -type h | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
HOST8=$(govc find . -type r | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
CLUSTER1_DATASTORE="vsanDatastore"
CLUSTER2_DATASTORE="vsanDatastore (1)"

# find local datastore for HOST7 and HOST8
arr=$(govc find -i datastore -name local-0*)
arr=(${arr[@]})
for x in "${arr[@]}"
do
	echo $x
	host=$(govc find . -type h -datastore "$x" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
	if [ "$host" == "$HOST7" ]; then
		datastorename=$(govc find . -type s -summary.datastore "$x" | sed 's/.*\///')
		echo "Matched host. Choosing datastore $datastorename"
        export HOST7_DATASTORE=$datastorename
		break;
	fi
done

for x in "${arr[@]}"
do
	echo $x
	host=$(govc find . -type h -datastore "$x" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
    host=(${host[@]})
    host="${host[0]}"
	if [ "$host" == "$HOST8" ]; then
		datastorename=$(govc find . -type s -summary.datastore "$x" | sed 's/.*\///')
		echo "Matched host. Choosing datastore $datastorename"
        export HOST8_DATASTORE=$datastorename
		break;
	fi
done

# migrate each node vm to its corresponding location
govc vm.migrate -host $HOST1 -ds "$CLUSTER1_DATASTORE" master
govc vm.migrate -host $HOST2 -ds "$CLUSTER1_DATASTORE" node1
govc vm.migrate -host $HOST3 -ds "$CLUSTER1_DATASTORE" node2
govc vm.migrate -host $HOST4 -ds "$CLUSTER2_DATASTORE" node3
govc vm.migrate -host $HOST5 -ds "$CLUSTER2_DATASTORE" node4
govc vm.migrate -host $HOST7 -ds "$HOST7_DATASTORE" node5
govc vm.migrate -host $HOST8 -ds "$HOST8_DATASTORE" node6

# retain one shared datastore acroos cluster-1 and cluster-2
# remove all other shared datastores
govc datastore.remove -ds coke $HOST7 $HOST8
govc datastore.remove -ds pepsi $HOST1 $HOST2 $HOST3 $HOST4 $HOST5 $HOST6
govc datastore.remove -ds pepsi $HOST7 $HOST8
govc datastore.remove -ds sharedVmfs-0 $HOST1 $HOST2 $HOST3 $HOST4 $HOST5 $HOST6
govc datastore.remove -ds sharedVmfs-0 $HOST7 $HOST8
govc datastore.remove -ds sharedVmfs-1 $HOST1 $HOST2 $HOST3 $HOST4 $HOST5 $HOST6
govc datastore.remove -ds sharedVmfs-1 $HOST7 $HOST8
govc datastore.remove -ds nfs0-1 $HOST1 $HOST2 $HOST3 $HOST4 $HOST5 $HOST6
govc datastore.remove -ds nfs0-1 $HOST7 $HOST8
govc datastore.remove -ds nfs0-2 $HOST1 $HOST2 $HOST3 $HOST4 $HOST5 $HOST6
govc datastore.remove -ds nfs0-2 $HOST7 $HOST8

# create new datacenter and move HOST8 under it
govc datacenter.create datacenter-2
govc cluster.create -dc=datacenter-2 cluster-1
govc host.remove -dc=vcqaDC $HOST8
govc cluster.add -dc=datacenter-2 -cluster cluster-1 -hostname $HOST8 -username root -password ca\$hc0w -noverify
govc object.rename "/datacenter-2/datastore/$HOST8_DATASTORE" localDatastore
govc object.rename "/vcqaDC/datastore/$HOST7_DATASTORE" localDatastore

# create kubernetes folder in datacenter-2 and move node6 vm under it
govc folder.create /datacenter-2/vm/kubernetes
govc object.mv "/datacenter-2/vm/Discovered virtual machine/node6" /datacenter-2/vm/kubernetes

# create zone and region tag categories
govc tags.category.create -d "Kubernetes zone" -m=true k8s-zone
govc tags.category.create -d "Kubernetes region" k8s-region
govc tags.category.ls

# create zone and region tags
govc tags.create -d "zone-a" -c "k8s-zone" zone-a
govc tags.create -d "zone-b" -c "k8s-zone" zone-b
govc tags.create -d "zone-c" -c "k8s-zone" zone-c
govc tags.create -d "zone-d" -c "k8s-zone" zone-d

govc tags.create -d "region-a" -c "k8s-region" region-a

# tag the clusters and hosts with the zones and regions
govc tags.attach zone-a "$CLUSTER1_NAME"
govc tags.attach region-a "$CLUSTER1_NAME"
govc tags.attach zone-c "/vcqaDC/host/$CLUSTER1_NAME/$HOST3"
govc tags.attach zone-b "$CLUSTER2_NAME"
govc tags.attach region-a "$CLUSTER2_NAME"
govc tags.attach zone-c "$CLUSTER3_NAME"
govc tags.attach region-a "$CLUSTER3_NAME"
govc tags.attach zone-d "/datacenter-2/host/cluster-1"
govc tags.attach region-a "/datacenter-2/host/cluster-1"

# compatible policy rule
export COMPAT_POLICY_RULE="{'VSAN.hostFailuresToTolerate':1}"
# non-compatible policy rule
export NONCOMPAT_POLICY_RULE="{'VSAN.hostFailuresToTolerate':4}"

# create two storage policies
python /root/scripts/create_policy.py -s $VSPHERE_VCENTER -u $USERNAME -r $COMPAT_POLICY_RULE -n compatpolicy -p $PASSWORD
python /root/scripts/create_policy.py -s $VSPHERE_VCENTER -u $USERNAME -r $NONCOMPAT_POLICY_RULE -n noncompatpolicy -p $PASSWORD

# configure passwordless login on all the node VM's
cd /root/scripts/ || exit
bash -x /root/scripts/configure_passwordless_login.sh

# get all node VM IP's
addresses=`kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'`
IFS=' ' read -a addressArray <<< "${addresses}"

cnt=0
# update the resourcepool-path and labels of each node VM and reboot them
for address in "${addressArray[@]}"
do
cnt=$((cnt + 1))
ssh root@$address <<EOF
if [[ "$cnt" == "1" ]]; then
sed '1d;2d;3d;4d;5d;6d;7d;8d;9d' /etc/kubernetes/vsphere.conf>/etc/kubernetes/abc.conf; mv /etc/kubernetes/abc.conf /etc/kubernetes/vsphere.conf;
echo "[Workspace]" >> /etc/kubernetes/vsphere.conf
echo "        server = \"$VSPHERE_VCENTER\"" >> /etc/kubernetes/vsphere.conf
echo "        datacenter = \"vcqaDC\"" >> /etc/kubernetes/vsphere.conf
echo "        default-datastore = \"vsanDatastore\"" >> /etc/kubernetes/vsphere.conf
echo "        folder = \"kubernetes\"" >> /etc/kubernetes/vsphere.conf
echo "[VirtualCenter \"$VSPHERE_VCENTER\"]" >> /etc/kubernetes/vsphere.conf
echo "[Global]" >> /etc/kubernetes/vsphere.conf
echo "        user = \"$USERNAME\"" >> /etc/kubernetes/vsphere.conf
echo "        password = \"$PASSWORD\"" >> /etc/kubernetes/vsphere.conf
echo "        port = \"443\"" >> /etc/kubernetes/vsphere.conf
echo "        insecure-flag = \"1\"" >> /etc/kubernetes/vsphere.conf
echo "        datacenters = \"vcqaDC,datacenter-2\"" >> /etc/kubernetes/vsphere.conf
fi
if [[ "$cnt" == "7" ]]; then
sed '1d;2d;3d;4d;5d;6d;7d;8d;9d' /etc/kubernetes/vsphere.conf>/etc/kubernetes/abc.conf; mv /etc/kubernetes/abc.conf /etc/kubernetes/vsphere.conf;
echo "[Global]" >> /etc/kubernetes/vsphere.conf
echo "        user = \"$USERNAME\"" >> /etc/kubernetes/vsphere.conf
echo "        password = \"$PASSWORD\"" >> /etc/kubernetes/vsphere.conf
echo "        server = \"$VSPHERE_VCENTER\"" >> /etc/kubernetes/vsphere.conf
echo "        port = \"443\"" >> /etc/kubernetes/vsphere.conf
echo "        insecure-flag = \"1\"" >> /etc/kubernetes/vsphere.conf
echo "        datacenter = \"datacenter-2\"" >> /etc/kubernetes/vsphere.conf
echo "        datastore = \"vsanDatastore\"" >> /etc/kubernetes/vsphere.conf
echo "        working-dir = \"kubernetes\"" >> /etc/kubernetes/vsphere.conf
fi
echo "[Labels]" >> /etc/kubernetes/vsphere.conf
echo "        zone = \"k8s-zone\"" >> /etc/kubernetes/vsphere.conf
echo "        region = \"k8s-region\"" >> /etc/kubernetes/vsphere.conf
cat /etc/kubernetes/vsphere.conf
reboot
EOF
done

# wait for all nodes to come up after reboot
export NUM_NODES=7
bash -x /root/scripts/validate-kubelet-restart.sh

# git clone the kubernetes codebase and compile
cd /mnt/workspace/
# rm -rf kubernetes/
git clone https://github.com/kubernetes/kubernetes.git
cd kubernetes
# git checkout $BRANCH_NAME
make quick-release

# executing e2e tests
export E2E_REPORT_DIR="/mnt/workspace/Run-Tests-on-Your-K8S-Cluster/${BUILD_ID}"
export KUBERNETES_CONFORMANCE_PROVIDER="vsphere"
export KUBERNETES_CONFORMANCE_TEST=Y
export VSPHERE_VCENTER_PORT=443
export VSPHERE_USER=Administrator@vsphere.local
export VSPHERE_PASSWORD='Admin!23'
export VSPHERE_INSECURE=true
export VSPHERE_VM_NAME="dummy"
export KUBE_SSH_USER="root"
export VSPHERE_KUBERNETES_CLUSTER="kubernetes"
export VOLUME_OPS_SCALE=5

# export environment variables required for zone tests
export VCP_ZONE_VSANDATASTORE1="vsanDatastore"
export VCP_ZONE_VSANDATASTORE2="vsanDatastore (1)"
export VCP_ZONE_LOCALDATASTORE="localDatastore"
export VCP_ZONE_COMPATPOLICY_NAME="compatpolicy"
export VCP_ZONE_NONCOMPATPOLICY_NAME="noncompatpolicy"
export VCP_ZONE_A="zone-a"
export VCP_ZONE_B="zone-b"
export VCP_ZONE_C="zone-c"
export VCP_ZONE_D="zone-d"
export VCP_INVALID_ZONE="invalidZone"

# specify zone testsuite
GINKGO_FOCUS[0]="Zone\sSupport"
REGEX="--ginkgo.focus="$(IFS='|' ; echo "${GINKGO_FOCUS[*]}")

# run zone test
go run hack/e2e.go --check-version-skew=false --v 9 --test --test_args="${REGEX}"

# printing kubeconfig.json and cluster status
kubectl cluster-info
kubectl get nodes