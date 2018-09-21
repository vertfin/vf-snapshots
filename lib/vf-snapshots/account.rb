module VfSnapshots
  class Account

    attr_accessor :ec2, :name

    def initialize account_name
      @name = account_name
    end

    def region
      Config.accounts[@name][:region] || 'us-east-1'
    end

    def credentials
      { access_key_id: Config.accounts[@name][:access_key_id],
        secret_access_key: Config.accounts[@name][:secret_access_key],
        region: region,
      }
    end

    def account_id
      Config.accounts[@name][:account_id]
    end

    def snapshots
      return @snapshots if @snapshots
      VfSnapshots::verbose Rainbow("\nLoading snapshots for #{name}").green

      @snapshots = ec2.snapshots(
        owner_ids:['self'],
        filters: [
          { name: 'status', values: [ 'completed' ] },
        ]
      ).sort { |a,b| b.start_time <=> a.start_time }

      if filter = Config.options[:snapshot_filter]
        @snapshots = @snapshots.select { |s| !s.description.to_s.index(filter).nil? }
      end
      @snapshots
    end

    def volumes
      return @volumes if @volumes
      @volumes = []
      VfSnapshots::verbose Rainbow("\nLoading volumes for #{name}").green
      Instance.get_running(self).each do |instance|
        VfSnapshots::verbose Rainbow("  Checking #{name} #{instance.ec2_instance.id} for volumes").blue
        @volumes += instance.volumes # .each do |volume|
=begin
          case volume.ec2_volume.attachments.count
          when 0
            # this volume not attached to anything, not snapshoting
          when 1
            volume.ec2_volume.attachments.each do |attachment|
              VfSnapshots::verbose Rainbow("    adding #{ec2_volume.size.to_s}GB volume mounted at #{attachment.device.to_s}").white
              instance = attachment.instance
              @volumes << Volume.new(ec2_volume, ec2)
            end
          else
            raise "A volume has more than one attachment, that is impossible, my worldview has been shattered, and I am quitting now."
          end
        end
=end

      end
      VfSnapshots::verbose "\n"
      @volumes
    end

    def find_instance_by_name instance_name
      _instances = ec2.instances(
        { filters: [
            { name: 'instance-state-name', values: [ 'running' ] },
            { name: 'tag:Name', values: [ instance_name ] },
          ]
        }
      )
      raise "Multiple instances found with name: #{instance_name}" if _instances.count > 1
      raise "No instance found with name: #{instance_name}" if _instances.count == 0
      Instance.new(_instances.first, ec2)
    end

    def ec2
      VfSnapshots.verbose "\nSetting account to #{name}" if @ec2.nil?
      @ec2 ||= Aws::EC2::Resource.new( credentials )
    end

    def create_snapshots

    end

    def verify_snapshots

    end

    def self.for_each(account_name=nil)
      if account_name
        if Config.accounts.has_key?(account_name)
          yield Account.new(account_name)
        else
          puts "Account not found: #{account_name}"
        end
      else
        Config.accounts.keys.each do |account_name|
          yield Account.new(account_name)
        end
      end
    end

    def has_backup?
      Config.accounts[name][:backup]
    end

  end

end
