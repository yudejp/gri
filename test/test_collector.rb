# coding: us-ascii

require File.expand_path(File.dirname(__FILE__) + '/unittest_helper')

require 'socket'
require 'mock'
require 'gri/log'
require 'gri/collector'

module GRI

class MockSNMP < SNMP
  def connect
    @sock = MockUDPSocket.new
    @sock.connect @host, @port
  end
end

class TestCollector < Test::Unit::TestCase
  TEST_SYS = "0\x81\xF2\x02\x01\x01\x04\bpublic00\xA2\x81\xE2\x02" +
    "\x02\x03\xEA\x02\x01\x00\x02\x01\x000\x81\xD50d\x06\b+\x06\x01" +
    "\x02\x01\x01\x01\x00\x04XLinux xxxxx.yyyyy.zzz.com " +
    "X.X.XX-XXX.XX.X.XXX #1 SMP Thu Oct 31 12:00:00 EDT 2013 x86_64" +
    "0\x1F\x06\b+\x06\x01\x02\x01\x01\x05\x00\x04\x13xxxxx.yyyyy.zzz.com" +
    "0\x16\x06\b+\x06\x01\x02\x01\x01\x02\x00\x06\n+\x06\x01\x04\x01" +
    "\xBF\b\x03\x02\n0\x10\x06\b+\x06\x01\x02\x01\x01\x03\x00C\x04" +
    "\x7F\xC9i\xA10\"\x06\b+\x06\x01\x02\x01\x01\x06\x00" +
    "\x04\x16xxxxx xxxx, xxxxx xxx."

  def test_snmp_collector
    c = Collector.create('snmp', 'testhost', {}) {|records|}
    snmp = MockSNMP.new 'testhost'
    c.instance_eval {
      @loop = MockLoop.new
      @snmp = snmp
    }

    rs = {}
    c.get(SNMPCollector::SYSOIDS) {|results|
      results.each {|enoid, tag, val| rs[SNMP::ROIDS[enoid]] = val}
    }
    ae :GET_REQ, snmp.state

    ae 0, c.instance_eval('@retry_count')
    c.retry
    ae 1, c.instance_eval('@retry_count')

    snmp.sock.data = TEST_SYS
    c.on_readable
    ae rs['sysName.0'], 'xxxxx.yyyyy.zzz.com'

    enoid = BER.enc_v_oid SNMP::OIDS['ipAdEntIfIndex']
    c.walk(enoid) {|enoid, tag, val|}
    ae :GETNEXT_REQ, snmp.state
  end

  def test_snmp_collector_fake_snmp
    opts = {'fake-snmp'=>File.join($test_dir, 'fake_snmp.txt')}
    records = nil
    c = Collector.create('snmp', 'testhost', opts) {|rs| records = rs}
    c.attach MockLoop.new

    sys = records.detect {|r| r['_key'] == 'SYS'}
    ae 'HOSTNAME.example.com', sys['sysName']

    eth0 = records.detect {|r| r['ifDescr'] == 'eth0'}
    ae '_eth0', eth0['_key']
    ae 1000000000, eth0['ifSpeed']
  end

  def test_snmp_collector_retry_fallback_getbulk_to_getnext
    c = Collector.create('snmp', 'testhost', {}) {|records|}
    snmp = MockSNMP.new 'testhost'
    snmp.connect
    c.instance_eval {
      @loop = MockLoop.new
      @snmp = snmp
      @buffers = []
      @tout = 5
      @retry_count = 3
      @preq = [:GETBULK_REQ, BER.enc_v_oid('1.3.6.1.2.1.1')]
    }
    snmp.state = :GETBULK_REQ

    c.retry

    ae :GETNEXT_REQ, snmp.state
    assert !c.instance_eval('@buffers').empty?
    ae 0, c.instance_eval('@retry_count')
    ae true, snmp.bulk_unavailable
  end

  def test_snmp_collector_retry_fallback_getbulk_immediately
    c = Collector.create('snmp', 'testhost', {}) {|records|}
    snmp = MockSNMP.new 'testhost'
    snmp.connect
    c.instance_eval {
      @loop = MockLoop.new
      @snmp = snmp
      @buffers = []
      @tout = 5
      @retry_count = 0
      @preq = [:GETBULK_REQ, BER.enc_v_oid('1.3.6.1.2.1.1')]
    }
    snmp.state = :GETBULK_REQ

    c.retry

    ae :GETNEXT_REQ, snmp.state
    assert !c.instance_eval('@buffers').empty?
    ae 0, c.instance_eval('@retry_count')
    ae [:GETNEXT_REQ, BER.enc_v_oid('1.3.6.1.2.1.1')], c.instance_eval('@preq')
    ae true, snmp.bulk_unavailable
  end

  def test_hc_cache_support_detected
    host = 'hctest1'
    SNMPCollector.class_variable_get(:@@hc_cache).clear

    c = Collector.create('snmp', host, {}) {|records|}
    c.instance_eval {
      @loop = MockLoop.new
      @snmp = MockSNMP.new('test')
      @snmp.connect
      @detect_results = []
      @detect_cb = nil
    }

    hc_enoid = BER.enc_v_oid(SNMP::OIDS['ifHCInOctets'])
    mock_results = [[hc_enoid, 0x43, 12345]]
    c.define_singleton_method(:walk) do |enoid, cb=nil, detect: false, &b|
      cb ||= b
      if detect
        cb.call mock_results
      else
        cb.call []
      end
    end

    c.detect_walk_next([hc_enoid.dup]) {|supported|
      SNMPCollector.class_variable_get(:@@hc_cache)[host] = {
        support: supported, checked_at: Time.now
      }
    }

    cache = SNMPCollector.class_variable_get(:@@hc_cache)[host]
    assert cache
    assert_equal true, cache[:support]
    assert_kind_of Time, cache[:checked_at]
  end

  def test_hc_cache_no_support
    host = 'hctest2'
    SNMPCollector.class_variable_get(:@@hc_cache).clear

    c = Collector.create('snmp', host, {}) {|records|}
    c.instance_eval {
      @loop = MockLoop.new
      @snmp = MockSNMP.new('test')
      @snmp.connect
      @detect_results = []
      @detect_cb = nil
    }

    c.define_singleton_method(:walk) do |enoid, cb=nil, detect: false, &b|
      cb ||= b
      cb.call []
    end

    hc_enoid = BER.enc_v_oid(SNMP::OIDS['ifHCInOctets'])
    c.detect_walk_next([hc_enoid]) {|supported|
      SNMPCollector.class_variable_get(:@@hc_cache)[host] = {
        support: supported, checked_at: Time.now
      }
    }

    cache = SNMPCollector.class_variable_get(:@@hc_cache)[host]
    assert cache
    assert_equal false, cache[:support]
  end

  def test_hc_cache_returns_cached_result
    host = 'hctest3'
    SNMPCollector.class_variable_get(:@@hc_cache).clear

    SNMPCollector.class_variable_get(:@@hc_cache)[host] = {
      support: true, checked_at: Time.now
    }

    c = Collector.create('snmp', host, {}) {|records|}
    c.instance_eval {
      @loop = MockLoop.new
      @detect_results = []
      @detect_cb = nil
    }

    result = c.detect_hc(host)
    assert_equal true, result
  end

  def test_hc_cache_expires
    host = 'hctest4'
    SNMPCollector.class_variable_get(:@@hc_cache).clear

    SNMPCollector.class_variable_get(:@@hc_cache)[host] = {
      support: true, checked_at: Time.now - 100000
    }

    c = Collector.create('snmp', host, {'hc-recheck-interval'=>'0'}) {|records|}
    c.instance_eval {
      @loop = MockLoop.new
      @snmp = MockSNMP.new('test')
      @snmp.connect
      @detect_results = []
      @detect_cb = nil
    }

    mock_results = [[BER.enc_v_oid(SNMP::OIDS['ifHCInOctets'] + '.1'), 0x43, 999]]
    c.define_singleton_method(:walk) do |enoid, cb=nil, detect: false, &b|
      cb ||= b
      if detect
        cb.call mock_results
      else
        cb.call []
      end
    end

    c.detect_hc(host)
    c.on_readable

    cache = SNMPCollector.class_variable_get(:@@hc_cache)[host]
    assert cache
    assert cache[:checked_at] > Time.now - 5
  end

  def test_hc_cache_skips_ifmib_when_unsupported
    host = 'hctest5'
    SNMPCollector.class_variable_get(:@@hc_cache).clear
    SNMPCollector.class_variable_get(:@@hc_cache)[host] = {
      support: false, checked_at: Time.now
    }

    c = Collector.create('snmp', host, {}) {|records|}
    snmp = MockSNMP.new host
    c.instance_eval {
      @loop = MockLoop.new
      @snmp = snmp
    }

    c.get(SNMPCollector::SYSOIDS) {|results| }

    sysinfo = {'sysObjectID'=>'', 'sysDescr'=>'test'}
    sysinfo['_host'] = host
    sysinfo['_key'] = 'SYS'
    sysinfo['_time'] = Time.now.to_i
    sysinfo['_mtime'] = Time.now.to_i

    vendor = Vendor.check sysinfo, {'interfaces'=>true, 'ifMIB'=>true}
    punits = vendor.get_punits

    if vendor.options['ifMIB']
      cached = SNMPCollector.class_variable_get(:@@hc_cache)[host]
      interval = 86400
      hc_known = cached && (Time.now - cached[:checked_at]) < interval
      if hc_known && !cached[:support]
        punits.reject! {|pu| pu.name == 'ifMIB'}
      end
    end

    ifmib_pu = punits.find {|pu| pu.name == 'ifMIB'}
    assert_nil ifmib_pu
  end

  def test_hc_cache_keeps_ifmib_when_supported
    host = 'hctest6'
    SNMPCollector.class_variable_get(:@@hc_cache).clear
    SNMPCollector.class_variable_get(:@@hc_cache)[host] = {
      support: true, checked_at: Time.now
    }

    c = Collector.create('snmp', host, {}) {|records|}

    sysinfo = {'sysObjectID'=>'', 'sysDescr'=>'test'}
    sysinfo['_host'] = host
    sysinfo['_key'] = 'SYS'
    sysinfo['_time'] = Time.now.to_i
    sysinfo['_mtime'] = Time.now.to_i

    vendor = Vendor.check sysinfo, {'interfaces'=>true, 'ifMIB'=>true}
    punits = vendor.get_punits

    if vendor.options['ifMIB']
      cached = SNMPCollector.class_variable_get(:@@hc_cache)[host]
      interval = 86400
      hc_known = cached && (Time.now - cached[:checked_at]) < interval
      if hc_known && !cached[:support]
        punits.reject! {|pu| pu.name == 'ifMIB'}
      end
    end

    ifmib_pu = punits.find {|pu| pu.name == 'ifMIB'}
    refute_nil ifmib_pu
  end
end

end
