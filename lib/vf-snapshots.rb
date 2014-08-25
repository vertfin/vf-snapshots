# encoding: UTF-8

require 'vf-snapshots/version'

require 'thor'
require 'aws'
require 'yaml'
require 'rainbow'
require 'pony'

require 'vf-snapshots/volume'

module VfSnapshots

  class Snapshots < Thor

    no_commands do
      def verbose message
        puts message if options[:verbose]
      end

      def config
        YAML.load_file(options[:config] || "/etc/vf-snapshots.yml")
      end

      def for_each_aws_account
        config[:aws_accounts].each_pair do |account, credentials|
          verbose "\nSetting account to #{account}"
          AWS.memoize do
            ec2 = AWS::EC2.new( credentials )
            load_volumes account, ec2
            yield account, ec2
          end
        end
      end

      def load_volumes account, ec2
        @volumes = []
        verbose Rainbow("Loading volumes for #{account}").green
        ec2.instances.filter('instance-state-name', 'running').each do |instance|
          verbose Rainbow("  Checking #{account} #{instance.id} for volumes").blue
          ec2.volumes.filter('attachment.instance-id', instance.id ).each do |volume|
            case volume.attachments.count
            when 0
              # this volume not attached to anything, not snapshoting
            when 1
              volume.attachments.each do |attachment|
                verbose Rainbow("    adding #{volume.size.to_s}GB volume mounted at #{attachment.device.to_s}").white
                instance = attachment.instance
                @volumes << Volume.new(ec2, volume)
              end  
            else
              raise "A volume has more than one attachment, that is impossible, my worldview has been shattered, and I am quitting now."
            end
          end
        end
        verbose "\n"
      end

      def send_email subject, body
        verbose "\n\nEMAIL SUBJECT: #{subject}"
        verbose body
        verbose "\n"

        emails = options[:emails].to_s.split(',')

        if emails.length > 0          
          emails.each do |email|
            verbose "Sending mail to: #{email}"          
            opts = config[:mail].merge({:from => Config[:mail][:from], :to => email, :subject => subject, :body => body})
            Pony.mail(opts)
          end
        end
      end
    end

    desc 'create', 'create new snapshots of all mounted volumes in the configured AWS accounts'  
    option :emails
    option :config
    option :dry_run, :type => :boolean
    option :verbose, :type => :boolean
    def create
      for_each_aws_account do |account, ec2|
        @volumes.each do |volume|
          message = "Creating #{volume.current_snapshot_name}"
          if options[:dry_run]
            verbose "#{message} (dry run, not really creating)"
          else
            verbose message
            volume.create_snapshot
          end
        end
      end
      verbose "\n"
    end

    desc 'verify', 'verify recent snapshots for all mounted volumes in the configured AWS accounts'
    option :emails
    option :config
    option :verbose, :type => :boolean
    def verify
      messages = []
      subject = 'AWS Snapshots'
      body = "Hi,\n\n"
      volume_count = 0
      volume_count_with_recent_snapshot = 0
      for_each_aws_account do |account, ec2|
        volume_count += @volumes.count
        @volumes.each do |volume|
          vmsg = "Verifying current snapshot for #{volume.name}"
          if volume.recent_snapshot_exists?
            volume_count_with_recent_snapshot += 1
            vmsg = Rainbow("✓ #{vmsg}").green
            verbose vmsg
          else
            vmsg = Rainbow("X #{account}: FAILURE #{vmsg}; most recent was #{volume.most_recent_snapshot_date.to_s}").red
            messages << "#{account}: No recent snapshot found for #{volume.name}, most recent was #{volume.most_recent_snapshot_date.to_s}"
            puts vmsg
          end
        end     
      end
      if messages.empty?
        body << "Everything is fine, there are current snapshots for #{volume_count} volumes.\n\n"

        subject << ' completed OK'
        body << "Thanks,\n\n"
        body << "The friendly AWS Snapshotter service."
      else
        subject << ' -- ACHTUNG!!! THERE ARE PROBLEMS!!!!!'
        body << "There should be recent snapshots for #{volume_count} volumes, and there #{volume_count_with_recent_snapshot == 1 ? 'was' : 'were'} only #{volume_count_with_recent_snapshot}.  Here are some more details:\n\n"
        body << messages.join("\n")
        body << "\n\n"
        body << "Sorry for the bad news,\n\n"
        body << "The concerned AWS Snapshotter service."
      end

      send_email subject, body
    end

    desc 'test_email', 'send a test email, you will want to pass the emails=xxx,yyy,zzz option for this to make any sense'
    option :emails
    option :verbose, :type => :boolean
    def test_email
      puts Rainbow("\nThis command doesn't really make a lot of sense unless you provide some emails via --emails=xxx,yyy,zzz!\n").red unless options[:emails]
      send_email 'This is a test email', "\n\nThis is a test email to confirm the AwsSnapshot gem bin can send email.\n"
      verbose "\n"
    end

  end

end
