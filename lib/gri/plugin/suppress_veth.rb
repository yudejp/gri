GRI::DEFS['interfaces'].update :ignore? => proc {|record|
  /(^(|Loopback|Null|Async)\d+)|(^veth\w)|(^docker0$)|(^br-)|cef layer|atm subif/ ===
    record['ifDescr']
},
  :exclude? => proc {|record|
  ifdescr = record['ifDescr'].to_s
  record['ifOperStatus'].to_i != 1 or
    ((/\A(veth\w|docker0|br-)/ === ifdescr) && record['ifSpeed'].to_i == 0) or
    (Integer(record['ifInOctets']) == 0 and
     Integer(record['ifOutOctets']) == 0) or
    /(^(|Loopback|Null|Async|lo)\d+)|(^veth\w)|(^docker0$)|(^br-)|cef layer|atm subif/ ===
    ifdescr
},
  :hidden? => proc {|record|
  /(^veth\w)|(^docker0$)|(^br-)|cef layer|atm subif|unrouted.VLAN/ === record['ifDescr']
}
