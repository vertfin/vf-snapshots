# encoding: utf-8

require 'vf-snapshots/version'

require 'thor'
require 'aws-sdk'
require 'yaml'
require 'rainbow'
require 'pony'
require 'byebug'

require 'vf-snapshots/config'
require 'vf-snapshots/account'
require 'vf-snapshots/instance'
require 'vf-snapshots/volume'
require 'vf-snapshots/backup'

module VfSnapshots

  # a regex to detect snapshots that originated with us
  DESC_REGEX = /\d{14}\ i-/
  DEFAULT_BACKUP_DAYS = 7

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
    option :account, :desc => 'specify account'
    def create
      VfSnapshots::Config.options = options
      Account.for_each(options[:account]) do |account, ec2|
        begin
          account.volumes.each do |volume|
            message = "Creating #{volume.current_snapshot_name}"
            if options[:dry_run]
              VfSnapshots::verbose "#{message} (dry run, not really creating)"
            else
              VfSnapshots::verbose message
              volume.create_snapshot
            end
          end
        rescue Aws::EC2::Errors::AuthFailure
          vmsg = Rainbow("X #{account.name}: INVALID AUTHENTICATION").magenta
          puts vmsg
        end
      end
      VfSnapshots::verbose "\n"
    end

    desc 'verify', 'verify recent snapshots for all mounted volumes in the configured AWS accounts'
    option :emails, :desc => 'comma-separated list of email recipients of a status report'
    option :no_emails, :type => :boolean, :desc => 'suppress email output'
    option :config, :desc => 'alternate file for config, default is /etc/vf-snapshots.yml.  example file is in gem source at config/vf-snapshots.yml.example'
    option :verbose, :type => :boolean, :desc => 'tell me more stuff!'
    option :account, :desc => 'specify account'
    def verify
      begin
        VfSnapshots::Config.options = options
        messages = []
        subject = 'AWS Snapshots'
        body = "Hi,\n\n"
        details = ''
        volume_count = 0
        volume_count_with_recent_snapshot = 0
        Account.for_each(options[:account]) do |account|
          begin
            details << "\nAccount: #{account.name}\n"
            #Aws.memoize do
            volume_count += account.volumes.count
            account.volumes.each do |volume|
              vmsg = "Verifying current snapshot for #{volume.name}"
              if volume.recent_snapshot_exists?
                volume_count_with_recent_snapshot += 1
                vmsg = Rainbow("✓ #{vmsg}").green
                VfSnapshots::verbose vmsg
                details << "  ok: #{volume.name}\n"
                details << "      #{volume.other_details}\n"
              else
                vmsg = Rainbow("X #{account.name}: FAILURE #{vmsg}; most recent was #{volume.most_recent_snapshot_date.to_s}").red
                messages << "  #{account.name}: No recent snapshot found for #{volume.name}, most recent was #{volume.most_recent_snapshot_date.to_s}"
                details << "  XX: #{volume.name}\n"
                puts vmsg
              end
            end
            #end
          rescue Aws::EC2::Errors::AuthFailure
            puts "Error: #{$!}"
            details << "  INVALID AUTHENTICATION\n"
            messages << "  #{account.name}: AWS Authentication Error"
            vmsg = Rainbow("X #{account.name}: INVALID AUTHENTICATION").magenta
            puts vmsg
          end
        end
        if messages.empty?
          body << "Everything is fine, there are current snapshots for #{volume_count} volumes.\n"

          subject << ' completed OK'
          body << details + "\n\n"
          body << "Thanks,\n\n"
          body << "The friendly AWS Snapshotter service.\n\n"
        else
          subject << ' -- ACHTUNG!!! THERE ARE PROBLEMS!!!!!'
          body << "There should be recent snapshots for #{volume_count} volumes, and there #{volume_count_with_recent_snapshot == 1 ? 'was' : 'were'} only #{volume_count_with_recent_snapshot}.  Here are some more details:\n\n"
          body << messages.join("\n")
          body << "\n"
          body << details + "\n\n"
          body << "Sorry for the bad news,\n\n"
          body << "The concerned AWS Snapshotter service.\n\n"
        end
      rescue => exception
        puts "Error: #{$!}"
        puts exception.backtrace
        subject = 'AWS Snapshots -- DANGER WILL ROBINSON!!!'
        body = "Something has gone really wrong here.\n\n"
        body << $!.inspect
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

    desc 'show-instances', 'show available instance names for an account'
    option :account, :required => true, :desc => 'specify account'
    def show_instances
      VfSnapshots::Config.options = options
      Account.for_each(options[:account]) do |account|
        begin
          # printf "%-20s %s\n", value_name, value
          fields = {
            'Instance ID' => 'instance.id',
            'Status'      => 'instance.state.name',
            'Name'        => "instance.tags.select{|tag| tag.key == 'Name'}.first.value",
            'Public IP'   => 'instance.public_ip_address',
            'Private IP'  => 'instance.private_ip_address',
          }
          puts "Account: #{account.name}"
          puts
          output = []
          widths = []
          account.ec2.instances.each do |instance|
            line = []
            fields.values.collect { |f| eval(f) }.each_with_index do |f,idx|
              widths[idx] = [ widths[idx].to_i, f.respond_to?(:length) ? f.length : 20 ].max
              line << f
            end
            output << line
          end

          div = ''
          widths.each do |width|
            div << '-'*width
            div << ' '
          end
          widths = widths.collect { |w| "%-#{w.to_s}s" }.join(' ') + "\n"
          printf widths, *fields.keys
          puts div
          output.each do |line|
            printf widths, *line
          end
          puts

        rescue Aws::EC2::Errors::AuthFailure
          puts "INVALID AUTHENTICATION"
          puts
        end
      end
    end

    desc 'show-snapshots', 'show available snapshots for an instance'
    option :account, :required => true, :desc => 'show snapshots for an instance'
    option :name, :required => true, :desc => 'instance name'
    option :snapshot_filter, :desc => "beginning snapshot desc to use, partial is ok, i.e. '2014090412', use 'show-snapshots' command to find"
    def show_snapshots
      VfSnapshots::Config.options = options
      account = Account.new(options)
      instance = account.find_instance_by_name(options[:name])

#          widths = widths.collect { |w| "%-#{w.to_s}s" }.join(' ') + "\n"
#          printf widths, *fields.keys
      widths = [ 20,20,20 ]
      data = []
      instance.volumes.each do |volume|
        volume.snapshots.each do |snapshot|
          line = [ snapshot.id, Rainbow(snapshot.start_time).blue, Rainbow(snapshot.description).yellow ]
          data << line
          line.each_with_index do |l,idx|
            widths[idx] = [ widths[idx], l.length ].max
          end
        end
      end

      printf "\n%-#{widths[0].to_s}s %-#{widths[1].to_s}s %-#{widths[2].to_s}s\n", 'ID', Rainbow('START TIME').blue, Rainbow('DESC').yellow

      data.each do |line|
        printf "%-#{widths[0].to_s}s %-#{widths[1].to_s}s %-#{widths[2].to_s}s\n", *line
      end
      puts
    end

    desc 'clone-instance', 'clone a instance and its volumes'
    option :verbose, :type => :boolean, :default => true
    option :account, :required => true, :desc => 'account name, use show-accounts to view all configured accounts'
    option :name, :required => true, :desc => 'instance name'
    option :snapshot_filter, :desc => "beginning snapshot desc to use, partial is ok, i.e. '2014090412', use 'show-snapshots' command to find"
    option :date
    option :security_group_id, :required => false, :desc => "optional security group id override, useful when moving an instance into a vpc.  can be 'none' to not specify at all."
    option :subnet_id, :required => false, :desc => "optional subnet id, useful when moving an instance into a vpc"

    def clone_instance
      VfSnapshots::Config.options = options
      account = Account.new(options)
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

    desc 'prune', 'prune old snapshots'
    option :keep, :desc => 'number of old snapshots to keep, not including monthlies', :default => DEFAULT_BACKUP_DAYS
    option :keep_monthly, :desc => 'number of old snapshots to keep from the 1st of the month', :default => 3
    option :dry_run, :type => :boolean, :desc => "don't actually prune anything, just tell us what would be deleted"
    option :old_format, :type => :boolean, :desc => "also find snapshots using the original format.  this option will be removed when all of the olds are gone"
    option :verbose, :type => :boolean
    def prune
      VfSnapshots::Config.options = options
      total_deleted = {}
      Account.for_each(options[:account]) do |account|
        begin
          total_deleted[account.name] = 0
          VfSnapshots::verbose "\n"
          VfSnapshots::verbose "ACCOUNT: #{account.name}"
          account.volumes.each do |volume|
            dailies = []
            monthlies = []
            volume.snapshots.each do |snapshot|
              # determine if this is 'our' snapshot
              # by checking for timestamp at start of desc.
              # TODO use a dedicated tag
              if (/^(\d{6})(\d{2})(\d{6})\s/ =~ snapshot.description) || (options[:old_format] && /^(\d{4})-(\d{2})-(\d{2})\s/ =~ snapshot.description)
                if $2 == '01' # we got a monthly
                  monthlies << snapshot
                else
                  dailies << snapshot
                end
              end
            end
            dailies.sort! { |a,b| b.description.slice(0,14) <=> a.description.slice(0,14) }
            monthlies.sort! { |a,b| b.description.slice(0,14) <=> a.description.slice(0,14) }
            tbe = dailies.slice(options[:keep].to_i,99999).to_a + monthlies.slice(options[:keep_monthly].to_i,99999).to_a

            VfSnapshots::verbose "#{volume.name} | #{tbe.length} for deletion"
            total_deleted[account.name] += tbe.length
            if options[:dry_run]
              VfSnapshots::verbose "Not deleting, --dry-run:"
              VfSnapshots::verbose tbe.collect(&:description).inspect
            else
              tbe.each do |s|
                begin
                  s.delete
                rescue
                  puts "Error deleting snapshot: #{$!}"
                end
              end
            end
          end
          VfSnapshots::verbose "Total account deletions: #{ total_deleted[account.name].to_s }"
        rescue Aws::EC2::Errors::AuthFailure
          vmsg = Rainbow("X #{account.name}: INVALID AUTHENTICATION").magenta
          puts vmsg
        end
      end
      VfSnapshots::verbose "\n"
      VfSnapshots::verbose "Total deletions: #{ total_deleted.values.inject{|sum,x| sum + x } }"
      VfSnapshots::verbose "\n"

    end

    desc 'show-orphans', 'show snapshots not associated with volumes'
    # option :old_format, :type => :boolean, :desc => "also find snapshots using the original format.  this option will be removed when all of the olds are gone"
    option :verbose, :type => :boolean
    option :account, :desc => 'account name, use show-accounts to view all configured accounts'
    option :delete, :type => :boolean
    def show_orphans
      VfSnapshots::Config.options = options
      orphans = []
      Account.for_each(options[:account]) do |account|
        begin
          VfSnapshots::verbose "\n"
          VfSnapshots::verbose "ACCOUNT: #{account.name}"
          # puts account.volumes.collect { |v| v.attachment.inspect }
          VfSnapshots::verbose "\nGetting all volumes for account, might be slow..."
          all_volume_ids = account.volumes.collect { |v| v.ec2_volume.id }
          VfSnapshots::verbose "All Volume IDs: #{all_volume_ids.inspect}"

          VfSnapshots::verbose "\nGetting all snapshots for account, might be slow..."
          all_snapshots = account.snapshots
          VfSnapshots::verbose "\nSnapshot count: #{all_snapshots.count}"

          VfSnapshots::verbose "\nFinding orphans..."
          orphan_snapshots = all_snapshots.select { |s| !all_volume_ids.include?(s.volume_id) }
          VfSnapshots::verbose "\nFound orphans (#{orphan_snapshots.length}), getting details.\n"
          results = []
          orphan_snapshots.each do |orphan_snapshot|
            results << {
                         snapshot: orphan_snapshot,
                         snapshot_id: orphan_snapshot.id,
                         #snapshot_name: orphan_snapshot.tags.to_h['Name'],
                         volume_id: orphan_snapshot.volume_id,
                         #volume_name: orphan_snapshot.volume.tags.to_h['Name']
                         start_date: orphan_snapshot.start_time.to_date,
            }
          end
          deleted_count = 0
          results.sort { |a,b| a[:volume_id] <=> b[:volume_id] }.each_with_index do |orphan_snapshot,idx|
            if options[:delete]
              begin
                orphan_snapshot[:snapshot].delete
                puts "[#{idx}] #{orphan_snapshot[:start_date]} DELETED volume_id:#{orphan_snapshot[:volume_id]} snapshot_id:#{orphan_snapshot[:snapshot_id]}"
                deleted_count += 1
              rescue
                puts "[#{idx}] #{orphan_snapshot[:start_date]} ERROR DELETING: volume_id:#{orphan_snapshot[:volume_id]} snapshot_id:#{orphan_snapshot[:snapshot_id]}"
                puts "[#{idx}] ERROR: #{$!}"
              end
            else
              puts "[#{idx}] #{orphan_snapshot[:start_date]} volume_id:#{orphan_snapshot[:volume_id]} snapshot_id:#{orphan_snapshot[:snapshot_id]}"
            end
          end

          puts
          puts "Total Snapshots: #{all_snapshots.length}"
          puts "Orphaned Snapshots: #{results.length}"
          puts "Deleted Snapshots: #{deleted_count}"
          puts

        rescue Aws::EC2::Errors::AuthFailure
          vmsg = Rainbow("X #{account.name}: INVALID AUTHENTICATION").magenta
          puts vmsg
        end
      end
      VfSnapshots::verbose "\n"

    end

    desc 'backup', 'sync snapshots with backup account, if provided'
    option :dry_run, :type => :boolean, :desc => 'just show the backup info'
    option :account, :desc => 'account name, use show-accounts to view all configured accounts'
    option :verbose, :type => :boolean, :desc => 'tell me more stuff!'
    def backup
      VfSnapshots::Config.options = options
      orphans = []
      Account.for_each(options[:account]) do |account|
        begin
          VfSnapshots::verbose "\n"
          VfSnapshots::verbose "ACCOUNT: #{account.name}"

          if account.has_backup?
            backup = Backup.new(account)
            missing = backup.enumerate_missing
            if options[:dry_run]
              VfSnapshots::verbose "Snapshots to backup: #{missing.length}"
              missing.each do |m|
                VfSnapshots::verbose "[#{idx+1} of #{missing.lenfth} #{m.description}"
              end
            else
              backup.copy_snapshots! missing unless options[:dry_run]
            end
          end

        rescue Aws::EC2::Errors::AuthFailure
          vmsg = Rainbow("X #{account.name}: INVALID AUTHENTICATION").magenta
          puts vmsg
        end
      end
      VfSnapshots::verbose "\n"

    end

    # at present backup prune casts a wide net, and deletes ALL snapshots
    # whose descriptions match the basic regex
    # on the backup account that are older than backup[:days].  be careful!
    desc 'backup-prune', 'prune backup account, if provided'
    option :dry_run, :type => :boolean, :desc => 'just show the backup snapshots to be pruned'
    option :account, :desc => 'account name, use show-accounts to view all configured accounts'
    option :verbose, :type => :boolean, :desc => 'tell me more stuff!'
    def backup_prune
      VfSnapshots::Config.options = options
      orphans = []
      Account.for_each(options[:account]) do |account|
        begin
          VfSnapshots::verbose "\n"
          VfSnapshots::verbose "ACCOUNT: #{account.name}"

          if account.has_backup?
            backup = Backup.new(account)
            prunees = backup.enumerate_snapshots_to_be_pruned
            VfSnapshots::verbose "SNAPSHOTS TO PRUNE: #{prunees.length}"
            if options[:dry_run]
              VfSnapshots::verbose "Snapshot backups to prune: #{prunees.length}"
              prunees.each_with_index do |snap,idx|
                VfSnapshots::verbose "[#{idx+1} of #{prunees.length}] #{snap.description}"
              end
            else
              backup.delete! prunees
            end
          end

        rescue Aws::EC2::Errors::AuthFailure
          vmsg = Rainbow("X #{account.name}: INVALID AUTHENTICATION").magenta
          puts vmsg
        end
      end
      VfSnapshots::verbose "\n"

    end

    # at present backup prune casts a wide net, and deletes ALL snapshots
    # whose descriptions match the basic regex
    # on the backup account that are older than backup[:days].  be careful!
    desc 'backup-tag', 'tag snapshots in backup account'
    option :account, :desc => 'account name, use show-accounts to view all configured accounts'
    option :verbose, :type => :boolean, :desc => 'tell me more stuff!'
    def backup_tag
      VfSnapshots::Config.options = options
      orphans = []
      Account.for_each(options[:account]) do |account|
        begin
          VfSnapshots::verbose "\n"
          VfSnapshots::verbose "ACCOUNT: #{account.name}"

          if account.has_backup?
            backup = Backup.new(account)
            backup.tag_accounts!
          end

        rescue Aws::EC2::Errors::AuthFailure
          vmsg = Rainbow("X #{account.name}: INVALID AUTHENTICATION").magenta
          puts vmsg
        end
      end
      VfSnapshots::verbose "\n"
    end

    desc 'version', 'show gem version number'
    def version
      puts "vf-snapshots version #{VfSnapshots::VERSION}"
    end

  end
end
