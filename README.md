# VfSnapshots

This gem provides a command, 'vf-snapshots', that can ensure there are up to date snapshots of all active volumes in any number of AWS accounts.  The configuration data lives in /etc/vf-snapshots.yml, and there is an example config in config/vf-snapshots.yml.example.

The envisioned use is to have two cronjobs, one for *create* and a second one, some time later, for *verify*.  AWS sometimes can take a little while to complete a snapshot.

## Commands:

### create

Creates new snapshots of all volumes currently mounted on running instances within the accounts specified in the config file.  Can take an additional option, `--dry-run`, which skips the actual snapshot creation step.

_example_: `vf-snapshots create --verbose --dry-run`

### verify

Command confirms that there are recent snapshots for all volumes.  'Recent' is presently hardcoded as 'within the past 24 hours.'  The `verify` command takes an `--emails` option which will override the recipients specified in the configuration file.  It also takes a `--no-emails` option to suppress email output.

_example_: `vf-snapshots verify --verbose --emails=someone@soewhere.com,someoneelse@somewhereelse.com,noone@nowhere.com`

As seen in the examples above, both 'create' and 'verify' commands take a --verbose option which outputs lots of stuff.  A --config option can also be passed if you wish to use or test a config file in a non-standard location.

### show-snapshots

### clone-instance

Pass --account and --name.  This only works on EBS backed instances, but it should make new volumes for your snapshots, reattach those volumes, and fire up a new instance in the correct region.  It will use the newest available snapshots unless you use the snapshot-filter option, which allows you to choose a specfic snapshot set to use.

### prune

Nuke old snapshots.  Takes some options.  --keep=x is the number of recent snapshots to keep.  Defauts to 10.
Pass --keep-monthly=x to keep x snapshots from the first of the month.  Defauts to 3.

### test-email

Tests the emailing subsystem.  An --emails option can be provided; it will override the settings in the configuration file.

Example: `vf-snapshots test_email --emails=jon@jms-audioware.com`

## Installation

1. Clone the repo: `git clone https://github.com/vertfin/vf-snapshots.git`
2. Build the gem: `gem build vf-snapshots.gemspec`
3. Install the gem, probably as root: `sudo gem install --local vf-snapshots-x.y.z.gem`
4. Cron it up and have a cocktail.

## Contributing

1. Fork it ( https://github.com/vertfin/vf-snapshots/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## IAM Profile

Here's an IAM profile with enough perms for this all to work.

{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:AttachVolume",
                "ec2:CreateImage",
                "ec2:CreateSnapshot",
                "ec2:CreateVolume",
                "ec2:CreateTags",
                "ec2:DeleteSnapshot",
                "ec2:DeleteTags",
                "ec2:DeregisterImage",
                "ec2:DescribeInstanceAttribute",
                "ec2:DescribeInstanceStatus",
                "ec2:DescribeInstances",
                "ec2:DescribeImages",
                "ec2:DescribeSnapshotAttribute",
                "ec2:ModifySnapshotAttribute",
                "ec2:DescribeSnapshots",
                "ec2:DescribeTags",
                "ec2:DescribeVolumeAttribute",
                "ec2:DescribeVolumeStatus",
                "ec2:DescribeVolumes",
                "ec2:RegisterImage",
                "ec2:RunInstances"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}

Here's an IAM profile with minimal perms for the backup account.

{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:CopySnapshot",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                # "ec2:DeleteSnapshot" # for pruning, you don't want this perm on main account!
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
