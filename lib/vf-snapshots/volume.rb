module VfSnapshots
  class Volume

    attr_accessor :ec2, :ec2_volume, :instance, :attachment

    def snapshots
      return @snapshots if @snapshots
      AWS.memoize do
        @snapshots = ec2.snapshots.filter( 'volume-id', ec2_volume.id )
          .filter( 'status', 'completed' )
          .sort { |a,b| b.start_time <=> a.start_time }
      end
      if filter = Config.options[:snapshot_filter]
        @snapshots = @snapshots.select { |s| s.description.to_s.index(filter)==0 }
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
        @instance = attachment.instance
      end
    end

    def name
      "#{instance.id} #{instance.tags.to_h['Name']} #{ec2_volume.size}GB #{instance.public_ip_address} #{attachment.device.to_s}"
    end

    def current_snapshot_name
      "#{VfSnapshots.current_time_string} #{name}"
    end

    def create_snapshot
      snapshot = ec2_volume.create_snapshot(current_snapshot_name)
      snapshot.tags['Instance-Name']=instance.tags.to_h['Name']
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
