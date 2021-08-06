# Reference

## Data collection

```@docs
@snoopr
@snoopi_deep
@snoopi
@snoopc
@snoopl
```

## GUIs

```@docs
flamegraph
pgdsgui
```

## Analysis of invalidations

```@docs
uinvalidated
invalidation_trees
precompile_blockers
filtermod
findcaller
```

## Analysis of `@snoopi_deep`

```@docs
flatten
exclusive
inclusive
accumulate_by_source
collect_for
staleinstances
inference_triggers
trigger_tree
suggest
isignorable
callerinstance
callingframe
skiphigherorder
InferenceTrigger
runtime_inferencetime
SnoopCompile.parcel
SnoopCompile.write
report_callee
report_callees
report_caller
```

## Other utilities

```@docs
SnoopCompile.read
SnoopCompile.read_snoopl
SnoopCompile.format_userimg
```

## Demos

```@docs
SnoopCompile.flatten_demo
SnoopCompile.itrigs_demo
SnoopCompile.itrigs_higherorder_demo
```
