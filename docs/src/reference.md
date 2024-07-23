# Reference

## Data collection

```@docs
SnoopCompileCore.@snoop_invalidations
SnoopCompileCore.@snoop_inference
SnoopCompileCore.@snoop_llvm
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
report_invalidations
```

## Analysis of `@snoop_inference`

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

## Analysis of LLVM

```@docs
SnoopCompile.read_snoop_llvm
```

## Demos

```@docs
SnoopCompile.flatten_demo
SnoopCompile.itrigs_demo
SnoopCompile.itrigs_higherorder_demo
```
