# Boundary Install Script
Current works for workers only. WIP to add controller logic soon!

```
Download and Install a Boundary worker - Latest Version unless '-i' specified

usage: install-worker.sh [-i VERSION] [-a] [-c] [-h] [-v] [unique-name] [controller-ip] [worker-ip]

example: install-worker.sh -i 0.7.1 my-worker 53.75.200.120 24.253.12.12

 Flags
     -i VERSION : specify version to install in format '0.8.0' (OPTIONAL)
     -a         : automatically use sudo to install to /usr/local/bin
     -c         : leave binary in working directory (for CI/DevOps use)
     -h         : help
     -v         : display install-worker.sh version

 Arguments
     unique-name        : a unique name for your worker configuration
     controller-ip      : the IP address for your worker to reach your controller
     worker-ip  : the IP address for your clients to reach your worker
```
