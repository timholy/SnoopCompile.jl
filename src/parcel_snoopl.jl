"""
    times, info = SnoopCompile.read_snoopl("func_names.csv", "llvm_timings.yaml")

Reads the log file produced by the compiler and returns the structured representations.
"""
function read_snoopl(func_csv_file, llvm_yaml_file; tmin_secs=0.0)
    func_csv = _read_snoopl_csv(func_csv_file)
    llvm_yaml = YAML.load_file(llvm_yaml_file)

    jl_names = Dict(r[1]::String => r[2]::String for r in func_csv)

    try_get_jl_name(name) = if name in keys(jl_names)
        jl_names[name]
        else
            @warn "Couldn't find $name"
            name
        end

    time_secs(llvm_module) = llvm_module["time_ns"] / 1e9

    times = [
        time_secs(llvm_module) => [
            try_get_jl_name(name)
            for (name,_) in llvm_module["before"]
        ] for llvm_module in llvm_yaml
        if time_secs(llvm_module) > tmin_secs
    ]

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
        if time_secs(llvm_module) > tmin_secs
    )


    # sort times so that the most costly items are displayed last
    return (sort(times), info)
end


"""
`SnoopCompile._read_snoopl_csv("compiledata.csv")` reads the log file produced by the
compiler and returns the function names as an array of pairs.
"""
function _read_snoopl_csv(filename)
    data = Vector{Pair{String,String}}()
    # Format is [^\t]+\t[^\t]+. That is, tab-separated entries. No quotations or other
    # whitespace are considered.
    for line in eachline(filename)
        c_name, jl_type = split2(line, '\t')
        (length(c_name) < 2 || length(jl_type) < 2) && continue
        push!(data, c_name => jl_type)
    end
    return data
end