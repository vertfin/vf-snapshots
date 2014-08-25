# VfSnapshots

This gem provides a command, 'snapshots', that can ensure there are up to date snapshots of all active volumes in any number of AWS accounts.  The configuration data lives in /etc/snapshots.yml, and there is an example config in config/snapshots.yml.example.

The envisioned use is to have two cronjobs, one for *create* and a second one, some time later, for *verify*.  AWS sometimes can take a little while to complete a snapshot.

## Commands:

### create

Creates new snapshots of all volumes currently mounted on running instances within the accounts specified in the config file.  Can take an addition option, `--dry-run`, which skips the actual snapshot creation step.

_example_: `snapshots create --verbose --dry-run`

### verify

Command confirms that there are recent snapshots for all volumes.  'Recent' is presently hardcoded as 'within the past 24 hours.'  The `verify` command takes an `--emails` option.

_example_: `snapshots verify --verbose --emails=someone@soewhere.com,someoneelse@somewhereelse.com,noone@nowhere.com`

As seen in the examples above, both 'create' and 'verify' commands take a --verbose option which outputs lots of stuff.

### test_email

Tests the emailing subsystem.

Example: `snapshots test_email --emails=jon@jms-audioware.com`

## Contributing

1. Fork it ( https://github.com/[my-github-username]/snapshots/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## TODO: pruning

