require File.expand_path(File.dirname(__FILE__) + '/unittest_helper')

require 'gri/builtindefs'
require 'gri/msnmp'
require 'gri/vendor'
require 'gri/plugin/ucdavis'

module GRI

class TestBuiltinDEFS < Test::Unit::TestCase
  def setup
  end

  def test_get_specs
    specs = DEFS.get_specs 'num'
    ae '_index', specs[:prop][:name]
    ae 4, specs[:rra].size
    specs = DEFS.get_specs ''
    ae 'ifInOctets,inoctet,DERIVE,MAX,AREA,#90f090,in,8', specs[:ds].first
    specs = DEFS.get_specs :l
  end

  def test_get_specs_foo
    specs = DEFS.get_specs :foo
    assert_nil specs
    DEFS.instance_eval {@specs = nil}
    DEFS['foo'] = {:tdb=>['foo', 'xx * 10', 'yy', 'zz']}
    specs = DEFS.get_specs :foo
    ae ['foo', 'xx', 'yy', 'zz'], specs[:tdb]
  end

  def test_interfaces_exclude_docker0_and_br
    specs = DEFS.get_specs ''
    assert specs[:ignore?].call({'ifDescr' => 'docker0'})
    assert specs[:ignore?].call({'ifDescr' => 'br-1234567890ab'})

    record = {
      'ifOperStatus' => '1',
      'ifInOctets' => '1',
      'ifOutOctets' => '1'
    }
    assert specs[:exclude?].call(record.merge('ifDescr' => 'docker0'))
    assert specs[:exclude?].call(record.merge('ifDescr' => 'br-1234567890ab'))
  end

  def test_suppress_veth_does_not_exclude_ens
    require 'gri/plugin/suppress_veth'
    DEFS.instance_eval {@specs = nil}
    specs = DEFS.get_specs ''

    ens = {
      'ifDescr' => 'ens18',
      'ifOperStatus' => '1',
      'ifSpeed' => '0',
      'ifInOctets' => '4111917315',
      'ifOutOctets' => '801580196'
    }
    assert !specs[:exclude?].call(ens)

    veth = ens.merge('ifDescr' => 'vethabc123', 'ifInOctets' => '0', 'ifOutOctets' => '0')
    assert specs[:exclude?].call(veth)
    assert specs[:exclude?].call(ens.merge('ifDescr' => 'docker0'))
    assert specs[:exclude?].call(ens.merge('ifDescr' => 'br-1234567890ab'))
  end

  def test_suppress_veth_handles_nil_octets
    require 'gri/plugin/suppress_veth'
    DEFS.instance_eval {@specs = nil}
    specs = DEFS.get_specs ''

    record = {
      'ifDescr' => 'ens18',
      'ifOperStatus' => '1',
      'ifSpeed' => '1000000000',
      'ifInOctets' => nil,
      'ifOutOctets' => nil
    }

    assert_nothing_raised { specs[:exclude?].call(record) }
    assert !specs[:exclude?].call(record)
  end
end

end
