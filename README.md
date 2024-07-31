# eks-ubuntu-node
Configure a standard Ubuntu image to work with EKS control plane

Needs further testing. Run the setupnode.sh script on a stock ubuntu server, and then save as an AMI. Can use the cloud formation templates to deploy an EKS cluster, simply chose the newly created AMI as your node image. One template supports custom SLR roles for the autoscaler, if needed.
