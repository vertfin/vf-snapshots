class Volume

  SECONDS_IN_AN_HOUR = 60*60
  attr_accessor :ec2
  attr_accessor :volume, :instance, :attachment

  def _get_snapshots
    AWS.memoize do
      @snapshots ||= ec2.snapshots.filter( 'volume-id', volume.id )
        .filter( 'status', 'completed' )
        .sort { |a,b| b.start_time <=> a.start_time }
    end
  end

  public
  def initialize ec2, volume
    @ec2 = ec2
    @volume = volume
    # we'll only get here with volumes that have ONE attachment
    volume.attachments.each do |attachment|
      @attachment = attachment
      @instance = attachment.instance
    end
  end

  def name
    "#{instance.id} #{instance.tags.to_h['Name']} #{volume.size}GB #{instance.public_ip_address} #{attachment.device.to_s}"
  end

  def current_snapshot_name
    "#{Date.today.to_s} #{name}"
  end

  def create_snapshot
    volume.create_snapshot(current_snapshot_name)
  end

  def most_recent_snapshot_date
    _get_snapshots
    @snapshots.first.start_time rescue 'NEVER'
  end

  def recent_snapshot_exists?(since=Time.now-25*SECONDS_IN_AN_HOUR)
    mrsd = most_recent_snapshot_date
    return false if mrsd.is_a?(String) # crap, it's NEVER!
    mrsd >= since
  end

end
