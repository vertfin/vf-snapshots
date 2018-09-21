module VfSnapshots
  class Backup

    attr_accessor :account

    def initialize account
      if Config.accounts[account.name][:backup]
        @account = account
        @name = account.name
        self
      else
        raise "No backup configured for Account:#{account.name}"
      end
    end

    def name
      @account.name
    end

    def account_id
      Config.accounts[@name][:backup][:account_id]
    end

    def region
      Config.accounts[@name][:backup][:region] || 'us-east-1'
    end

    def credentials
      { access_key_id: Config.accounts[@name][:backup][:access_key_id],
        secret_access_key: Config.accounts[@name][:backup][:secret_access_key],
        region: region
      }
    end

    def ec2
      VfSnapshots.verbose "\nSetting to backup account for #{name}" if @ec2.nil?
      @ec2 ||= Aws::EC2::Resource.new( credentials )
    end

    def sync
    end

    def snapshots
      return @snapshots if @snapshots
      VfSnapshots::verbose Rainbow("\nLoading backup snapshots for #{name}").green

      @snapshots = ec2.snapshots(
        owner_ids: ['self'],
        filters: [
          { name: 'status', values: [ 'completed' ] },
        ]
      ).sort { |a,b| b.start_time <=> a.start_time }

      if filter = Config.options[:snapshot_filter]
        @snapshots = @snapshots.select { |s| !s.description.to_s.index(filter).nil? }
      end
      @snapshots
    end

    # enumerate the missing snapshots
    def enumerate_missing
      account_snapshots = account.snapshots
      backed_up_snapshots = self.snapshots
      backed_up_snapshot_descriptions = backed_up_snapshots.collect { |bus| bus.description }
      missing = []
      account_snapshots.each do |snapshot|
        new_desc = "#{account.name} #{snapshot.description}"
        missing << snapshot if !backed_up_snapshot_descriptions.include?(new_desc) && (VfSnapshots::DESC_REGEX =~ snapshot.description) && snapshot.start_time.to_date > Date.today-( Config.accounts[account.name][:backup][:days] || VfSnapshots::DEFAULT_BACKUP_DAYS )
      end
      if missing.count > 0
        VfSnapshots.verbose "\n#{missing.count} to copy, here we go."
      else
        VfSnapshots.verbose "\nNothing to copy."
      end
      begin
        missing.each do |snapshot|
          VfSnapshots.verbose "\nCopying #{account.name} #{snapshot.description}"

          # modify the source snapshot to share with the backup account
          snapshot.modify_attribute(attribute:'createVolumePermission', operation_type: 'add', user_ids: [ account.account_id ], create_volume_permission: { add: [{ user_id: account_id }] } )
          # get it in the backup account
          shared_snapshot = ec2.snapshot(snapshot.id)
          region = 'us-east-1'
          new_desc = "#{account.name} #{snapshot.description}"
          copy_response = shared_snapshot.copy(
                         description: new_desc,
                         source_region: region,
                         destination_region: region
          )
          puts "Sleeping..."
          sleep 1
          puts "Woke!"
        end
      rescue Aws::EC2::Errors::ResourceLimitExceeded
        VfSnapshots.verbose "\nThrottled!"
      end
    end

    def copy_missing

    end

  end

end
