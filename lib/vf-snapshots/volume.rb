module VfSnapshots
  class Volume

    attr_accessor :ec2, :ec2_volume, :instance_id, :instance, :attachment

    def snapshots
      return @snapshots if @snapshots
      # Aws.memoize do
      @snapshots = ec2.snapshots(
        { filters: [
            { name: 'status', values: [ 'completed' ] },
            { name: 'volume-id', values: [ ec2_volume.id ] },
          ]
        }
      ).sort { |a,b| b.start_time <=> a.start_time }
      # end
      if filter = Config.options[:snapshot_filter]
        @snapshots = @snapshots.select { |s| !s.description.to_s.index(filter).nil? }
      end
      @snapshots
    end

    public
    def initialize ec2_volume, ec2
      @ec2_volume = ec2_volume
      @ec2        = ec2
      # we'll only get here with volumes that have ONE attachment
      ec2_volume.attachments.each do |attachment|
        @attachment = attachment
        @instance_id = attachment.instance_id
      end
      # get the instance
      @instance = ec2.instance( @instance_id )
    end

    def name
      "#{instance_id} #{instance.tags.find { |t| t.key=='Name' }.value} #{ec2_volume.size}GB #{instance.public_ip_address} #{attachment.device.to_s}"
    end

    def other_details
      i = instance
      a = {
        architecture: i.architecture.to_s,
        kernel_id: i.kernel_id,
        virtualization_type: i.virtualization_type.to_s,
      }
      a[:ramdisk_id] = i.ramdisk_id if i.ramdisk_id
      o = []
      a.each_pair do |k,v|
        o << "#{k.to_s}=#{v.to_s}"
      end
      o.join('; ')
    end

    def current_snapshot_name
      "#{VfSnapshots.current_time_string} #{name}"
    end

    def create_snapshot
      desc = current_snapshot_name
      snapshot = ec2_volume.create_snapshot( description: desc )
    rescue Aws::EC2::Errors::ConcurrentSnapshotLimitExceeded
      VfSnapnshots::verbose Rainbow("\nSnapshot in progress, can't start another yet: #{desc}").red
    end

    def most_recent_snapshot
      snapshots.first
    end

    def most_recent_snapshot_date
      most_recent_snapshot.start_time rescue 'NEVER'
    end

    def recent_snapshot_exists?(since=Time.now-Config.recent_timespan_in_seconds)
      mrsd = most_recent_snapshot_date
      return false if mrsd.is_a?(String) # crap, it's NEVER!
      mrsd >= since
    end

  end

end
