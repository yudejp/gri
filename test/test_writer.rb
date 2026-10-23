require File.expand_path(File.dirname(__FILE__) + '/unittest_helper')

require 'fileutils'
require 'tmpdir'

require 'gri/writer'
require 'gri/updater'

module GRI

class Writer
  attr_reader :options
end

class TestWriter < Test::Unit::TestCase
  def test_switch_to_64_bit_counter_does_not_create_a_spike
    Config.init
    Dir.mktmpdir('gri-writer') do |dir|
      writer = RRDWriter.new :gra_dir=>dir, :interval=>300
      t0 = (Time.now.to_i / 300 - 10) * 300
      base = {'_host'=>'testhost', '_key'=>'_eth0', '_interval'=>300,
        'ifDescr'=>'eth0', 'ifOperStatus'=>1, 'ifSpeed'=>1_000_000_000}
      samples = [
        {'ifInOctets'=>1_000_000_000},
        {'ifInOctets'=>21_000_000_000, 'ifHCInOctets'=>21_000_000_000},
        {'ifInOctets'=>36_000_000_000, 'ifHCInOctets'=>36_000_000_000},
        {'ifInOctets'=>51_000_000_000, 'ifHCInOctets'=>51_000_000_000}
      ]
      samples.each_with_index do |sample, index|
        writer.write [base.merge(sample).merge('_time'=>t0 + index * 300)]
      end

      rrd = RRD.new
      rrd.set_create_args File.join(dir, 'testhost', 'testhost__eth0.rrd')
      rates = rrd.fetch('MAX', 300, t0, t0 + 1200).
        map {|_, values| values.first}.compact
      assert rates.any? {|rate| (rate - 50_000_000).abs < 1}, rates.inspect
      assert rates.all? {|rate| rate <= 50_000_000}, rates.inspect
    end
  end

  def test_writer
    tra_dir = '/tmp'
    writer = Writer.create 'ldb', :tra_dir=>tra_dir, :tra_expire_day=>1
    assert_kind_of TextWriter, writer

    hdir = tra_dir + '/testhost'
    FileUtils.rm_r hdir, :force=>true
    records = [{'_host'=>'testhost', '_key'=>'SYS', '_sysdescr'=>'TEST'}]
    writer.write records
    writer.finalize
    sysdir = hdir + '/SYS_'
    fname = Dir.glob(sysdir + '/*').first
    str = File.read fname
    assert_match /_sysdescr:TEST/, str
    writer.purge_logs
    FileUtils.rm_r hdir, :force=>true
  end
end

end
