# Batch Tracker

A free, open-source grow-cycle tracker for mushroom/produce growers - rooms,
zones, bays, batches, harvests, costs, and yield forecasting. Single-page
static app (`index.html`), backed by your own free Supabase project. No
shared server, no subscription, no vendor lock-in - you own your data.

## Setup

**No installs, no terminal.** Open [`setup.html`](setup.html) in your
browser and follow the 5 steps - it copies the schema for you, and tests
your Project URL/anon key live before handing you a ready-to-use `config.js`
to download. New to this whole area? Paste [`SETUP-WITH-AI.md`](SETUP-WITH-AI.md)
to Claude or ChatGPT first and it'll walk you through it end to end,
including the GitHub/Supabase dashboard parts `setup.html` can't automate.

Prefer a terminal? `setup.js` does the same schema-push + config-write in
one command (`npm install && npm run setup`) - entirely optional, same end
result either way.

## Batch IDs, Block IDs & strains

Every batch gets a **Batch ID** assigned by the database when it's created:
`AADDD-LL` - 2-digit year + day of the year it was sown + batch number for
that day (e.g. `26279-02` = second batch sown on 6 Oct 2026). Every block
gets a **Block ID** built from it: `26279-02-17` = block 17 of that batch.
Up to 99 batches a day and 99 blocks a batch; IDs never change and block
numbers are never reused. Each batch can also have a **strain code** ("ID
Cepa", e.g. `BOCF`) shown next to its ID everywhere - the list lives in the
`mn_strains` table and is editable in the app under Settings -> Strains.

Block labels (Labels -> "One per block") carry a QR that opens that block;
in Incubation/Fruiting -> Place -> **Scan blocks**, scanning a block's
label records exactly which block went into each shelf slot.

Updating an existing install: re-run `schema.sql` in the Supabase SQL Editor
first. It adds the new tables/columns and gives every existing batch a Batch
ID from its inoculation date (and Block IDs for its blocks).

## Spawn (grain spawn bags)

Pipeline -> **Spawn** tracks spawn batches the same way as blocks (same IDs,
strains, labels and incubation shelves) but bag by bag: incubating -> ready
-> used / sold, or lost. A bag becomes "used" by itself when its ID is
entered on a new batch (blocks, or the next spawn generation - G2, G3...),
and that batch takes the bag's strain and cost. Spawn cost per bag is set by
grain under Costs -> Spawn; the "should be ready" alert uses each strain's
"Spawn ready (days)" under Settings -> Strains. Bought spawn: leave the bag
field empty and type its code under Spawn code.

## Data and the free Supabase plan

The app reads every table in pages of 1000 rows (Supabase's per-request
cap), re-reads only the table a save touched, keeps its offline copy in
IndexedDB, and loads archived batches' shelf history only when it's needed.
A busy year (~400 blocks + 100 spawn bags a week) is roughly 40 MB of the
free plan's 500 MB. Free projects pause after 7 days without use (data is
kept; restore it from the Supabase dashboard) and have no downloadable
backups - export your tables now and then, or move to Pro for daily backups.

## Analytics

`index.html` and `setup.html` include a small, disclosed, cookie-free visit
counter ([GoatCounter](https://www.goatcounter.com)) so the maintainer can
see roughly how much this template gets used - page views and which setup
steps get reached, nothing about your farm or your Supabase project, which
never leaves your own account. Delete the `<script data-goatcounter...>` tag
near the top of either file if you'd rather run with none at all.

## Support

This is free and gifted with no strings attached - no account of mine, no
subscription, nothing to maintain on your end. If it saves you real time and
you'd like to say thanks, there's a Ko-fi: **[ko-fi.com/farmeradam](https://ko-fi.com/farmeradam)**.
Entirely optional, never required to use or deploy this.

## License

Copyright (C) 2026 Markwood Mushrooms.
[AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.html), provided as-is with
no warranty - see [`LICENSE`](LICENSE). You're free to use, modify, and even
sell hosting/support around this - the one condition is that if you modify
it and let other users interact with your version over a network (including
just running it for your own farm's staff), you make your modified source
available to them too. That's the copyleft trade: free to build on, not free
to enclose - improvements stay part of the commons instead of disappearing
into someone's private, closed-off fork.

This is a self-hosted template: each grower runs their own copy against
their own Supabase project and is solely responsible for their own data,
backups, security configuration, and any costs on their own accounts. The
original author provides no support, uptime guarantee, or liability for any
individual deployment.
