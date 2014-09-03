# VfSnapshots

This gem provides a command, 'vf-snapshots', that can ensure there are up to date snapshots of all active volumes in any number of AWS accounts.  The configuration data lives in /etc/vf-snapshots.yml, and there is an example config in config/vf-snapshots.yml.example.

The envisioned use is to have two cronjobs, one for *create* and a second one, some time later, for *verify*.  AWS sometimes can take a little while to complete a snapshot.

## Commands:

### create

Creates new snapshots of all volumes currently mounted on running instances within the accounts specified in the config file.  Can take an addition option, `--dry-run`, which skips the actual snapshot creation step.

_example_: `vf-snapshots create --verbose --dry-run`

### verify

Command confirms that there are recent snapshots for all volumes.  'Recent' is presently hardcoded as 'within the past 24 hours.'  The `verify` command takes an `--emails` option which will override the recipients specified in the configuration file.  It also takes a `--no-emails` option to suppress email output.

_example_: `vf-snapshots verify --verbose --emails=someone@soewhere.com,someoneelse@somewhereelse.com,noone@nowhere.com`

As seen in the examples above, both 'create' and 'verify' commands take a --verbose option which outputs lots of stuff.  A --config option can also be passed if you wish to use or test a config file in a non-standard location.

### show-snapshots

### clone-instance

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

## TODO: pruning

