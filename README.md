# OpenTelemetry Target Allocator Example

This is the companion repo for the KubeCon EU 2024 Talk, ["Prometheus and OpenTelemetry: Better Together"](https://kccnceu2024.sched.com/event/1YePz/prometheus-and-opentelemetry-better-together-adriana-villela-servicenow-cloud-observability-reese-lee-new-relic).

See the slides [here](https://drive.google.com/file/d/1iGZJrxq5SomDou1A2DS871_y7IzV4MIC/view?usp=sharing).

Watch the talk [here](https://youtu.be/LJd1pJ0k28g?si=Z9nTsr3dZu3fbakx).

In this example, we will:

1. Install [KinD (KUbernetes in Docker)](https://kind.sigs.k8s.io)
2. Install the `ServiceMonitor` and `PodMonitor` Prometheus CRs
3. Install the OTel Operator
4. Deploy 3 Python services:
   - The Python [Client](./src/python/client.py) and [Server](./src/python/server.py) services are instrumented using OpenTelemetry, using a combination of both auto-instrumentation via the OTel Operator, and manual instrumentation
   - The [Prometheus app](./src/python/app.py) emits Prometheus metrics which are picked up by the [`ServiceMonitor`](./src/resources/04-service-monitor.yml) CR and are added to the [Prometheus Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/prometheusreceiver/README.md)'s scrape config via the [OTel Operator's Target Allocator](https://github.com/open-telemetry/opentelemetry-operator/tree/main/cmd/otel-allocator).

The Target Allocator configuration and sample [Python Prometheus app](./src/python/app.py) are based on [this tutorial](https://trstringer.com/opentelemetry-prometheus-metrics/).

## Installation

This project can be run using GitHub Codespaces. To learn how, [check out this video](https://youtu.be/dRbUKhBtMg4).

### 1- Install KinD and set up k8s cluster

The scripts below will install KinD, and then will install the following in the newly-created cluster:

- the `PodMonitor` and `ServiceMonitor` Prometheus CRs
- `cert-manager` (an OTel Operator pre-requisite)
- the OTel Operator.

```bash
./src/scripts/01-install-kind.sh
./src/scripts/02-k8s-setup.sh
```

### 2- Build and deploy image

Build Docker image and deploy to KinD

```bash
./src/scripts/03-build-and-deploy-images.sh
```

Verify that images are in KinD:

```bash
docker exec -it otel-target-allocator-talk-control-plane crictl images | grep target-allocator
```

Reference [here](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster).

## 3a - Kubernetes Deployment (Collector stdout only)

> 🚨 This step deploys resources to send telemetry to the OTel Collector's sdout only. If you want to send telemetry to [ServiceNow Cloud Observability (formerly known as Lightstep)](https://www.servicenow.com/products/observability.html), you'll need to skip this step and follow [Step 3b](#3b--kubernetes-deployment-servicenow-cloud-observability-backend) instead.

Now you are ready to deploy the Kubernetes resources

```bash
./src/scripts/04-deploy-resources.sh
```

### 3b- Kubernetes deployment (ServiceNow Cloud Observability backend)

> 🚨 If you want to send telemetry to [ServiceNow Cloud Observability (formerly known as Lightstep)](https://www.servicenow.com/products/observability.html), you'll need to follow the steps below, and skip [Step 3a](#3a---kubernetes-deployment-collector-stdout-only).

To send telemetry to ServiceNow Cloud Observability, you will first need a Cloud Observability account. You will also need to obtain an [access token](https://docs.lightstep.com/docs/create-and-manage-access-tokens#create-an-access-token).

We're going to store the access token in a Kubernetes secret, and will map the secret to an environment variabe in the [`OpenTelemetryCollector CR`](https://github.com/avillela/otel-target-allocator-talk/blob/a2763917142957f8f6e32d137e35a6d0e4ea4f55/src/resources/02-otel-collector-ls.yml#L17-L21).

First, create a secrets file for the Lightstep token.

```bash
tee -a src/resources/00-secret.yaml <<EOF
 apiVersion: v1
 kind: Secret
 metadata:
   name: otel-collector-secret
   namespace: opentelemetry
 data:
   LS_TOKEN: <base64-encoded-LS-token>
 type: "Opaque"
EOF
```

Replace <base64-encoded-LS-token> with your own [access token] (https://docs.lightstep.com/docs/create-and-manage-access-tokens#create-an-access-token)

Be sure to Base64 encode it like this:

```bash
echo <LS-access-token> | base64
```

Or you can Base64-encode it through [this website](https://www.base64encode.org/).

Finally, deploy the Kubernetes resources:

```bash
./src/scripts/04-deploy-resources-ls-backend.sh
```

## 4- Check logs

This command will tail the Collector logs

```bash
kubectl logs -l app.kubernetes.io/component=opentelemetry-collector -n opentelemetry --follow
```

This command will return unique items from the Collector logs containing "Name:"

```bash
kubectl logs otelcol-collector-0 -n opentelemetry | grep "Name:" | sort | uniq
```

Check Target Allocator logs:

```bash
kubectl logs -l app.kubernetes.io/component=opentelemetry-targetallocator -n opentelemetry --follow
```

## Troubleshooting

Based on [this article](https://trstringer.com/opentelemetry-target-allocator-troubleshooting/)

Expose target allocator port

```bash
kubectl port-forward svc/otelcol-targetallocator -n opentelemetry 8080:80
```

So we can get list of jobs

```bash
curl localhost:8080/jobs | jq
```

Sample output:

```json
{
  "serviceMonitor/opentelemetry/sm-example/2": {
    "_link": "/jobs/serviceMonitor%2Fopentelemetry%2Fsm-example%2F2/targets"
  },
  "serviceMonitor/opentelemetry/sm-example/0": {
    "_link": "/jobs/serviceMonitor%2Fopentelemetry%2Fsm-example%2F0/targets"
  },
  "serviceMonitor/opentelemetry/sm-example/1": {
    "_link": "/jobs/serviceMonitor%2Fopentelemetry%2Fsm-example%2F1/targets"
  },
  "otel-collector": {
    "_link": "/jobs/otel-collector/targets"
  }
}
```

Peek into one of the jobs:

```bash
curl localhost:8080/jobs/serviceMonitor%2Fopentelemetry%2Fmy-app%2F1/targets | jq
```

Sample output:

```json
{
  "otelcol-collector-0": {
    "_link": "/jobs/serviceMonitor%2Fopentelemetry%2Fmy-app%2F1/targets?collector_id=otelcol-collector-0",
    "targets": [
      {
        "targets": ["10.244.0.29:8082"],
        "labels": {
          "__meta_kubernetes_endpointslice_annotation_endpoints_kubernetes_io_last_change_trigger_time": "2024-02-28T18:09:34Z",
          "__meta_kubernetes_endpointslice_labelpresent_app_kubernetes_io_name": "true",
          "__meta_kubernetes_endpointslice_endpoint_conditions_serving": "true",
          "__meta_kubernetes_endpointslice_labelpresent_endpointslice_kubernetes_io_managed_by": "true",
          "__meta_kubernetes_service_labelpresent_app": "true",
          "__meta_kubernetes_pod_label_pod_template_hash": "f89fdbc4f",
          "__meta_kubernetes_endpointslice_endpoint_conditions_terminating": "false",
          "__meta_kubernetes_pod_label_app": "my-app",
          "__meta_kubernetes_pod_ip": "10.244.0.29",
          "__meta_kubernetes_pod_container_image": "otel-target-allocator-talk:0.1.0-py-otel-server",
          "__meta_kubernetes_endpointslice_address_type": "IPv4",
          "__meta_kubernetes_service_annotation_kubectl_kubernetes_io_last_applied_configuration": "{\"apiVersion\":\"v1\",\"kind\":\"Service\",\"metadata\":{\"annotations\":{},\"labels\":{\"app\":\"my-app\",\"app.kubernetes.io/name\":\"py-otel-server\"},\"name\":\"py-otel-server-svc\",\"namespace\":\"opentelemetry\"},\"spec\":{\"ports\":[{\"name\":\"py-server-port\",\"port\":8082,\"protocol\":\"TCP\",\"targetPort\":\"py-server-port\"}],\"selector\":{\"app.kubernetes.io/name\":\"py-otel-server\"}}}\n",
          "__meta_kubernetes_endpointslice_annotationpresent_endpoints_kubernetes_io_last_change_trigger_time": "true",
          "__meta_kubernetes_pod_container_port_number": "8082",
          "__meta_kubernetes_pod_uid": "06cc65c5-61a2-4d0c-87ef-74302f977d48",
          "__meta_kubernetes_endpointslice_labelpresent_kubernetes_io_service_name": "true",
          "__meta_kubernetes_endpointslice_label_endpointslice_kubernetes_io_managed_by": "endpointslice-controller.k8s.io",
          "__meta_kubernetes_service_name": "py-otel-server-svc",
          "__meta_kubernetes_endpointslice_endpoint_conditions_ready": "true",
          "__meta_kubernetes_endpointslice_address_target_kind": "Pod",
          "__meta_kubernetes_pod_annotation_instrumentation_opentelemetry_io_inject_python": "true",
          "__meta_kubernetes_pod_container_port_name": "py-server-port",
          "__meta_kubernetes_endpointslice_address_target_name": "py-otel-server-f89fdbc4f-lbb7z",
          "__meta_kubernetes_endpointslice_labelpresent_app": "true",
          "__meta_kubernetes_pod_host_ip": "172.24.0.2",
          "__meta_kubernetes_pod_container_name": "py-otel-server",
          "__meta_kubernetes_namespace": "opentelemetry",
          "__meta_kubernetes_endpointslice_label_kubernetes_io_service_name": "py-otel-server-svc",
          "__meta_kubernetes_pod_controller_name": "py-otel-server-f89fdbc4f",
          "__meta_kubernetes_pod_labelpresent_app_kubernetes_io_name": "true",
          "__meta_kubernetes_service_label_app_kubernetes_io_name": "py-otel-server",
          "__meta_kubernetes_pod_node_name": "otel-target-allocator-talk-control-plane",
          "__meta_kubernetes_pod_labelpresent_pod_template_hash": "true",
          "__address__": "10.244.0.29:8082",
          "__meta_kubernetes_service_labelpresent_app_kubernetes_io_name": "true",
          "__meta_kubernetes_pod_label_app_kubernetes_io_name": "py-otel-server",
          "__meta_kubernetes_pod_container_port_protocol": "TCP",
          "__meta_kubernetes_pod_labelpresent_app": "true",
          "__meta_kubernetes_pod_annotationpresent_instrumentation_opentelemetry_io_inject_python": "true",
          "__meta_kubernetes_endpointslice_port": "8082",
          "__meta_kubernetes_pod_phase": "Running",
          "__meta_kubernetes_endpointslice_name": "py-otel-server-svc-t2wgv",
          "__meta_kubernetes_endpointslice_label_app_kubernetes_io_name": "py-otel-server",
          "__meta_kubernetes_endpointslice_port_protocol": "TCP",
          "__meta_kubernetes_service_annotationpresent_kubectl_kubernetes_io_last_applied_configuration": "true",
          "__meta_kubernetes_pod_ready": "true",
          "__meta_kubernetes_pod_controller_kind": "ReplicaSet",
          "__meta_kubernetes_pod_name": "py-otel-server-f89fdbc4f-lbb7z",
          "__meta_kubernetes_service_label_app": "my-app",
          "__meta_kubernetes_endpointslice_port_name": "py-server-port",
          "__meta_kubernetes_endpointslice_label_app": "my-app"
        }
      }
    ]
  }
}
```

# Notes

https://wiki.ravianand.me/
https://academy.portainer.io/deploy/kubernetes/#/
https://hub.docker.com/r/portainer/dev-toolkit
https://docs.portainer.io/start/install-ce/server/docker/linux
https://www.portainer.io/blog/using-vscode-with-portainer-managed-kubernetes-clusters
https://yashsrivastav.hashnode.dev/getting-started-with-portainer-using-kind
https://opentelemetry.io/docs/specs/otel/metrics/
https://trstringer.com/otel-part1-intro/
https://github.com/trstringer/otel-shopping-cart
https://trstringer.com/openetelemetry-sample-application/

https://www.baeldung.com/ops/kubernetes
https://www.baeldung.com/ops/kubernetes-helm
https://www.baeldung.com/ops/docker-compose-vs-kubernetes
https://www.baeldung.com/ops/k3s-getting-started
https://www.baeldung.com/ops/microk8s-introduction
https://www.baeldung.com/ops/kubernetes-pod-lifecycle
https://www.baeldung.com/ops/kubevirt-kubernetes-addon-guide
https://www.baeldung.com/ops/prometheus-cpu-memory-kubernetes
https://www.baeldung.com/ops/kubernetes-series
https://www.baeldung.com/ops/kubectl-ls-alternatives
https://www.baeldung.com/ops/kubectl-output-format
https://www.baeldung.com/ops/delete-namespace-terminating-state
https://www.baeldung.com/ops/kubernetes-pods-scaling

https://www.baeldung.com/ops/docker-guide
https://www.baeldung.com/ops/podman-execute-docker-container
https://www.baeldung.com/linux/ssh-check-remote-file-exists

# Example of how to use devcontainers with nix/direnv

https://github.com/importantimport/hatsu/blob/c4c30551c48c42a173fc1584ac5a3ef228166e4c/.devcontainer/devcontainer.json#L5
https://github.com/otomadb/devlog/blob/7a4d1395731086b07410f1f3bec78792e1602f12/.devcontainer/.devcontainer.json#L8

# Aside for when we create the control plane:

To start using your cluster, you need to run the following as a regular user:

mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Alternatively, if you are the root user, you can run:

export KUBECONFIG=/etc/kubernetes/admin.conf

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of control-plane nodes by copying certificate authorities
and service account keys on each node and then running the following as root:

kubeadm join otel-target-allocator-talk-control-plane:6443 --token <value withheld> \
 --discovery-token-ca-cert-hash sha256:e83378ed6aa7fbee52ba8bd75b20da6bdad0af0ea301b05a26a53fe6b3b0ef48 \
 --control-plane

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join otel-target-allocator-talk-control-plane:6443 --token <value withheld> \
 --discovery-token-ca-cert-hash sha256:e83378ed6aa7fbee52ba8bd75b20da6bdad0af0ea301b05a26a53fe6b3b0ef48
I1102 16:59:18.220030 216 loader.go:395] Config loaded from file: /etc/kubernetes/admin.conf

## SNIP

Set kubectl context to "kind-otel-target-allocator-talk"
You can now use your cluster with:

kubectl cluster-info --context kind-otel-target-allocator-talk

# End control plane creation

# We can try to view the pods via k9s like this?

sudo -E $(which nix) run nixpkgs#k9s -- -A

# End k9s as root

https://kubernetes.io/docs/setup/
https://kubernetes.io/docs/tasks/tools/
https://k0sproject.io/
https://www.blueshoe.io/blog/minikube-vs-k3d-vs-kind-vs-getdeck-beiboot/
https://github.com/gefyrahq/gefyra
https://kubernetes.io/docs/tasks/debug/

# How to stop a pod(s) associated with a namespace

kubectl --context kind-otel-target-allocator-talk get pods --namespace k8s-metrics  
NAME READY STATUS RESTARTS AGE
kube-otel-stack-kube-state-metrics-5b84b9cd55-5jfwh 1/1 Running 0 139m
kube-otel-stack-metrics-collector-0 0/1 CreateContainerConfigError 0 62m
kube-otel-stack-metrics-collector-1 0/1 CreateContainerConfigError 0 62m
kube-otel-stack-metrics-collector-2 0/1 CreateContainerConfigError 0 139m
kube-otel-stack-metrics-targetallocator-6f8d59c548-mm9rn 1/1 Running 0 139m
kube-otel-stack-metrics-targetallocator-6f8d59c548-rdfcj 1/1 Running 0 139m
kube-otel-stack-prometheus-node-exporter-hbz85 1/1 Running 0 139m

# Kill them all in one fell swoop

kubectl --context kind-otel-target-allocator-talk delete deployment/kube-otel-stack-kube-state-metrics --namespace k8s-metrics

# Uh... we still have stuff getting rebuilt!

kubectl --context kind-otel-target-allocator-talk delete pod --all --namespace k8s-metrics

# Ok this actually scaled it down:

kubectl --context kind-otel-target-allocator-talk scale deployments kube-otel-stack-metrics-targetallocator --replicas=0 --namespace k8s-metrics

# We tried this... let's see

kubectl --context kind-otel-target-allocator-talk delete deployment.apps/kube-otel-stack-metrics-targetallocator --namespace k8s-metrics

# OK - only deleting the namespace was the most effective way to shutdown all these pods

kubectl --context kind-otel-target-allocator-talk delete namespace k8s-metrics

kubectl --context kind-otel-target-allocator-talk delete namespace opentelemetry

# Links for interacting with kubectl

https://www.baeldung.com/ops/kubernetes-stop-pause
https://www.baeldung.com/ops/kubernetes-switch-namespaces
https://www.baeldung.com/ops/kubernetes-list-all-resources
https://www.baeldung.com/ops/kubernetes-pods-scaling
https://www.baeldung.com/ops/kubernetes-list-every-pod-node
https://www.baeldung.com/ops/delete-namespace-terminating-state

# List all the stuff in a namespace

kubectl api-resources --verbs=list --namespaced=true -o name \
| xargs -n 1 kubectl get --ignore-not-found --show-kind -n k8s-metrics

# Context Prefix: kubectl --context kind-otel-target-allocator-talk

# More articles:

https://www.baeldung.com/ops/kubernetes-nodeport-range
https://www.baeldung.com/ops/kubernetes-restart-container-pod
https://www.baeldung.com/ops/kubernetes-ingress-empty-address
https://www.baeldung.com/ops/kubernetes-timeout-issue-port-forwarding
https://www.baeldung.com/ops/kubernetes-list-recently-deleted-pods
https://www.baeldung.com/ops/kubernetes-endpoints
https://www.baeldung.com/ops/k9s-kubernetes-cluster-management
https://www.baeldung.com/ops/kubernetes-error-no-route-to-host
https://www.baeldung.com/ops/kubernetes-retrieve-ingress-endpoint-ip-address
https://www.baeldung.com/ops/kubectl-error-connection-to-server-was-refused
https://www.baeldung.com/ops/kubernetes-pod-communication

https://uptrace.dev/opentelemetry/python-tracing.html#quickstart
https://www.cncf.io/blog/2022/04/22/opentelemetry-and-python-a-complete-instrumentation-guide/
https://intellitect.com/blog/opentelemetry-metrics-python/
https://github.com/joeriddles/python-otel-demo/
https://www.cncf.io/blog/2022/07/29/prometheus-vs-opentelemetry-metrics-a-complete-guide/
https://coralogix.com/docs/opentelemetry/instrumentation-options/python-opentelemetry-instrumentation/#support
https://www.elastic.co/observability-labs/blog/auto-instrumentation-python-applications-opentelemetry
https://www.cncf.io/wp-content/uploads/2020/12/Hacking-Monitoring-CNCF-Sarah-Conway.pdf

# Let's have a look at these tutorials

https://opentelemetry-python-kinvolk.readthedocs.io/en/latest/getting-started.
https://github.com/open-telemetry/opentelemetry-demo
https://github.com/open-telemetry/opentelemetry-ebpf-profiler
https://github.com/open-telemetry/opentelemetry-python

https://opentelemetry.io/docs/languages/python/getting-started/
https://www.infracloud.io/blogs/opentelemetry-auto-instrumentation-jaeger/
https://opentelemetry.io/docs/languages/python/exporters/
https://opentelemetry-python.readthedocs.io/en/stable/exporter/jaeger/jaeger.html#opentelemetry-jaeger-thrift-exporter