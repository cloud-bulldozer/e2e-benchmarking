# Workload scripts

### Note: 
Make sure to enable one of the below authentication methods to the openshift cluster before running any of the workload scripts. 

**1) Authenticate using the kubeconfig file** 
This can be done by setting the KUBECONFIG env var, with the absolute path to the location of the kubeconfig file. Default: ~/.kube/config 

**2) Authenticate using a virtual user for oc login**
This can be done by setting 3 env vars which will be consumed by the oc login command. 
* KUBEUSER - Any user who has cluster administrator privileges. Default: kubeadmin
* KUBEPASSWORD - Password for the above user.
* KUBEURL - The openshift server URL for your cluster.
