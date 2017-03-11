Deken Search Server
===================

this is a small standalone python server with the task of answering
search queries send from Pd's 'deken' search.


# Why?
So far, deken queries are answered directly by the plone portal
at puredata.info.
So why do we need a standalone server?

## Using puredata.info

### pros
- written in python
- all the deken packages are uploaded directly to the plone portal,
  so it is much more easy to query the internal database there
- no caching problems (as we always work on 'the' data)

### cons
- its pretty slow
- right now, the search script is run as an in-database-script
  (rather than a filesystem-based product), which means that it
  lacks a lot of priviliges (like filesystem access)
  - python2.6! not really possible to upgrade


## Using a dedicated server

### pros
- fast (only a single task)
- written in whatever we like (python3!)
- if things go wrong, we don't take the entire portal down (privilege separation)

### cons
- caching: don't serve outdated information

# How?

- fetch data from puredata.info
- store in in a local "database"
- answer queries

# Fetch data

- library search
 + "periodicially" (e.g. every hour) run a search-all on puredata.info
- object search
 + "periodicially" get a list of all -metainfo.txt files from puredata.info,
 + sync/download/delete the files from the server with a local fs (mirror)

## Implementation: filesystem based
my original idea was to have an external cron-job that would run 'wget' or similar.
an inotify thread in the Server would then wake up whenever some files changed,
and update the internal data representation

## Implementation: python-requests
otoh, we could do everything within python (using the 'requests' module),
so we wouldn't need any filesystem access.

we could even implement a 'push' functionality, where puredata.info notified the deken-server
whenever somebody uploaded a file.
this would
- lower the load on puredata.info (no need to run full searches when nothing has changed)
- make data available almost instantanious

# Store data

## Implementation: dict
the first idea was to just use python's `dict` class.

## Implementation: sqlite3
using a proper database would make it much easier to do searches
(eg. with wildcard support).

it might also be faster (though i doubt that we have enough data tso this actually matters).


if *data fetch* was implemented within the server, we could even use a memory-only database
(no filesystem access required)

one drawback is that we have to take care that the SQL-query cannot be exploited.
(sanitize the search-string first!)
