require 'fluent/test'
require 'fluent/test/driver/input'
require 'fluent/plugin/in_docker_metrics'
require 'fakefs/safe'
require 'minitest/autorun'

class TestDockerMetricsInput < Minitest::Test
  METRICS = [
      ['memory', 'memory.stat'],
      ['cpuacct', 'cpuacct.stat'],
      ['blkio', 'blkio.io_serviced'],
      ['blkio', 'blkio.io_service_bytes'],
      ['blkio', 'blkio.io_queued'],
      ['blkio', 'blkio.sectors']
    ]

  def setup
    Fluent::Test.setup
    @container_id = 'sadais1337hacker'
    @container_name = 'sample_container'
    @mock_metrics = read_mock_metrics
    FakeFS.activate!
    setup_proc_files
  end

  def read_mock_metrics
    metrics = {}
    METRICS.each do |_, file|
      p = "#{File.dirname(File.expand_path(__FILE__))}/data/#{file}"
      if not File.exists?(p)
        raise IOError, p
      end
      metrics[file] = File.new(p).read
    end
    metrics
  end

  def setup_proc_files
    METRICS.each do |type, file|
      path = "/sys/fs/cgroup/#{type}/docker/#{@container_id}"
      FileUtils.mkdir_p(path)
      fh = File.new("#{path}/#{file}", "w")
      fh.write(@mock_metrics[file])
      fh.close
    end
  end

  def create_driver
    Fluent::Test::Driver::Input.new(Fluent::Plugin::DockerMetricsInput).configure(%[
      container_ids [["#{@container_id}", "#{@container_name}"]]
      stats_interval 5s
    ])
  end

  def test_outputs
    d = create_driver
    d.run(expect_emits: 46, timeout: 5)

    emits = d.events
    check_metric_type(emits, 'memory.stat', [
        {"key"=>"memory_stat_cache", "value"=>32768},
        {"key"=>"memory_stat_rss", "value"=>471040},
        {"key"=>"memory_stat_mapped_file", "value"=>0},
        {"key"=>"memory_stat_pgpgin", "value"=>293},
        {"key"=>"memory_stat_pgpgout", "value"=>170},
        {"key"=>"memory_stat_swap", "value"=>0},
        {"key"=>"memory_stat_pgfault", "value"=>1254},
        {"key"=>"memory_stat_pgmajfault", "value"=>0},
        {"key"=>"memory_stat_inactive_anon", "value"=>20480},
        {"key"=>"memory_stat_active_anon", "value"=>483328},
        {"key"=>"memory_stat_inactive_file", "value"=>0},
        {"key"=>"memory_stat_active_file", "value"=>0},
        {"key"=>"memory_stat_unevictable", "value"=>0},
        {"key"=>"memory_stat_hierarchical_memory_limit", "value"=>9223372036854775807},
        {"key"=>"memory_stat_hierarchical_memsw_limit", "value"=>9223372036854775807},
        {"key"=>"memory_stat_total_cache", "value"=>32768},
        {"key"=>"memory_stat_total_rss", "value"=>471040},
        {"key"=>"memory_stat_total_mapped_file", "value"=>0},
        {"key"=>"memory_stat_total_pgpgin", "value"=>293},
        {"key"=>"memory_stat_total_pgpgout", "value"=>170},
        {"key"=>"memory_stat_total_swap", "value"=>0},
        {"key"=>"memory_stat_total_pgfault", "value"=>1254},
        {"key"=>"memory_stat_total_pgmajfault", "value"=>0},
        {"key"=>"memory_stat_total_inactive_anon", "value"=>20480},
        {"key"=>"memory_stat_total_active_anon", "value"=>483328},
        {"key"=>"memory_stat_total_inactive_file", "value"=>0},
        {"key"=>"memory_stat_total_active_file", "value"=>0},
        {"key"=>"memory_stat_total_unevictable", "value"=>0}
      ])
    check_metric_type(emits, 'cpuacct.stat', [
        {"key"=>"cpuacct_stat_user", "value"=>0},
        {"key"=>"cpuacct_stat_system", "value"=>0}
      ])
    check_metric_type(emits, 'blkio.io_queued', [
        {"key"=>"blkio_io_queued_read", "value"=>0},
        {"key"=>"blkio_io_queued_write", "value"=>0},
        {"key"=>"blkio_io_queued_sync", "value"=>0},
        {"key"=>"blkio_io_queued_async", "value"=>0},
        {"key"=>"blkio_io_queued_total", "value"=>0}
      ])
    check_metric_type(emits, 'blkio.io_serviced', [
        {"key"=>"blkio_io_serviced_read", "value"=>822},
        {"key"=>"blkio_io_serviced_write", "value"=>1},
        {"key"=>"blkio_io_serviced_sync", "value"=>823},
        {"key"=>"blkio_io_serviced_async", "value"=>0},
        {"key"=>"blkio_io_serviced_total", "value"=>823}
      ])
    check_metric_type(emits, 'blkio.sectors', [
        {"key"=>"blkio_sectors", "value"=>816}
      ])
  end

  def check_metric_type(emits, type, records)
    stats = emits.select do |tag, time, record| tag == "docker.#{type}" end
    assert_equal records.length, stats.length, "Mismatch for #{type}"
    assert_equal @container_id, emits.first[2]["id"]
    assert_equal @container_name, emits.first[2]["name"]
    records.each do |record|
      find_metric(stats, record)
    end
  end

  def find_metric(emits, expected_record)
    match = emits.select do |_, _, record|
      record["key"] == expected_record["key"] &&
      record["value"] == expected_record["value"]
    end

    assert_equal 1, match.length, "Didn't find #{expected_record.to_json} among #{emits.to_json}"
  end

  def teardown
    FakeFS.deactivate!
  end
end
