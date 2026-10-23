require File.expand_path(File.dirname(__FILE__) + '/unittest_helper')

require 'gri/rrd'
require 'tmpdir'
require 'json'

class TestRRD < Test::Unit::TestCase
  def setup
    @test_dir = File.expand_path(File.dirname(__FILE__))
  end

  def create_test_rrd path

  end

  def test_rrd_version
    rrd = RRD.new
    assert_match /\A1\.\d\z/, rrd.version
  end

  def test_remove_base_dir
    args = 'foo', 'bar', '/usr/local/gri/gra/host/host.rrd'
    rrd = RRD.new nil, nil
    res = rrd.remove_base_dir *args
    ae args, res
    base_dir = '/usr/local/gri/gra'
    rrd = RRD.new nil, base_dir
    res = rrd.remove_base_dir *args
    ae 'host/host.rrd', res[2]
    base_dir = '/usr/local/gri/gra'
    rrd = RRD.new nil, base_dir
    res = rrd.remove_base_dir *args
    ae 'host/host.rrd', res[2]
  end

  def test_rrd_create_and_graph
    Dir.mktmpdir('gri-rrd') do |dir|
      s = Time.local(2012,12,19,9)
      rrd_path = File.join(dir, 'test.rrd')
      rrd = RRD.new
      rrd.set_create_args rrd_path, s - 300, 300,
        'DS:number:GAUGE:600:U:U RRA:MAX:0.5:1:1000'
      s.to_i.step((s+24*3600).to_i, 300) {|i|
        rrd.buffered_update "#{i}:#{i%3600/300}"
      }
      rrd.flush_buffer

      stime = Time.local(2012,12,19,9,0)
      etime = Time.local(2012,12,20,9,0)
      img = rrd.graphgen stime, etime,
        ["DEF:number=#{rrd_path}:number:MAX", "LINE1:number#ff0000:id"]
      assert_equal "\x89PNG".b, img.byteslice(0, 4)
    end
  end

  def test_64_bit_counter_at_400_mbps
    Dir.mktmpdir('gri-rrd') do |dir|
      t0 = (Time.now.to_i / 300 - 10) * 300
      rrd = RRD.new
      rrd.set_create_args File.join(dir, 'traffic.rrd'), t0 - 300, 300,
        'DS:inoctet:DERIVE:900:U:U', 'RRA:MAX:0.5:1:20'
      rrd.buffered_update "#{t0}:5000000000"
      rrd.buffered_update "#{t0 + 300}:20000000000"
      rrd.flush_buffer

      rates = rrd.fetch('MAX', 300, t0, t0 + 600).map {|_, values| values.first}.compact
      assert rates.any? {|rate| (rate - 50_000_000).abs < 1}, rates.inspect
    end
  end

  def test_counter_reset_is_not_plotted_as_traffic
    Dir.mktmpdir('gri-rrd') do |dir|
      t0 = (Time.now.to_i / 300 - 10) * 300
      path = File.join(dir, 'traffic.rrd')
      rrd = RRD.new
      rrd.set_create_args path, t0 - 300, 300,
        'DS:inoctet:DERIVE:900:U:U', 'RRA:MAX:0.5:1:20'
      rrd.buffered_update "#{t0}:20000000000"
      rrd.buffered_update "#{t0 + 300}:35000000000"
      rrd.buffered_update "#{t0 + 600}:1000"
      rrd.flush_buffer

      expression = RRD.defstr([path], 'inoctet', 'MAX',
        'traffic', 'XPORT', '', 'in', 8, 0, nil)
      values = JSON.parse(rrd.xport(t0, t0 + 900, expression))['data'].
        map {|row| row.first}
      assert values.any? {|value| value && (value - 400_000_000).abs < 1}, values.inspect
      assert values.any?(&:nil?), values.inspect
      assert values.compact.all? {|value| value <= 400_000_000}, values.inspect
    end
  end

  def test_concurrent_graphs_use_separate_output_files
    paths = Queue.new
    continue = Queue.new
    rrd = RRD.allocate
    rrd.define_singleton_method(:graph) do |path, *args|
      paths << path
      continue.pop
      File.binwrite(path, "\x89PNG".b)
    end
    threads = 2.times.map {Thread.new {rrd.graphgen(0, 1, [])}}
    first_path, second_path = paths.pop, paths.pop
    assert_not_equal first_path, second_path
    2.times {continue << true}
    threads.each {|thread| ae "\x89PNG".b, thread.value}
  ensure
    2.times {continue << true} if continue
    threads&.each(&:join)
  end
end
