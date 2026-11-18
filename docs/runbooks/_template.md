# The drill, as an instruction

<!-- Copy this file to short-slug.md and add a row to README.md and an entry
under Runbooks in SUMMARY.md. The title says what the drill does, for example
"Lose one control plane, then two". -->

<!-- One paragraph: what the drill breaks and why that matters. Then when I ran
it and the headline number, such as how long reads failed. Say where it runs:
my home server or my laptop, and how many terminals. -->

## Before I start

<!-- Everything that must be true first, one bullet each, and how I check it.
For example `just cluster-check` passes, or `just drill-watch` is running and
printed `Start the drill`. Say where the output is logged. -->

-

## Steps

<!-- Numbered steps, each an instruction with the exact commands and what I
expect to see. Someone else could follow them at 3 a.m. without me. The last
two steps are always "Prove it" and "Clean up". -->

### 1. First step

```bash
```

### 2. Prove it

<!-- The check that shows the drill worked, and the output that means it did. -->

### 3. Clean up

<!-- Put everything back the way "Before I start" found it. -->

## What I saw

<!-- One section per run, newest last. Real output, trimmed to the lines that
matter, with timings. If a run went wrong, say so and say what changed in the
steps. -->

### First run, D Month YYYY

## Why it works

<!-- Optional. The mechanism underneath, briefly: quorum, leases, offsets. Name
this section after the question it answers, for example "Why three or five".
Delete it if the steps speak for themselves. -->

## When it goes wrong

<!-- One section per failure I've seen or expect: the symptom as I'd notice it,
the cause and the fix. End with what I never do, if there's a tempting
shortcut that makes things worse. -->

### Symptom as I'd see it
