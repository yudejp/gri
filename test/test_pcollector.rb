require File.expand_path(File.dirname(__FILE__) + '/unittest_helper')

require 'gri/config'
require 'gri/pcollector'
require 'mock'
require 'tmpdir'
require 'socket'

module GRI

class TestPCollector < Test::Unit::TestCase
  def setup
    path = File.expand_path(File.dirname(__FILE__) + '/root/testtab')
    config = Config.new
    config['gritab-path'] = path
    @app = AppCollector.new config
    lines = @app.load_target_lines config
    @targets = @app.get_targets_from_lines lines, config
  end

  def test_pcollector_get_ptargets
    targets = @targets

    basetime = Time.local(2013,4,1,10,5).to_i
    ptargets = @app.get_ptargets targets, basetime, 0
    ae 1, ptargets.size
    ae basetime.to_i, ptargets.keys.first

    ptargets = @app.get_ptargets targets, basetime, 1
    t = Time.local(2013,4,1,10,5).to_i
    hosts = ptargets[t].map {|n| targets[n].first}.sort
    ae ["host01", "host02", "host03", "host04", "host05", "localhost"], hosts

    basetime = Time.local(2013,4,1,10,0).to_i
    ptargets = @app.get_ptargets targets, basetime, 300
    t = Time.local(2013,4,1,10,0).to_i
    hosts = ptargets[t].map {|n| targets[n].first}.sort
    ae ["host00", "host01", "host02", "host03", "host04", "host05", "host06",
      "localhost"], hosts

    basetime = Time.local(2013,4,1,10,7).to_i
    ptargets = @app.get_ptargets targets, basetime, 300
    t = Time.local(2013,4,1,10,10).to_i
    hosts = ptargets[t].map {|n| targets[n].first}.sort
    ae ["host01", "host02", "host03", "host04", "host05", "localhost"], hosts

    basetime = Time.local(2013,4,1,10,7).to_i
    ptargets = @app.get_ptargets targets, basetime, 300, 120

    #for t, inds in ptargets.sort_by {|t,| t}
    #  p [Time.at(t), inds.map {|ind|targets[ind].first}]
    #end
  end

  def test_pcollector_server_loop
    @app.server_loop([], {}, nil, nil)
  end

  def test_parallel_run_uses_process_socket_and_preserves_other_results
    Dir.mktmpdir('gri-parallel') do |dir|
      begin
        probe = UNIXServer.new File.join(dir, 'probe.sock')
        probe.close
      rescue Errno::EPERM
        omit 'Unix sockets are unavailable in this sandbox'
      end
      config = Config.new
      config['root-dir'] = dir
      config['log-dir'] = dir
      app = AppCollector.new config
      other_result = File.join(dir, 'res.other.dump')
      File.write(other_result, 'other run')
      socket_path = nil
      app.define_singleton_method(:fork_child) do |server, path, *args|
        socket_path = path
        []
      end
      app.define_singleton_method(:server_loop) do |*args|
      end

      app.run_para [], nil, Time.now.to_i, nil

      assert_match %r{\A/tmp/\.gcollectsock\.#{Process.pid}\.[0-9a-f]{12}\z},
        socket_path
      assert File.exist?(other_result)
      assert !File.exist?(socket_path)

      app.define_singleton_method(:server_loop) do |*args|
        raise Timeout::Error, 'collector worker did not connect'
      end
      assert_raise(Timeout::Error) {app.run_para [], nil, Time.now.to_i, nil}
      assert !File.exist?(socket_path)
      assert File.exist?(other_result)

      occupied_path = File.join(dir, 'occupied.sock')
      occupied = UNIXServer.new occupied_path
      config['sock-path'] = occupied_path
      assert_raise(Errno::EADDRINUSE) do
        app.run_para [], nil, Time.now.to_i, nil
      end
      occupied.close
    end
  end

  def test_disabled_interval_does_not_shift_target_indices
    targets = [['disabled', {'interval'=>0}], ['enabled', {'interval'=>300}]]
    ptargets = @app.get_ptargets targets, 1_800_000_000, 300
    ae [1], ptargets[1_800_000_000]
  end

  def test_pcollector_get_max_queue_size
    config = Config.new
    app = AppCollector.new config
    assert_kind_of Integer, @app.get_max_queue_size
  end

  def test_pcollector_fork_child
    @app.extend MockFork
    nproc = 2
    pids = @app.fork_child nil, nil, nproc, nil, nil, nil, nil
    ae nproc, pids.size
  end
end

end
