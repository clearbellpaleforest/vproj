# Docs Pipeline

## How the wiki works

Every push to `git@snuffletron:vproj.git` triggers an automatic pipeline
that rebuilds the live documentation at
[https://wiki.newingtonamc.com/docs/vproj/](https://wiki.newingtonamc.com/docs/vproj/).

## Pipeline flow

```
git push snuffletron master
  → post-receive hook fires
    → /home/mkdocs/.tools/sync_docs.sh vproj
      → git archive HEAD doc/ | tar x
        → rsync into /home/mkdocs/vproj/docs/
          → mkdocs build --strict
            → /home/mkdocs/vproj/site/
              → served by nginx at wiki.newingtonamc.com/docs/vproj/
```

The entire build takes under 1 second.

## What gets published

Everything under `doc/` in this repository. The `mkdocs.yml` on snuffletron
(in `/home/mkdocs/vproj/`) controls navigation and site structure.

## Manual rebuild

If the hook fails or you need to test without pushing:

```bash
ssh snuffletron 'sudo -u mkdocs /home/mkdocs/.tools/sync_docs.sh vproj'
```

## Adding pages

1. Create a new `.md` file in `doc/`
2. SSH to snuffletron and add it to the `nav` section in `/home/mkdocs/vproj/mkdocs.yml`
3. Push to `snuffletron`

## Anchor links

MkDocs generates anchor IDs from headings by lowercasing and replacing spaces
with hyphens. When you change a heading, update any `#anchor` links that point
to it.

## Key distinction

- `doc/` in this repo → design docs, pipelined to the wiki
- `doc_manual.txt` in this repo → Vim help file (`:help vproj`), installed with the plugin

They started as copies of each other but diverge unless manually synced.

## Backup

The mkdocs source on snuffletron is backed up automatically. Manual backups:

```bash
ssh snuffletron 'cp -r /home/mkdocs/vproj/docs /home/mkdocs/vproj/docs.bak.$(date +%Y%m%d-%H%M)'
```
