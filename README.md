# Influx - Import CSV files to Mastodon

This Action will help you import CSV files to Mastodon, including:

* Follows
* Mutes
* Account blocks
* Lists
* Bookmarks
* Domain blocks

We (me and the script) try our best to auto-detect the import file type so you don't have to specify or care. The import is then performed using the Mastodon API and an Access Token.

## Documentation

Here's how you'd import a singular file if your account is on the dataplatform.social Mastodon instance.

```yaml
- name: Import CSV to Mastodon
  uses: potatoqualitee/influx@v1
    with:
        server: dataplatform.social
        filepath: ./follows.csv
    env:
        ACCESS_TOKEN: "${{ secrets.ACCESS_TOKEN }}"
```

If you have a ton of entries to follow/bookmark/ban, note that Mastodon limits API calls to 300 per 5 minutes, which averages 1 second so each call will have a delay of one second. Since GitHub Actions have a 60 minute max, this means that you can only import a max of 3600 items, minus overhead time.

If you're doing a variety of imports (follows, bookmarks, etc), you can dedicate one job per import which can help speed things up if you need.

# Usage

## Pre-requisites

### Get a Mastodon Bearer Token

A Mastodon token is required for this Action to work. Fortuantely, it's very easy to get one.

Go to your Mastodon profile/client/webpage and click Preferences -> Development -> New Application -> Application name: Whatever you like, I named mine Imports -> Limit Permissions (optional) -> Submit

> **Note**
>
> If you limit your permissions too much when you create the app, you may need to recreate it. I was too strict with my permissions and it _looked_ like I could edit them but the edit is like a secondary scope

Click new application link -> Your access token

### Add GitHub Secrets

Once you have your authentication information, you will need to them to your [repository secrets](https://docs.github.com/en/codespaces/managing-codespaces-for-your-organization/managing-encrypted-secrets-for-your-repository-and-organization-for-github-codespaces#adding-secrets-for-a-repository).

I named my secret `TOKEN`. You can modify the names, though you must ensure that your environmental variables are named appropriately, as seen in the sample code.

### Create workflows

Finally, create a workflow `.yml` file in your repositories `.github/workflows` directory. An [example workflow](#example-workflow) is available below. For more information, reference the GitHub Help Documentation for [Creating a workflow file](https://help.github.com/en/articles/configuring-a-workflow#creating-a-workflow-file).

## Inputs

* `server` - Your Mastodon server. If you are dbatools@dataplatform.social, this would be dataplatform.social.
* `file-path` - The path to the CSV file. Accepts one or many files, directory paths and even web addresses to csv files or zips.
* `type` - The type of file. Not required unless the script can't figure it out.
* `recurse` - When specifying a directory, recurse. Defaults to false.
* `verbose` - Show verbose output. Defaults to true.

## Outputs

None

### Example workflows

Use the `Exodus` action to find mastodon addresses in your follows and followers, then import them each night at midnight.

Note that if any of your follows or followers have been previously blocked on Mastodon, they will be skipped.

```yaml
name: Auto-Twitter Import
on:
  workflow_dispatch:
  schedule:
    - cron: "0 0 * * *"
jobs:
  export-import:
    runs-on: ubuntu-latest
    steps:

    - name: Check Twitter friends for Maston accounts
      uses: potatoqualitee/exodus@v1
      id: export
      with:
        my: follows, followers
      env:
        BLUEBIRDPS_API_KEY: "${{ secrets.BLUEBIRDPS_API_KEY }}"
        BLUEBIRDPS_API_SECRET: "${{ secrets.BLUEBIRDPS_API_SECRET }}"
        BLUEBIRDPS_ACCESS_TOKEN: "${{ secrets.BLUEBIRDPS_ACCESS_TOKEN }}"
        BLUEBIRDPS_ACCESS_TOKEN_SECRET: "${{ secrets.BLUEBIRDPS_ACCESS_TOKEN_SECRET }}"

    - name: Import the results
      uses: potatoqualitee/influx@v1
      id: import
      with:
        server: tech.lgbt
        file-path: ${{ steps.export.outputs.mastodon-csv-filepath }}
      env:
        ACCESS_TOKEN: "${{ secrets.ACCESS_TOKEN }}"
```

## How are the import types detected?

I looked at what the web exporter generated and crossed my fingers that it used a standard. Here's how I determine type:

| File Type | Location | Looks like |
| --- | --- | --- |
| Follows | /settings/exports/follows.csv | Columns named "Account address", "Show boosts" and maybe "Notify on new posts" ", "Languages" |
| Lists | /settings/exports/lists.csv | No header, two columns formatted like: listname, user@domain.tld |
| Blocked Accounts | /settings/exports/blocks.csv | No heading, only 1 column formatted like: user@domain.tld |
| Mutes | /settings/exports/mutes.csv | Columns named "Account address", "Hide notifications" |
| Blocked Domains | /settings/exports/domain_blocks.csv | Just a server name, no http, no second column |
| Bookmarks | /settings/exports/bookmarks.csv | Just one column, https and the word statuses |


### Details

Here's some extra examples for the inputs.

| Input | Example | Another Example | And Another
| --- | --- | --- | --- |
| server | dataplatform.social | dbatools@dataplatform.social | https://dataplatform.social
| file-path | /tmp/follows.csv | follows.csv, blocked.csv | https://funbucket.dev/follows.csv

### Want to run this locally?

Just add your `$env:ACCESS_TOKEN` environmental variables to your `$profile` and reload, clone the repo, change directories, modify this command and run.

```powershell
./main.ps1 -Server yourinstance.tld -FilePath C:\temp\csvdir, https://pubs.com/northwind/csvs.zip
```

## A quick note

Some Mastodon addresses are not resolving properly but that should be fixed soon. It's mostly Mastodon with three-part addresses and unexpected characters in their bio. This impacted 3 accounts of 100 on my own tests.

Also, the following pre-check mostly works and I'll figure that out later. Right now, it just means that there may be additional, unnecessary calls to the server, but it does't impact expected functionality.

## Contributing
Pull requests are welcome!

I think Exodus and Influx could benefit from JavaScript integration to Mastadon, maybe? Making it easy to pick and choose who to import.

## TODO
You tell me! I'm open to suggestions.

## License
The scripts and documentation in this project are released under the [MIT License](LICENSE)