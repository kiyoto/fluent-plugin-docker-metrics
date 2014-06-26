# Fluentd Docker Metrics Input Plugin

This is a [Fluentd](http://www.fluentd.org) plugin to collect Docker metrics periodically.

## How it works

It's assumed to run on the host server. It periodically runs `docker ps --no-trunc -q`
to get a list of running Docker container IDs, and it looks at `/sys/fs/cgroups/<metric_type>/docker/<container_id>/`
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
2014-06-26 18:16:43 +0000 docker.memory.stat: {"key":"memory_stat_total_active_anon","value":26025984,"source":"docker:precise64:b7f17c393775476bc0999cb6dcb4c6416e94b0473317375b9a245985dc6e91c5"}
2014-06-26 18:16:43 +0000 docker.memory.stat: {"key":"memory_stat_total_inactive_file","value":131072,"source":"docker:precise64:b7f17c393775476bc0999cb6dcb4c6416e94b0473317375b9a245985dc6e91c5"}
```

In particular, each event is a key-value pair of individual metrics. Also, it has a field whose value is "<tag_prefix>:<hostname>:<container_id>"
