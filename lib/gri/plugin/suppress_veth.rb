GRI::DEFS['interfaces'].update :ignore? => proc {|record|
  /(^(|Loopback|Null|Async)\d+)|(^veth\w)|(^docker0$)|(^br-)|cef layer|atm subif/ ===
    record['ifDescr']
},
  :exclude? => proc {|record|
  ifdescr = record['ifDescr'].to_s
  if_in_octets = Integer(record['ifInOctets'], exception: false)
  if_out_octets = Integer(record['ifOutOctets'], exception: false)
  record['ifOperStatus'].to_i != 1 or
    ((/\A(veth\w|docker0|br-)/ === ifdescr) && record['ifSpeed'].to_i == 0) or
    (if_in_octets == 0 and
     if_out_octets == 0) or
    /(^(|Loopback|Null|Async|lo)\d+)|(^veth\w)|(^docker0$)|(^br-)|cef layer|atm subif/ ===
    ifdescr
},
  :hidden? => proc {|record|
  /(^veth\w)|(^docker0$)|(^br-)|cef layer|atm subif|unrouted.VLAN/ === record['ifDescr']
}
