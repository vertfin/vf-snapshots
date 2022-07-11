module VfSnapshots
  class Config

    class << self
      attr_accessor :options
    end

    def self.config
      YAML.load_file(options && options[:config] || "/etc/vf-snapshots.yml")
    end

    def self.mail
      config[:mail]
    end

    def self.email_recipients
      ( @options[:emails] || mail[:recipients] ).to_s.split(',')
    end

    def self.accounts
      config[:accounts]
    end

    def self.recent_timespan_in_seconds
      seconds_in_an_hour = 60*60
      25*seconds_in_an_hour
    end

    def self.subnet_id
      config[:subnet_id]
    end

    def self.security_group_id
      config[:security_group_id]
    end

  end

end
