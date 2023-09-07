module VfSnapshots
  class Instance

    attr_accessor :ec2, :ec2_instance, :config

    def initialize ec2_instance, ec2
      @ec2_instance = ec2_instance
      @ec2          = ec2
    end

    def volumes
      @volumes ||= ec2.volumes(
        { filters: [
            { name: 'attachment.instance-id', values: [ ec2_instance.id ] },
          ]
        }
      ).collect { |ec2_volume|
        VfSnapshots::verbose Rainbow("    adding #{ec2_volume.size.to_s}GB volume mounted at #{ec2_volume.attachments.first[:device].to_s}").white

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
      name = ec2_instance.tags.find { |tag| tag.key=='Name' }.value

      a = {
        # dry_run: true,
        name: "TEMPORARY Cloned AMI from #{system_volume.name} #{VfSnapshots.current_time_string}",
        architecture: ec2_instance.architecture.to_s,
        kernel_id: ec2_instance.kernel_id,
        ramdisk_id: ec2_instance.ramdisk_id,
        root_device_name: root_device,
        virtualization_type: ec2_instance.virtualization_type,
        block_device_mappings: [
          {
            device_name: root_device,
            ebs: {
              snapshot_id: system_volume.most_recent_snapshot.id,
            }
          }
        ]
      }

      a.each_pair do |k,v|
        a.delete(k) if v.nil?
      end

      new_ami_id = ec2.client.register_image(a).image_id
      new_ami = nil

      t = 0
      while new_ami.nil? || new_ami.state.to_s != 'available' do
        sleep 1
        new_ami ||= ec2.images( filters: [ { name: 'image-id', values: [new_ami_id] } ] ).first
        t += 1
        VfSnapshots.verbose "[#{t}] Waiting for AMI to become available..."
      end

      bdm = []
      data_volumes.each do |dv|
        bdm << {
          device_name: dv.ec2_volume.attachments.first.device,
          ebs: {
            snapshot_id: dv.most_recent_snapshot.id,
          },
        }
      end

      name = "#{name} Autoclone from snapshots #{VfSnapshots.current_time_string}"
      a = {
        # dry_run: true,
        image_id: new_ami_id,
        min_count: 1,
        max_count: 1,
        instance_type: ec2_instance.instance_type,
        kernel_id: ec2_instance.kernel_id,
        security_group_ids: ec2_instance.security_groups.collect(&:group_id),
        placement: ec2_instance.placement,
        tag_specifications: [
          {
            resource_type: "instance",
            tags: [
                {
                  key: "Name",
                  value: name,
                },
            ],
          },
        ]

      }

      a[:block_device_mappings] = bdm unless bdm.empty?

      if Config.options[:security_group_id]
        if Config.options[:security_group_id]=='none'
          a.delete(:security_group_ids)
        else
          a[:security_group_ids] = [Config.options[:security_group_id]]
        end
      end

      a.each_pair do |k,v|
        a.delete(k) if v.nil?
      end

      [:ramdisk_id, :subnet_id].each do |f|
        v = ec2_instance.send(f)
        a[f] = v unless v.nil?
      end

      if Config.options[:subnet_id]
        a[:subnet_id] = Config.options[:subnet_id]
        a.delete(:placement)
      end

      cloned_instance = ec2.create_instances(a)

      VfSnapshots.verbose "New Instance Name: #{name}"
      new_ami.deregister
    end

    def self.get_running account
      account.ec2.instances(
        { filters: [
            { name: 'instance-state-name', values: [ 'running' ] },
          ]
        }
      ).collect { |ec2_instance| Instance.new(ec2_instance, account.ec2) }
    end

  end

end
