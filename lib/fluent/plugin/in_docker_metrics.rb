require 'fluent/plugin/input'

module Fluent::Plugin
  class DockerMetricsInput < Input
    Fluent::Plugin.register_input('docker_metrics', self)

    helpers :timer

    # Define `router` method of v0.12 to support v0.10 or earlier
    unless method_defined?(:router)
      define_method("router") { Engine }
    end

    config_param :cgroup_path, :string, :default => '/sys/fs/cgroup'
    config_param :stats_interval, :time, :default => 60 # every minute
    config_param :tag_prefix, :string, :default => "docker"
    config_param :container_ids, :array, :default => nil # mainly for testing

    def initialize
      super
      require 'socket'
      require 'docker'
      @hostname = Socket.gethostname
      @with_systemd = File.exists?("#{@cgroup_path}/systemd")
    end

    def configure(conf)
      super

    end

    def start
      super
      timer_execute(:in_docker_metrics_timer, @stats_interval, &method(:get_metrics))
    end

    # Metrics collection methods
    def get_metrics
      ids = @container_ids || list_container_ids
      ids.each do |id, name|
        emit_container_metric(id, name, 'memory', 'memory.stat')
        emit_container_metric(id, name, 'cpuacct', 'cpuacct.stat')
        emit_container_metric(id, name, 'blkio', 'blkio.io_serviced')
        emit_container_metric(id, name, 'blkio', 'blkio.io_service_bytes')
        emit_container_metric(id, name, 'blkio', 'blkio.io_queued')
        emit_container_metric(id, name, 'blkio', 'blkio.sectors')
      end
    end

    def list_container_ids
      Docker::Container.all.map do |container|
        [container.id, container.info["Names"].first]
      end
    end

    def emit_container_metric(id, name, metric_type, metric_filename, opts = {})

      if @with_systemd
        path = "#{@cgroup_path}/#{metric_type}/system.slice/docker-#{id}.scope/#{metric_filename}"
      else
        path = "#{@cgroup_path}/#{metric_type}/docker/#{id}/#{metric_filename}"
      end

      if File.exist?(path)
        # the order of these two if's matters
        if metric_filename == 'blkio.sectors'
          parser = BlkioSectorsParser.new(path, metric_filename.gsub('.', '_'))
        elsif metric_type == 'blkio'
          parser = BlkioStatsParser.new(path, metric_filename.gsub('.', '_'))
        else
          parser = KeyValueStatsParser.new(path, metric_filename.gsub('.', '_'))
        end
        time = Fluent::Engine.now
        tag = "#{@tag_prefix}.#{metric_filename}"
        mes = Fluent::MultiEventStream.new
        parser.parse_each_line do |data|
          next if not data
          # TODO: address this more elegantly
          if data['key'] =~ /^(?:cpuacct|blkio|memory_stat_pg)/
            data['type'] = 'counter'
          else
            data['type'] = 'gauge'
          end
          data["hostname"] = @hostname
          data["id"] = id
          data["name"] = name.sub(/^\//, '')
          mes.add(time, data)
        end
        router.emit_stream(tag, mes)
      else
        nil
      end
    end

    def shutdown
      super
    end

    class TimerWatcher < Coolio::TimerWatcher

      def initialize(interval, repeat, log, &callback)
        @callback = callback
        @log = log
        super(interval, repeat)
      end
      def on_timer
        @callback.call
      rescue
        @log.error $!.to_s
        @log.error_backtrace
      end
    end

    class CGroupStatsParser
      def initialize(path, metric_type)
        raise ConfigError if not File.exists?(path)
        @path = path
        @metric_type = metric_type
      end

      def parse_line(line)
      end

      def parse_each_line(&block)
        File.new(@path).each_line do |line|
          block.call(parse_line(line))
        end
      end
    end

    class KeyValueStatsParser < CGroupStatsParser
      def parse_line(line)
        k, v = line.split(/\s+/, 2)
        if k and v
          { 'key' => @metric_type + "_" + k, 'value' => v.to_i }
        else
          nil
        end
      end
    end

    class BlkioStatsParser < CGroupStatsParser
      BlkioLineRegexp = /^(?<major>\d+):(?<minor>\d+) (?<key>[^ ]+) (?<value>\d+)/

      def parse_line(line)
        m = BlkioLineRegexp.match(line)
        if m
          { 'key' => @metric_type + "_" + m["key"].downcase, 'value' => m["value"].to_i }
        else
          nil
        end
      end
    end

    class BlkioSectorsParser < CGroupStatsParser
      BlkioSectorsLineRegexp = /^(?<major>\d+):(?<minor>\d+) (?<value>\d+)/

      def parse_line(line)
        m = BlkioSectorsLineRegexp.match(line)
        if m
          { 'key' => @metric_type, 'value' => m["value"].to_i }
        else
          nil
        end
      end
    end
  end
end
