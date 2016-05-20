module VfSnapshots
  class Instance

    attr_accessor :ec2, :ec2_instance

    def initialize ec2_instance, ec2
      @ec2_instance = ec2_instance
      @ec2          = ec2
    end

    def volumes
      @volumes ||= ec2.volumes.filter('attachment.instance-id', ec2_instance.id ).collect { |ec2_volume|
        VfSnapshots::verbose Rainbow("    adding #{ec2_volume.size.to_s}GB volume mounted at #{ec2_volume.attachments.first.device.to_s}").white

        Volume.new(ec2_volume, ec2)
      }
    end

    def clone
      #     cloning steps:
      # +++ find instance
      # --- note region, security group, and arch of instance
      # --- get chosen system clone (sda1/xvda1)
      # --- get the AKI (and maybe the ramdisk id?)
      # --- register a new AMI, plug in the arch, AKI and Ramdisk ID
      # --- make new volume from data snapshot(s), give it a good name
      # --- launch instance, setting region and security group, give it a good name
      # --- attach volume(s) ( will we need to reboot?  can we attach before boot? )
      # --- wait for instance to be running
      # --- deregister AMI
      # --- cocktail?

      system_volume = volumes.select { |a| a.ec2_volume.attachments.first.device.index(/xvda|sda/) }
      raise "More than one system volume?" if system_volume.length > 1
      raise "System volume (sda/xvda) not found" if system_volume.length == 0
      system_volume = system_volume.first

      data_volumes = volumes.select { |a| a.ec2_volume.attachments.first.device.index(/xvda|sda/).nil? }

      VfSnapshots.verbose "System Volume: #{system_volume.name}"
      VfSnapshots.verbose "Other(s): #{data_volumes.collect(&:name)}"

      root_device = system_volume.ec2_volume.attachments.first.device

      a = {
                   name: "TEMPORARY Cloned AMI from #{system_volume.name} #{VfSnapshots.current_time_string}",
                   architecture: ec2_instance.architecture.to_s,
                   kernel_id: ec2_instance.kernel_id,
                   root_device_name: root_device,
                   block_device_mappings: { root_device => { :snapshot_id => system_volume.most_recent_snapshot.id } }
      }
      a[ramdisk_id] = ec2_instance.ramdisk_id if ec2_instance.ramdisk_id

      a.each_pair do |k,v|
        a.delete(k) if v.nil?
      end
      new_ami = ec2.images.create(a)

      t = 0
      while ec2.images[new_ami.id].nil? || new_ami.state.to_s != 'available' do
        sleep 1
        t += 1
        VfSnapshots.verbose "[#{t}] Waiting for AMI to become available..."
      end

      bdm = {}
      data_volumes.each do |dv|
        bdm[dv.ec2_volume.attachments.first.device] = { :snapshot_id => dv.most_recent_snapshot.id }
      end

      a = {
        count: 1,
        instance_type: ec2_instance.instance_type,
        kernel_id: ec2_instance.kernel_id,
        security_groups: ec2_instance.security_groups,
        availability_zone: ec2_instance.availability_zone,
        block_device_mappings: bdm

      }
      a.each_pair do |k,v|
        a.delete(k) if v.nil?
      end

      a[ramdisk_id] = ec2_instance.ramdisk_id if ec2_instance.ramdisk_id

      cloned_instance = new_ami.run_instance(a)
      VfSnapshots.verbose "New Instance: #{cloned_instance.inspect}"
      name = "#{self.ec2_instance.tags.to_h['Name']} Autoclone from snapshots #{VfSnapshots.current_time_string}"
      VfSnapshots.verbose "Name: #{name}"
      cloned_instance.tags['Name'] = name

      new_ami.deregister
    end

    def self.get_running account
      account.ec2.instances.filter('instance-state-name', 'running').collect { |ec2_instance| Instance.new(ec2_instance, account.ec2) }
    end

  end

end
