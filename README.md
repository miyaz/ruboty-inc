# Ruboty::Inc
incident viewer for Sm@rtDB

## Usage

```ruby
# Gemfile
gem 'ruboty-inc', :git => 'git://github.com/miyaz/ruboty-inc.git'
```

## ChatCommand
```
popy inc assgin count
popy inc change status
```

## ENV
```
RUBOTY_SDB_USER         - Sm@rtDB Account's username
RUBOTY_SDB_PASS         - Sm@rtDB Account's password
RUBOTY_SDB_URL          - Sm@rtDB URL
RUBOTY_ISE_AUTH_PATH    - Path to Get INSUITE session key (optional)
RUBOTY_SDB_AUTH_PATH    - Path to Get Sm@rtDB session key
RUBOTY_INC_SKIP_STATUS  - Status to skipping during count
RUBOTY_INC_SKIP_STATUS2 - Special Status to skipping during count
SLACK_API_TOKEN         - Send Message using Slack API Token for Labeling Linkname
SLACK_USERNAME          - Send Message using this Username
```
