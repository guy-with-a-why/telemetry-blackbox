# Flight plan amended

*14 November 2026*

## What was done

I've re-planned the route. The plan had five Days of nine hours each, 09:00 to 18:00, and I fly this in the evenings after a full working day. A Day was always going to be three or four evenings. The Days are now legs. Each has a budget in evenings and a due date that assumes weekday evenings only, and the last leg lands on 4 December. This timeline is documented in the table in [#62](https://github.com/guy-with-a-why/telemetry-blackbox/issues/62).

## Why was it done that way

A plan that's late from its second day stops being a plan. By Monday the flight strip would have shown every waypoint red and told me nothing useful. Budgets in evenings make the strip honest again, and a weekend counts as time in hand.

The order changed too. The cluster now flies before the firmware, because it carries the most risk on the route and everything downstream runs on it. Five VMs have to share a 16 GB machine, and I bootstrap the control plane by hand. The firmware and the cluster don't meet until the data path leg, so flying the riskier one first costs nothing and puts the slack where I need it.

## What challenges were faced

Day 0 was planned at an hour. It took two evenings, about eight and a half hours. The bench itself was quick. Releases, README badges, this blog and a security policy all joined the scope on the way. Each was worth having and none of them fitted in the hour. The flight strip counted them as headwind, which is what it calls work added after takeoff. From here, new scope goes to Stretch unless it blocks a leg.

## What's next

Today [#3](https://github.com/guy-with-a-why/telemetry-blackbox/issues/3) lands. The firmware already boots in Renode and blinks the board's green LED, and I'm checking its memory map against the STM32F407VG datasheet before it merges. Once I'm happy with that the next focus will be the cluster, with four evenings to Friday 20 November. The biggest risk is memory, because I'm building the whole platform on one 16 GB laptop on purpose. If five VMs don't fit in 16 GB, I drop to one control plane on a VM and run the HA drills on `kind`, which runs a whole multi-node cluster in Docker for a fraction of the memory.
