# encoding: UTF-8

require 'vf-snapshots/version'

require 'thor'
require 'aws'
require 'yaml'
require 'rainbow'
require 'pony'

require 'vf-snapshots/config'
require 'vf-snapshots/account'
require 'vf-snapshots/instance'
require 'vf-snapshots/volume'

module VfSnapshots

  def self.verbose message
    puts message if Config.options[:verbose]
  end

  def self.current_time_string
    Time.now.strftime('%Y%m%d%H%M%S')
  end

  class Snapshots < Thor

    no_commands do

      def send_email subject, body

        return if options[:no_emails]

        VfSnapshots::verbose "\n\nEMAIL SUBJECT: #{subject}"
        VfSnapshots::verbose body
        VfSnapshots::verbose "\n"

        emails = VfSnapshots::Config.email_recipients
        unless emails.empty?
          emails.each do |email|
            VfSnapshots::verbose "Sending mail to: #{email}" 
            opts = {:from => VfSnapshots::Config.mail[:from], :to => email, :subject => subject, :body => body, :via => VfSnapshots::Config.mail[:via], :via_options => VfSnapshots::Config.mail[:via_options]}
            Pony.mail(opts)
          end
        end

      end
    end

    desc 'create', 'create new snapshots of all mounted volumes in the configured AWS accounts'  
    option :config, :desc => 'alternate file for config, default is /etc/vf-snapshots.yml.  example file is in gem source at config/vf-snapshots.yml.example'
    option :dry_run, :type => :boolean, :desc => "don't actually create a snapshot, but do everything else"
    option :verbose, :type => :boolean, :desc => 'tell me more stuff!'
    def create
      VfSnapshots::Config.options = options
      Account.for_each do |account, ec2|
        account.volumes.each do |volume|
          message = "Creating #{volume.current_snapshot_name}"
          if options[:dry_run]
            VfSnapshots::verbose "#{message} (dry run, not really creating)"
          else
            VfSnapshots::verbose message
            volume.create_snapshot
          end
        end
      end
      VfSnapshots::verbose "\n"
    end

    desc 'verify', 'verify recent snapshots for all mounted volumes in the configured AWS accounts'
    option :emails, :desc => 'comma-separated list of email recipients of a status report'
    option :no_emails, :type => :boolean, :desc => 'suppress email output'
    option :config, :desc => 'alternate file for config, default is /etc/vf-snapshots.yml.  example file is in gem source at config/vf-snapshots.yml.example'
    option :verbose, :type => :boolean, :desc => 'tell me more stuff!'
    def verify
      VfSnapshots::Config.options = options
      messages = []
      subject = 'AWS Snapshots'
      body = "Hi,\n\n"
      volume_count = 0
      volume_count_with_recent_snapshot = 0
      Account.for_each do |account|
        AWS.memoize do
          volume_count += account.volumes.count
          account.volumes.each do |volume|
            vmsg = "Verifying current snapshot for #{volume.name}"
            if volume.recent_snapshot_exists?
              volume_count_with_recent_snapshot += 1
              vmsg = Rainbow("✓ #{vmsg}").green
              VfSnapshots::verbose vmsg
            else
              vmsg = Rainbow("X #{account.name}: FAILURE #{vmsg}; most recent was #{volume.most_recent_snapshot_date.to_s}").red
              messages << "  #{account.name}: No recent snapshot found for #{volume.name}, most recent was #{volume.most_recent_snapshot_date.to_s}"
              puts vmsg
            end
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

    desc 'show-accounts', 'shows the currently configured accounts'
    def show_accounts
      puts "Accounts"
      puts "--------"
      puts Config.accounts.keys.join("\n")
      puts
    end

    desc 'show-snapshots', 'show available snapshots for an instance'
    option :account, :required => true, :desc => 'show snapshots for an instance'
    option :name, :required => true, :desc => 'instance name'
    option :snapshot_filter, :desc => "beginning snapshot desc to use, partial is ok, i.e. '2014090412', use 'show-snapshots' command to find"

    def show_snapshots
      VfSnapshots::Config.options = options
      account = Account.new(options[:account])
      instance = account.find_instance_by_name(options[:name])
      puts "ID\t\t#{Rainbow('START TIME').blue}\t\t#{Rainbow('DESC').yellow}"
      instance.volumes.each do |volume|
        volume.snapshots.each do |snapshot|
          puts "#{snapshot.id}\t#{Rainbow(snapshot.start_time).blue}\t#{Rainbow(snapshot.description).yellow}"
        end
      end

    end

    desc 'clone-instance', 'clone a instance and its volumes'
    option :verbose, :type => :boolean, :default => true
    option :account, :required => true, :desc => 'account name, use show-accounts to view all configured accounts'
    option :name, :required => true, :desc => 'instance name'
    option :snapshot_filter, :desc => "beginning snapshot desc to use, partial is ok, i.e. '2014090412', use 'show-snapshots' command to find"
    option :date
    def clone_instance
      VfSnapshots::Config.options = options
      account = Account.new(options[:account])
      instance = account.find_instance_by_name(options[:name])
      instance.clone
    end

    desc 'test_email', 'send a test email'
    option :emails, :desc => 'comma-separated list of email recipients of the test.'
    option :no_emails, :type => :boolean, :desc => 'suppress email output'

    option :verbose, :type => :boolean
    def test_email
      VfSnapshots::Config.options = options
      send_email 'This is a test email', "\n\nThis is a test email to confirm the AwsSnapshot gem bin can send email.\n"
      VfSnapshots::verbose "\n"
    end

  end

end
