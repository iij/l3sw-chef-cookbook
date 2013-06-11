#
# Cookbook Name:: l3sw-chef-cookbook
# Recipe:: default
#
#  Copyright (c) 2013, Internet Initiative Japan Inc.
#  All rights reserved.
# 
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
# 
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS. AND CONTRIBUTORS
#  ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
#  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
#  PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR CONTRIBUTORS
#  BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.

def strfy(str)
  return '"' + str + '"'
end

def hash_new(h, key)
  if h[key] == nil
    h[key] = Hash.new
  end
end

case node["platform_family"]
when "pica8"

  l3sw = Pica8Config.new
  conf = l3sw.config_raw_get

  config_changed = false

  # hostname
  hostname_candidate = node['l3sw']['system']['hostname']
  hostname_running = conf['system']['hostname'].slice!(0).chop!
  if hostname_running != nil and
      hostname_running != hostname_candidate
    conf['system']['hostname'] = "\"#{hostname_candidate}\""
    config_changed = true
  end

  # timezone
  tz_candidate = node['l3sw']['system']['timezone']
  tz_running = conf['system']['timezone'].slice!(0).chop!
  if tz_running != nil and
      tz_running != tz_candidate
    conf['system']['timezone'] = "\"#{tz_candidate}\""
    config_changed = true
  end

  # interface
  if_candidate = node['l3sw']['interface']
  if_running = conf['interface']
  if if_candidate != nil
    if_candidate.each_key do |ki|
      if ki == "gigabit-ethernet"
        if_candidate[ki].each_key do |kifn|
          # description
          desc_candid = if_candidate[ki][kifn]['description']
          if desc_candid != nil
            if_running["#{ki}:\"#{kifn}\""]['description'] = "\"#{desc_candid}\""
            config_changed = true
          end

          # family
          fm_candid = if_candidate[ki][kifn]['family']
          if fm_candid != nil
            es_candid = fm_candid['ethernet-switching']
            if es_candid != nil
              pm_candid = es_candid['port-mode']
              if pm_candid != nil
                hash_new(if_running["#{ki}:\"#{kifn}\""], 'family')
                hash_new(if_running["#{ki}:\"#{kifn}\""]['family'], 'ethernet-switching')
                if_running["#{ki}:\"#{kifn}\""]['family']['ethernet-switching']['port-mode'] = strfy(pm_candid)
                config_changed = true
              end
              vl_candid = es_candid['vlan']
              if vl_candid != nil
                vm_candid = vl_candid['members']
                if vm_candid != nil
                  hash_new(if_running["#{ki}:\"#{kifn}\""], 'family')
                  hash_new(if_running["#{ki}:\"#{kifn}\""]['family'], 'ethernet-switching')
                  hash_new(if_running["#{ki}:\"#{kifn}\""]['family']['ethernet-switching'], 'vlan')
                  hash_new(if_running["#{ki}:\"#{kifn}\""]['family']['ethernet-switching']['vlan'], 'members')
                  if_running["#{ki}:\"#{kifn}\""]['family']['ethernet-switching']['vlan']['members'] = ':' + vm_candid.to_s
                  config_changed = true
                end
              end
            end
          end
        end
      end
    end
  end

  # static route
  rt_candidate = node['l3sw']['protocols']['static']
  if rt_candidate != nil
    rt_edit = Hash.new
    rt_candidate.each_key do |dst|
      # next-hop
      rt_edit["route:#{dst}"] = Hash.new
      rt_edit["route:#{dst}"]['next-hop'] = rt_candidate[dst]['next-hop']
      config_changed = true
    end
    conf['protocols']['static'] = rt_edit
  end

  # vlans
  vlan_candidate = node['l3sw']['vlans']['vlan-id']
  if vlan_candidate != nil
    vlan_edit = Hash.new
    vlan_candidate.each_key do |vlanid|
      ve = Hash.new
      vlan_edit["vlan-id:#{vlanid}"] = ve
      if vlan_candidate[vlanid]['description'] != nil
        ve['description'] = strfy(vlan_candidate[vlanid]['description'])
      else
        ve['description'] = strfy('')
      end
      if vlan_candidate[vlanid]['vlan-name'] != nil
        ve['vlan-name'] = strfy(vlan_candidate[vlanid]['vlan-name'])
      else
        ve['vlan-name'] = strfy('default')
      end
      if vlan_candidate[vlanid]['l3-interface'] != nil
        ve['l3-interface'] = strfy(vlan_candidate[vlanid]['l3-interface'])
      else
        ve['l3-interface'] = strfy('')
      end
      conf['vlans'] = vlan_edit
      config_changed = true
    end
  end

  # apply config
  if config_changed
    l3sw.config_apply(conf)
    log "Configuration is changed (applied)"
  end
end
