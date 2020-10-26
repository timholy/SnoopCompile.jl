"""
    times, info = SnoopCompile.read_snoopl("func_names.csv", "llvm_timings.yaml")

Reads the log file produced by the compiler and returns the structured representations.
"""
function read_snoopl(func_csv_file, llvm_yaml_file)
    func_csv = CSV.File(func_csv_file, header=false, delim='\t', types=[String, String])
    llvm_yaml = YAML.load_file(llvm_yaml_file)

    jl_names = Dict(r[1] => r[2] for r in func_csv)

    try_get_jl_name(name) = if name in keys(jl_names)
        jl_names[name]
        else
            @warn "Couldn't find $name"
            name
        end

    times = [llvm_module["time_ns"] => [
        try_get_jl_name(name)
        for (name,_) in llvm_module["before"]
    ] for llvm_module in llvm_yaml]

    info = Dict(
        try_get_jl_name(name) => (;
            before = (;
                instructions = before_stats["instructions"],
                basicblocks = before_stats["basicblocks"],
            ),
            after = (;
                instructions = after_stats["instructions"],
                basicblocks = after_stats["basicblocks"],
            ),
        )
        for llvm_module in llvm_yaml
        for (name, before_stats) in llvm_module["before"]
        for (name, after_stats)  in llvm_module["after"]
    )


    # sort times so that the most costly items are displayed last
    return (sort(times), info)
end
