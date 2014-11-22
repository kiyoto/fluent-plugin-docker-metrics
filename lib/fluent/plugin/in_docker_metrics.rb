module Fluent
  class DockerMetricsInput < Input
    Plugin.register_input('docker_metrics', self)

    config_param :cgroup_path, :string, :default => '/sys/fs/cgroup'
    config_param :stats_interval, :time, :default => 60 # every minute
    config_param :tag_prefix, :string, :default => "docker"
    config_param :container_ids, :array, :default => nil # mainly for testing

    def initialize
      super
      require 'socket'
      @hostname = Socket.gethostname
    end

    def configure(conf)
      super

    end

    def start
      @loop = Coolio::Loop.new
      tw = TimerWatcher.new(@stats_interval, true, @log, &method(:get_metrics))
      tw.attach(@loop)
      @thread = Thread.new(&method(:run))
    end
    def run
      @loop.run
    rescue
      log.error "unexpected error", :error=>$!.to_s
      log.error_backtrace
    end

    # Metrics collection methods
    def get_metrics
      ids = @container_ids || list_container_ids
      ids.each do |id|
        emit_container_metric(id, 'memory', 'memory.stat') 
        emit_container_metric(id, 'cpuacct', 'cpuacct.stat') 
        emit_container_metric(id, 'blkio', 'blkio.io_serviced') 
        emit_container_metric(id, 'blkio', 'blkio.io_service_bytes') 
        emit_container_metric(id, 'blkio', 'blkio.io_queued') 
        emit_container_metric(id, 'blkio', 'blkio.sectors') 
      end
    end

    def list_container_ids
      `docker ps --no-trunc -q`.split /\s+/
    end

    def emit_container_metric(id, metric_type, metric_filename, opts = {})
      path = "#{@cgroup_path}/#{metric_type}/docker/#{id}/#{metric_filename}"

      if File.exists?(path)
        # the order of these two if's matters
        if metric_filename == 'blkio.sectors'
          parser = BlkioSectorsParser.new(path, metric_filename.gsub('.', '_'))
        elsif metric_type == 'blkio'
          parser = BlkioStatsParser.new(path, metric_filename.gsub('.', '_'))
        else
          parser = KeyValueStatsParser.new(path, metric_filename.gsub('.', '_'))
        end
        time = Engine.now
        tag = "#{@tag_prefix}.#{metric_filename}"
        mes = MultiEventStream.new
        parser.parse_each_line do |data|
          next if not data
          # TODO: address this more elegantly
          if data['key'] =~ /^(?:cpuacct|blkio|memory_stat_pg)/
            data['type'] = 'counter'
          else
            data['type'] = 'gauge'
          end
          containerName = `docker inspect --format '{{ .Name }}' #{id}`.strip[1..-1]
          data["source"] = "#{@tag_prefix}:#{@hostname}:#{containerName}"
          mes.add(time, data)
        end
        Engine.emit_stream(tag, mes)
      else
        nil
      end
    end

    def shutdown
      @loop.stop
      @thread.join
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
  