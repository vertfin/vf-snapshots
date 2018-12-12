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
          # once all of our backup snapshots have account tags, we can
          { name: 'tag:Account', values: [ account.name ] },
        ]
      ).sort { |a,b| b.start_time <=> a.start_time }

      if filter = Config.options[:snapshot_filter]
        @snapshots = @snapshots.select { |s| !s.description.to_s.index(filter).nil? }
      end
      @snapshots
    end

    # enumerate the missing snapshots and return
    def enumerate_missing
      account_snapshots = account.snapshots
      backed_up_snapshots = self.snapshots
      backed_up_snapshot_descriptions = backed_up_snapshots.collect { |bus| bus.description }
      missing = []
      account_snapshots.each do |snapshot|
        new_desc = "#{account.name} #{snapshot.description}"
        missing << snapshot if !backed_up_snapshot_descriptions.include?(new_desc) && (VfSnapshots::DESC_REGEX =~ snapshot.description) && snapshot.start_time.to_date > Date.today-( Config.accounts[account.name][:backup][:days] || VfSnapshots::DEFAULT_BACKUP_DAYS )
      end
      missing
    end

    # enumberate the missing snapshots and return
    def copy_snapshots! snaps
      # account_snapshots = account.snapshots
      # backed_up_snapshots = self.snapshots
      # backed_up_snapshot_descriptions = backed_up_snapshots.collect { |bus| bus.description }
      if snaps.count > 0
        VfSnapshots.verbose "\n#{snaps.count} to copy, here we go."
      else
        VfSnapshots.verbose "\nNothing to copy."
      end
      begin
        tags = { tags: [
                   {
                     key: "Account",
                     value: account.name,
                   },
                 ]
               }

        snaps.each_with_index do |snapshot,idx|
          VfSnapshots.verbose "\nCopying #{account.name} #{snapshot.description} [#{idx+1} of #{snaps.length}]"

          # modify the source snapshot to share with the backup account
          snapshot.modify_attribute(attribute:'createVolumePermission', operation_type: 'add', user_ids: [ account.account_id ], create_volume_permission: { add: [{ user_id: account_id }] } )
          # get it in the backup account
          shared_snapshot = ec2.snapshot(snapshot.id)
          region = 'us-east-1'
          new_desc = "#{account.name} #{snapshot.description}"
          copy_response = shared_snapshot.copy(
                         description: new_desc,
                         source_region: region,
                         destination_region: region,
          )
          ec2.snapshot(copy_response.snapshot_id).create_tags tags
          # puts "Sleeping..."
          # sleep 1
          # puts "Woke!"
        end
      rescue Aws::EC2::Errors::ResourceLimitExceeded
        VfSnapshots.verbose "\nThrottled!"
        exit
      end
    end


    # enumerate the snapshots to be pruned
    def enumerate_snapshots_to_be_pruned
      backed_up_snapshots = self.snapshots
      backed_up_snapshot_descriptions = backed_up_snapshots.collect { |bus| bus.description }
      prunees = []
      before = Date.today - ( Config.accounts[account.name][:backup][:days] || VfSnapshots::DEFAULT_BACKUP_DAYS )
      backed_up_snapshots.each do |snapshot|
        old_desc = snapshot.description.sub("#{account.name} ",'')
        account_name = snapshot.description.split(VfSnapshots::DESC_REGEX).first.chop
        if account_name == account.name
          if /^(\d{14})/.match(old_desc)
            ts = Time.parse($1).to_date
            prunees << snapshot if (VfSnapshots::DESC_REGEX =~ old_desc) && ts < before
          end
        end
      end
      prunees
    end

    # enumberate the missing snapshots and return
    def delete! snaps
      if snaps.count > 0
        VfSnapshots.verbose "\n#{snaps.count} to delete, here we go."
      else
        VfSnapshots.verbose "\nNothing to delete."
      end
      begin
        snaps.each_with_index do |snapshot,idx|
          VfSnapshots.verbose "Deleting #{account.name} #{snapshot.description} [#{idx+1} of #{snaps.length}]"
          snapshot.delete
          # puts "Sleeping..."
          # sleep 1
          # puts "Woke!"
        end
      rescue Aws::EC2::Errors::ResourceLimitExceeded
        VfSnapshots.verbose "\nThrottled!"
        exit
      end
    end

    # probably temporary, just need to get the backup snapshot repo up to
    # snuff.  we really want an Account tag in the backup repo.
    def tag_accounts!
      snapshots = ec2.snapshots( owner_ids: ['self'],
                                 #filters: [
                                 #  { name: 'tag:Account', values: [] ] },
                                 #]

                               )
      snapshots.each do |snapshot|
        if account_name = snapshot.description.split(VfSnapshots::DESC_REGEX).first.chop
          if account_name == account.name
            tags = { tags: [
                       {
                         key: "Account",
                         value: account_name,
                       },
                     ]
                   }
            puts "#{snapshot.description} -> { account: '#{account_name}' }"
            snapshot.create_tags tags
          end
        end
      end
    end


  end

end
