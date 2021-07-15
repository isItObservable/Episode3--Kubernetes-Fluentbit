# Is it Observable?
<p align="center"><img src="/image/logo.png" width="40%" alt="Prometheus Logo" /></p>

## K8s and Loging with Fluentbit
<p align="center"><img src="/image/fluentbit.png" width="40%" alt="fluentbit Logo" /></p>
Repository containing the files for the Episode 3 of Is it Observable : K8s and Fluentbit


This repository showcase the usage of the Loki  by using GKE with :
- the HipsterShop


## Prerequisite
The following tools need to be install on your machine :
- jq
- kubectl
- git
- gcloud ( if you are using GKE)
- Helm
### 1.Create a Google Cloud Platform Project
```
PROJECT_ID="<your-project-id>"
gcloud services enable container.googleapis.com --project ${PROJECT_ID}
gcloud services enable monitoring.googleapis.com \
cloudtrace.googleapis.com \
clouddebugger.googleapis.com \
cloudprofiler.googleapis.com \
--project ${PROJECT_ID}
```
### 2.Create a GKE cluster
```
ZONE=us-central1-b
gcloud containr clusters create isitobservable \
--project=${PROJECT_ID} --zone=${ZONE} \
--machine-type=e2-standard-2 --num-nodes=4
```
### 3.Clone Github repo
```
git clone https://github.com/isItObservable/Episode3--Kubernetes-Fluentbit.git
cd Episode3--Kubernetes-Fluentbit
```
### 4. Deploy Prometheus
#### HipsterShop
```
cd hipstershop
./setup.sh
```
#### Prometheus ( already done during Episde 1)
```
helm install prometheus stable/prometheus-operator
```
#### Expose Grafana
```
kubectl get svc
kubectl edit svc prometheus-grafana
```
change to type NodePort
```yaml
apiVersion: v1
kind: Service
metadata:
  annotations:
    meta.helm.sh/release-name: prometheus
    meta.helm.sh/release-namespace: default
  labels:
    app.kubernetes.io/instance: prometheus
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: grafana
    app.kubernetes.io/version: 7.0.3
    helm.sh/chart: grafana-5.3.0
  name: prometheus-grafana
  namespace: default
  resourceVersion: "89873265"
  selfLink: /api/v1/namespaces/default/services/prometheus-grafana
spec:
  clusterIP: IPADRESSS
  externalTrafficPolicy: Cluster
  ports:
  - name: service
    nodePort: 30806
    port: 80
    protocol: TCP
    targetPort: 3000
  selector:
    app.kubernetes.io/instance: prometheus
    app.kubernetes.io/name: grafana
  sessionAffinity: None
  type: NodePort
status:
  loadBalancer: {}
```
Deploy the ingress by making sure to replace the service name of your grafan
```
cd ..\grafana
kubectl apply -f ingress.yaml
```
Get the login user and password of Grafana
* For the password :
```
kubectl get secret --namespace default prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```
* For the login user:
```
kubectl get secret --namespace default prometheus-grafana -o jsonpath="{.data.admin-user}" | base64 --decode
```
Get the ip adress of your Grafana
```
kubectl get ingress grafana-ingress -ojson | jq  '.status.loadBalancer.ingress[].ip'
```
#### Install Loki with Fluentbit
```
helm repo add loki https://grafana.github.io/loki/charts
helm repo update
helm upgrade --install loki loki/loki-stack --set fluent-bit.enabled=true,promtail.enabled=false
```
#### Configure Grafana 
In order to build a dashboard with data stored in Loki,we first need to add a new DataSource.
In grafana, goto Configuration/Add data source.
<p align="center"><img src="/image/addsource.PNG" width="60%" alt="grafana add datasource" /></p>
Select the source Loki , and configure the url to interact with it.

Remember Grafana is hosted in the same namesapce as Loki.
So you can simply refer the loki service :
<p align="center"><img src="/image/datasource.PNG" width="60%" alt="grafana add datasource" /></p>

#### explore the data provided by Loki in Grafana 
In grafana select Explore on the main menu
Select the datasource Loki . IN the dropdow menu select the label produc -> hipster-shop
<p align="center"><img src="/image/explore.png" width="60%" alt="grafana explore" /></p>

#### Let's build a query
Loki has a specific query langage allow you to filter, transform the data and event plot a metric from your logs in a graph.
Similar to Prometheus you need to :
* filter using labels : {app="frontend",product="hipster-shop" ,stream="stdout"}
  we are here only looking at the logs from hipster-shop , app frontend and on the logs pushed in sdout.
* transform using |
 for example :
```
{namespace="hipster-shop",stream="stdout"} | json | http_resp_took_ms >10
```
the first ```|```  specify to Grafana to use the json parser that will extract all the json properties as labels.
the second ```|``` will filter the logs on the new labels created by the json parser.
In this example we want to only get the logs where the attribute http.resp.took.ms is above 10ms ( the json parser is replace . by _)

We can then extract on field to plot it using all the various [functions available in Grafana](https://grafana.com/docs/loki/latest/logql/)

if i want to plot the response time over time i could use the function :
```
rate({namespace="hipster-shop" } |="stdout" !="error" |= "debug" |="http.resp.took_ms" [30s])  
```

### Let's install Fluentbit to go trough the configuration
Now that we have used the default configuration with Loki , let's deploy the standard Fluentbit
and explore the settings.

#### Installation of Fluentbit
```
helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit
```

#### Let's jump into fluentbit configuration file

The configuration file is stored in a ConfigMap
```
kubectl get cm
```
<p align="center"><img src="/image/getcm.png" width="60%" alt="grafana explore" /></p>

```yaml
[SERVICE]
        Flush 1
        Daemon Off
        Log_Level info
        Parsers_File parsers.conf
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port 2020

    [INPUT]
        Name tail
        Path /var/log/containers/*.log
        Parser docker
        Tag kube.*
        Mem_Buf_Limit 5MB
        Skip_Long_Lines On

    [INPUT]
        Name systemd
        Tag host.*
        Systemd_Filter _SYSTEMD_UNIT=kubelet.service
        Read_From_Tail On*

    
```

Now that we have the default configuration to collect logs of our Pods
Let's see how to filter and change the log stream 

#### Let's start by filtering Kubernetes metrics 
Let's add Filter block in our current Fluentbit pipeline

```
 [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Merge_Log_Trim On
        Labels Off
        Annotations Off
        K8S-Logging.Parser Off
        K8S-Logging.Exclude Off
```
And a output plugin to see the transformed log in Stdout ( of our fluentbit pods)
```
    [OUTPUT]
        Name stdout
        Match *
        Format json
        Json_date_key timestamp
        Json_date_format iso8601
```

#### Now let's transform our log stream to be able to send it to Dynatrace log ingest API

#### Requierements
If you don't have any dynatrace tenant , then let's start a [trial on Dynatrace](https://www.dynatrace.com/trial/) 
Setup the Dynatrace K8s operator following the steps describe in the [documentation](https://www.dynatrace.com/support/help/technology-support/container-platforms/kubernetes/monitor-kubernetes-environments/) 

In order to collect logs in Dynatrace, you will also need to install the Active Gate.*
Follow the documentation to [install the Active Gate on a seperate server](https://www.dynatrace.com/support/help/setup-and-configuration/dynatrace-activegate/)

#### Configuration of Fluentbit
Now need need to rename the log into content , and rename the kubernetes information with the right fields.
```
[FILTER]
    Name modify
    Match *
    Rename log content
```

Let's use the nest filter plugin to move the kubernetes tags
```
[FILTER]
    Name nest
    Match kube.*
    Operation lift
    Nested_under kubernetes
    Add_prefix   kubernetes_
```
Let's use modify plugin to rename and remove the non relevant tags
```
[FILTER]
    Name modify
    Match kube.*
    Rename log content
    Rename kubernetes_pod_name k8s.pod.name
    Rename kubernetes_namespace_name k8s.namespace.name
    Remove kubernetes_container_image
    Remove kubernetes_docker_id
    Remove kubernetes_container_name
    Remove kubernetes_pod_id
    Remove kubernetes_host
    Remove time
    Remove kubernetes_container_hash
    Add k8s.cluster.name Onlineboutique
```

The Dynatrace ingest API is limiting the number of calls per minute. 
We need to throttle the streams :
```
[FILTER]
    Name     throttle
    Match    *
    Rate     100
    Window   100
    Interval 1m
```

Last we can now connect the dynatrace API using the http output plugin
```
 [OUTPUT]
    Name http
    Match *
    host YOURHOST
    port 9999
    URI /e/<DYNATRACE TENANT ID>/api/v2/logs/ingest
    header Authorization Api-Token <DYNATRACE API TOKEN>
    header Content-Type application/json
    Format json
    Json_date_key timestamp
    Json_date_format iso8601
    tls On
    tls.verify Off
```

Let's open go to [calyptia](https://cloud.calyptia.com/) to visualize our log stream pipeline:
<p align="center"><img src="/image/log_stream_pipeline.PNG" width="60%" alt="grafana explore" /></p>
