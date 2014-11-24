# Fluentd Docker Metrics Input Plugin

This is a [Fluentd](http://www.fluentd.org) plugin to collect Docker metrics periodically.

## How it works

It's assumed to run on the host server. It periodically runs Docker Remote API calls to fetch container IDs and looks at `/sys/fs/cgroups/<metric_type>/docker/<container_id>/`
for relevant stats. You can say this is an implementation of the metric collection strategy outlined in [this blog post](http://blog.docker.com/2013/10/gathering-lxc-docker-containers-metrics/).

## Installing

to be uploaded on Rubygems

## Example config

```
<source>
  type docker_metrics
  stats_interval 1m
</source>
```

## Parameters

* **stats_interval**: how often to poll Docker containers for stats. The default is every minute.
* **cgroup_path**: The path to cgroups pseudofiles. The default is `sys/fs/cgroup`.
* **tag_prefix**: The tag prefix. The default value is "docker"

## Example output

```
2014-11-22 17:48:26 +0000 docker.blkio.io_queued: {"key":"blkio_io_queued_total","value":0,"type":"counter","hostname":"precise64","id":"24f5fb3bfc429e88aa3dbacd704667899dc496067cedcfa58dd84da42e7cb3cf","name":"/world"}
2014-11-22 17:48:26 +0000 docker.blkio.sectors: {"key":"blkio_sectors","value":136,"type":"counter","hostname":"precise64","id":"24f5fb3bfc429e88aa3dbacd704667899dc496067cedcfa58dd84da42e7cb3cf","name":"/world"}
```

In particular, each event is a key-value pair of individual metrics. Also, it has

- `hostname` is the hostname of the Docker host
- `id` is the ID of the container
- `name` is the descriptive name of the container (a la `docker inspect --format '{{ .Names }}'`)

