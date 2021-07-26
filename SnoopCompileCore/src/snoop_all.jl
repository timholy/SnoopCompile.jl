"""
```
SnoopCompileCore.@snoop_all "output_filename" begin
    # Commands to execute
end
```

Runs provided commands *in the current process*, and records snoop compilation results for
all phases of the compiler supported by SnoopCompile: Inference, LLVM Optimization, Codegen.

Returns a tuple of four values:
- `tinf`: Results from `@snoopi_deep`
- `"snoopl.csv"`: File 1 of results for `@snoopl`
- `"snoopl.yaml"`: File 2 of results for `@snoopl`
- `"snoopc.csv"`: Results file for `@snoopc`
"""
macro snoop_all(fname_prefix, commands)
    snoopl_csv_f, snoopl_yaml_f, snoopc_csv_f =
        "$fname_prefix.snoopl.csv", "$fname_prefix.snoopl.yaml", "$fname_prefix.snoopc.csv"
    tinf = gensym(:tinf)
    esc(quote
        @snoopc pspawn=false $snoopc_csv_f begin
            @snoopl pspawn=false $snoopl_csv_f $snoopl_yaml_f begin
                global $tinf = @snoopi_deep begin
                    @eval $commands
                end
            end
        end;
        $tinf, $snoopl_csv_f, $snoopl_yaml_f, $snoopc_csv_f
    end)
end